import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:flutter_test/flutter_test.dart';

EphemeralPeerFlash _flash({
  int peerId = 7,
  String? nodeId = 'node-peer',
  bool isPending = false,
}) => EphemeralPeerFlash(
  peerId: peerId,
  peerName: 'Peer',
  nodeId: nodeId,
  connectedAt: DateTime(2026, 9, 29),
  isPending: isPending,
);

/// Which peer banners reach the screen. An accepted pairing is only announced
/// when the announcement carries something to do (the contact card
/// invitation); otherwise it stays as quiet as it has been since the banner
/// was restricted to pending requests.
void main() {
  test('a pending request is shown', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(isPending: true));
    expect(provider.allEphemeralFlashes, hasLength(1));
  });

  test('an accepted pairing stays silent by default', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash());
    expect(provider.allEphemeralFlashes, isEmpty);
  });

  test('an accepted pairing is shown when the caller asks for it', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(), showAccepted: true);
    expect(provider.allEphemeralFlashes.single.isPending, isFalse);
  });

  test('accepting replaces the pending banner of the same peer', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(isPending: true));
    provider.addEphemeralPeer(_flash(), showAccepted: true);

    expect(provider.allEphemeralFlashes, hasLength(1));
    expect(provider.allEphemeralFlashes.single.isPending, isFalse);
  });

  test('the replacement matches on node id too', () {
    // The outgoing screens key a peer on its URL hash, the detection poll on
    // its database id: the node id is what the two share.
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(peerId: 1, isPending: true));
    provider.addEphemeralPeer(_flash(peerId: 2), showAccepted: true);

    expect(provider.allEphemeralFlashes, hasLength(1));
    expect(provider.allEphemeralFlashes.single.peerId, 2);
  });

  test('a peer is announced as accepted once per session', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(), showAccepted: true);
    provider.dismissEphemeral(7);
    provider.addEphemeralPeer(_flash(), showAccepted: true);
    expect(provider.allEphemeralFlashes, isEmpty);
  });

  test('a late pending signal does not undo an accepted banner', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(), showAccepted: true);
    provider.addEphemeralPeer(_flash(isPending: true));

    expect(provider.allEphemeralFlashes, hasLength(1));
    expect(provider.allEphemeralFlashes.single.isPending, isFalse);
  });

  test('other peers are left alone', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(
      _flash(peerId: 1, nodeId: 'node-a', isPending: true),
    );
    provider.addEphemeralPeer(
      _flash(peerId: 2, nodeId: 'node-b'),
      showAccepted: true,
    );
    expect(provider.allEphemeralFlashes, hasLength(2));
  });

  test('accepting always clears the pending banner, shown or not', () {
    // With nothing to invite to, the accepted banner stays silent, but the
    // request it answered is settled: "Review" would open an empty list.
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(_flash(isPending: true));
    provider.addEphemeralPeer(_flash());
    expect(provider.allEphemeralFlashes, isEmpty);
  });

  test('the contacts screen leaves pending requests to its own banner', () {
    final provider = FlashMessageProvider();
    provider.addEphemeralPeer(
      _flash(peerId: 1, nodeId: 'node-a', isPending: true),
    );
    provider.addEphemeralPeer(
      _flash(peerId: 2, nodeId: 'node-b'),
      showAccepted: true,
    );

    expect(
      provider.visibleEphemeralFlashesOn('/network').map((f) => f.peerId),
      [2],
    );
    expect(provider.visibleEphemeralFlashesOn('/books'), hasLength(2));
  });
}
