import 'package:flutter/material.dart';

import 'bookshops_section.dart';
import 'search_sources_section.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Find books section: where lookups go (search sources), then where to
/// buy or borrow (bookshops and libraries).
class FindBooksSettingsSection extends StatelessWidget {
  const FindBooksSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    if (!settingsMatches(context, [
      ...searchSourcesSearchKeys,
      ...bookshopsSearchKeys,
    ])) {
      return const SizedBox.shrink();
    }
    return const SettingsSection(
      name: 'find-books',
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SearchSourcesSettings(),
        Divider(height: 1),
        SizedBox(height: 12),
        BookshopsSettings(),
      ],
    );
  }
}
