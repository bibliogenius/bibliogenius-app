import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import '../theme/app_design.dart';

/// Always-pinned sliver that paints the app-bar gradient across the system
/// status bar area. Paired with [MediaQuery.removePadding] around the enclosing
/// [NestedScrollView], it guarantees the status bar stays covered even when
/// the floating [GenieSliverAppBar] has scrolled fully away.
class StatusBarCoverHeader extends SliverPersistentHeaderDelegate {
  final double height;
  final String themeStyle;

  const StatusBarCoverHeader({
    required this.height,
    required this.themeStyle,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppDesign.appBarGradientForTheme(themeStyle),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant StatusBarCoverHeader old) {
    return old.height != height || old.themeStyle != themeStyle;
  }
}

/// Pinned sliver header that hosts a [TabBar] and, optionally, an inline
/// search field (pattern 1 — icon expands into a full-width input within the
/// same row).
///
/// Designed to sit below a floating [GenieSliverAppBar] in a
/// [NestedScrollView], so the top AppBar collapses on scroll while the tab
/// navigation stays always reachable.
///
/// When search callbacks are left null, the search icon is not rendered.
class StickyTabsHeader extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final List<Tab> tabs;
  final ValueChanged<int>? onTabTap;
  final String themeStyle;

  // Optional inline search support
  final bool isSearching;
  final TextEditingController? searchController;
  final VoidCallback? onOpenSearch;
  final VoidCallback? onCloseSearch;
  final ValueChanged<String>? onSearchChanged;

  const StickyTabsHeader({
    required this.tabController,
    required this.tabs,
    required this.themeStyle,
    this.onTabTap,
    this.isSearching = false,
    this.searchController,
    this.onOpenSearch,
    this.onCloseSearch,
    this.onSearchChanged,
  });

  bool get _searchEnabled =>
      onOpenSearch != null &&
      onCloseSearch != null &&
      onSearchChanged != null &&
      searchController != null;

  static const double _rowHeight = 48;

  @override
  double get minExtent => _rowHeight;

  @override
  double get maxExtent => _rowHeight;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final gradient = AppDesign.appBarGradientForTheme(themeStyle);
    final showSearch = _searchEnabled && isSearching;
    return Container(
      decoration: BoxDecoration(gradient: gradient),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: showSearch
            ? _SearchRow(
                key: const ValueKey('sticky_tabs_search'),
                controller: searchController!,
                onClose: onCloseSearch!,
                onChanged: onSearchChanged!,
              )
            : _TabsRow(
                key: const ValueKey('sticky_tabs_tabs'),
                controller: tabController,
                tabs: tabs,
                onTap: onTabTap,
                onSearchTap: _searchEnabled ? onOpenSearch : null,
              ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant StickyTabsHeader old) {
    return old.isSearching != isSearching ||
        old.tabController != tabController ||
        old.tabs.length != tabs.length ||
        old.themeStyle != themeStyle ||
        old._searchEnabled != _searchEnabled;
  }
}

class _TabsRow extends StatelessWidget {
  final TabController controller;
  final List<Tab> tabs;
  final ValueChanged<int>? onTap;
  final VoidCallback? onSearchTap;

  const _TabsRow({
    super.key,
    required this.controller,
    required this.tabs,
    required this.onTap,
    required this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    final tabBar = TabBar(
      controller: controller,
      labelColor: Colors.white,
      unselectedLabelColor: Colors.white70,
      indicatorColor: Colors.white,
      indicatorWeight: 3,
      onTap: onTap,
      tabs: tabs,
    );
    if (onSearchTap == null) return tabBar;
    return Row(
      children: [
        Expanded(child: tabBar),
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white),
          tooltip: TranslationService.translate(context, 'search_books'),
          onPressed: onSearchTap,
        ),
      ],
    );
  }
}

class _SearchRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  const _SearchRow({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: TranslationService.translate(context, 'cancel'),
            onPressed: onClose,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: true,
              onChanged: onChanged,
              style: const TextStyle(color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText:
                    TranslationService.translate(context, 'search_books'),
                hintStyle: const TextStyle(color: Colors.white70),
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox(width: 48);
              return IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: TranslationService.translate(context, 'cancel'),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
