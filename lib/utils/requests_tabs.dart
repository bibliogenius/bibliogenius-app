/// Sub-tab layout of the "Demandes" tab on the loans screen.
///
/// Each sub-tab is gated by its own module, so the index of a given sub-tab
/// depends on which ones are visible. Kept pure so deep links can be tested
/// without building the screen.
class RequestsSubTabs {
  final bool canLend;
  final bool canBorrow;
  final bool showConnections;

  const RequestsSubTabs({
    required this.canLend,
    required this.canBorrow,
    required this.showConnections,
  });

  /// Visible sub-tabs, in display order.
  List<String> get visible => [
    if (canLend) 'received',
    if (canBorrow) 'sent',
    if (showConnections) 'connections',
  ];

  /// Number of sub-tabs to build; never zero, the tab bar needs one.
  int get count => visible.isEmpty ? 1 : visible.length;
}

/// Route that opens the pending connection requests directly.
const kConnectionRequestsRoute = '/requests?tab=requests&sub=connections';

/// Index of [subTab] among the visible sub-tabs, or 0 when it is hidden or
/// unknown, so a stale deep link still lands somewhere sensible.
int requestsSubTabIndex(RequestsSubTabs tabs, String? subTab) {
  if (subTab == null) return 0;
  final index = tabs.visible.indexOf(subTab);
  return index < 0 ? 0 : index;
}
