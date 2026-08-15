// Incoming hub follow requests: the collapsible section on the contacts tab,
// the card for a single request, and the sheet that holds the overflow when
// more requests arrive than the section previews inline.
//
// Lives in widgets/ rather than inside network_screen.dart so the screen file
// stays a composition of sections, per the file-size rule in
// .agents/instructions/flutter-frontend.md.

import 'package:flutter/material.dart';

import '../models/hub_directory.dart';
import '../providers/hub_directory_provider.dart';
import '../services/translation_service.dart';

/// How many request cards the inline preview renders before collapsing the
/// rest behind the "see all" link. The section sits on top of the contacts
/// list, so its height must stay bounded no matter how many requests land.
const int _kInlineRequestsPreview = 2;

/// Expandable section showing incoming hub follow requests with approve/reject/block.
class HubRequestsSection extends StatefulWidget {
  final List<HubFollow> requests;
  final HubDirectoryProvider provider;

  /// When true, render a small explainer below the header to clarify that the
  /// public directory is currently disabled but legacy pending requests still
  /// exist server-side and can be resolved from here.
  final bool showDisabledHint;

  const HubRequestsSection({
    super.key,
    required this.requests,
    required this.provider,
    this.showDisabledHint = false,
  });

  @override
  State<HubRequestsSection> createState() => HubRequestsSectionState();
}

class HubRequestsSectionState extends State<HubRequestsSection> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final count = widget.requests.length;
    final theme = Theme.of(context);
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Semantics(
            header: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              child: Row(
                children: [
                  Icon(
                    Icons.how_to_reg,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${TranslationService.translate(context, 'network_hub_requests_title')} ($count)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: theme.colorScheme.error,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          if (widget.showDisabledHint)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                TranslationService.translate(
                  context,
                  'hub_pending_legacy_note',
                ),
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ...widget.requests
              .take(_kInlineRequestsPreview)
              .map(
                (follow) => HubFollowRequestTile(
                  follow: follow,
                  provider: widget.provider,
                ),
              ),
          if (count > _kInlineRequestsPreview)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Center(
                child: TextButton.icon(
                  key: const Key('hubRequestsSeeAll'),
                  onPressed: () =>
                      showHubFollowRequestsSheet(context, widget.provider),
                  icon: const Icon(Icons.chevron_right, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: Text(
                    TranslationService.translate(
                      context,
                      'directory_requests_see_all',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Full list of incoming follow requests, in a scrollable modal sheet.
///
/// The inline section only previews the first [_kInlineRequestsPreview]
/// requests; this sheet is the overflow surface. It listens to [provider]
/// directly (rather than through a `Consumer`) so it keeps updating while the
/// list drains under the user's taps, whatever the provider scope of the
/// route that opened it.
Future<void> showHubFollowRequestsSheet(
  BuildContext context,
  HubDirectoryProvider provider,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return ListenableBuilder(
            listenable: provider,
            builder: (context, _) {
              final requests = provider.pendingRequests;
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Semantics(
                      header: true,
                      child: Text(
                        '${TranslationService.translate(context, 'network_hub_requests_title')} (${requests.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: requests.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                TranslationService.translate(
                                  context,
                                  'directory_requests_empty',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.only(bottom: 16),
                            itemCount: requests.length,
                            itemBuilder: (context, index) =>
                                HubFollowRequestTile(
                                  follow: requests[index],
                                  provider: provider,
                                ),
                          ),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

/// Single incoming follow request card.
///
/// Library names are generated from the device name, so they are long by
/// default: the name owns a full-width line here instead of competing with
/// the actions, which carry text labels rather than colour-coded icons (a
/// green check and an orange ban are indistinguishable without the tooltip,
/// which never shows on touch). Block sits in the overflow menu so the
/// hardest action to undo is not one thumb-width away from "approve".
class HubFollowRequestTile extends StatelessWidget {
  final HubFollow follow;
  final HubDirectoryProvider provider;

  const HubFollowRequestTile({
    super.key,
    required this.follow,
    required this.provider,
  });

  Future<void> _approve() async {
    // Seal contact info for the follower if available
    String? blob;
    final key = follow.followerX25519PublicKey;
    if (key != null && key.isNotEmpty) {
      blob = await provider.sealContactFor(key);
    }
    await provider.resolveFollow(follow.id, 'approve', encryptedContact: blob);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedName =
        follow.followerDisplayName ??
        provider.displayNameFor(follow.followerNodeId);
    final hasName = resolvedName != null && resolvedName.isNotEmpty;
    final label = hasName ? resolvedName : follow.followerNodeId;
    final subtitle = TranslationService.translate(
      context,
      'directory_wants_to_follow_you',
    );
    final busy = provider.isResolvingFollow(follow.id);

    return Semantics(
      // container: the card is not tappable any more (the buttons are), so it
      // needs its own node to announce whose request this is before a screen
      // reader reaches the actions.
      container: true,
      label: '$label, $subtitle',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      label.isNotEmpty ? label[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          // Generated names run 25-35 characters: two lines fit
                          // them whole on a phone, ellipsis is the last resort.
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: hasName
                              ? const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                )
                              : const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    enabled: !busy,
                    tooltip: TranslationService.translate(
                      context,
                      'more_actions',
                    ),
                    icon: const Icon(Icons.more_vert),
                    onSelected: (_) =>
                        provider.resolveFollow(follow.id, 'block'),
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'block',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.block,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            TranslationService.translate(
                              context,
                              'directory_block',
                            ),
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Wrap, not Row: at large text scales the two labels drop onto
              // separate lines instead of overflowing.
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => provider.resolveFollow(follow.id, 'reject'),
                    child: Text(
                      TranslationService.translate(context, 'directory_reject'),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : _approve,
                    icon: busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      TranslationService.translate(
                        context,
                        'directory_approve',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
