import 'package:bibliogenius/utils/requests_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

// The "Demandes" tab of the loans screen holds up to three sub-tabs, each
// gated by its own module: Reçues (lend), Envoyées (borrow), Connexions
// (connection validation). A deep link naming a sub-tab must land on it
// whatever the modules currently enabled, or fall back to the first one when
// the sub-tab is hidden.

void main() {
  group('requestsSubTabIndex', () {
    test('every sub-tab visible: positions follow the display order', () {
      const all = RequestsSubTabs(
        canLend: true,
        canBorrow: true,
        showConnections: true,
      );
      expect(requestsSubTabIndex(all, 'received'), 0);
      expect(requestsSubTabIndex(all, 'sent'), 1);
      expect(requestsSubTabIndex(all, 'connections'), 2);
    });

    test('hidden sub-tabs shift the following ones left', () {
      const noLend = RequestsSubTabs(
        canLend: false,
        canBorrow: true,
        showConnections: true,
      );
      expect(requestsSubTabIndex(noLend, 'sent'), 0);
      expect(requestsSubTabIndex(noLend, 'connections'), 1);

      const onlyConnections = RequestsSubTabs(
        canLend: false,
        canBorrow: false,
        showConnections: true,
      );
      expect(requestsSubTabIndex(onlyConnections, 'connections'), 0);
    });

    test('a hidden or unknown sub-tab falls back to the first one', () {
      const noConnections = RequestsSubTabs(
        canLend: true,
        canBorrow: true,
        showConnections: false,
      );
      expect(requestsSubTabIndex(noConnections, 'connections'), 0);
      expect(requestsSubTabIndex(noConnections, 'anything'), 0);
      expect(requestsSubTabIndex(noConnections, null), 0);
    });

    test('the count matches the tabs actually shown, with a floor of one', () {
      expect(
        const RequestsSubTabs(
          canLend: true,
          canBorrow: false,
          showConnections: true,
        ).count,
        2,
      );
      expect(
        const RequestsSubTabs(
          canLend: false,
          canBorrow: false,
          showConnections: false,
        ).count,
        1,
      );
    });
  });

  test('the connections deep link names the Demandes tab and its sub-tab', () {
    expect(kConnectionRequestsRoute, '/requests?tab=requests&sub=connections');
  });
}
