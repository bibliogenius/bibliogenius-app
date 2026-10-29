import 'package:bibliogenius/models/hub_directory.dart';
import 'package:bibliogenius/models/library_relation.dart';
import 'package:bibliogenius/models/network_member.dart';
import 'package:flutter_test/flutter_test.dart';

const _node = 'node-uuid';

HubFollow _follow(String status) => HubFollow(
  id: 1,
  followerNodeId: 'self',
  followedNodeId: _node,
  status: status,
  createdAt: '2026-10-22T00:00:00Z',
);

NetworkMember _peer(String status) => NetworkMember(
  id: 7,
  name: 'Paired library',
  type: NetworkMemberType.library,
  source: NetworkMemberSource.network,
  status: status,
);

void main() {
  group('LibraryRelation.canUnfollow', () {
    test('a hub follow alone can be withdrawn', () {
      final relation = LibraryRelation(
        nodeId: _node,
        follow: _follow('active'),
      );
      expect(relation.canUnfollow, isTrue);
    });

    test('a pending follow cannot be withdrawn yet', () {
      final relation = LibraryRelation(
        nodeId: _node,
        follow: _follow('pending'),
      );
      expect(relation.canUnfollow, isFalse);
    });

    test('a paired peer keeps its follow: deleting the contact ends both', () {
      // The follow materialises the pairing (ADR-053) and is requested
      // again at the next launch, so withdrawing it alone only confuses.
      final relation = LibraryRelation(
        nodeId: _node,
        peer: _peer('connected'),
        follow: _follow('active'),
      );
      expect(relation.canUnfollow, isFalse);
    });

    test('a pairing still pending leaves the follow withdrawable', () {
      // Nothing materialises yet: the follow stands on its own until the
      // pairing is accepted.
      final relation = LibraryRelation(
        nodeId: _node,
        peer: _peer('pending'),
        follow: _follow('active'),
      );
      expect(relation.canUnfollow, isTrue);
    });
  });
}
