import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/device_sync_provider.dart';
import '../services/translation_service.dart';
import '../src/rust/api/frb.dart' as frb;
import '../theme/app_design.dart';

class SyncReviewScreen extends StatefulWidget {
  const SyncReviewScreen({super.key});

  @override
  State<SyncReviewScreen> createState() => _SyncReviewScreenState();
}

class _SyncReviewScreenState extends State<SyncReviewScreen> {
  late DeviceSyncProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<DeviceSyncProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _provider.loadPendingReview();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'sync_review_title'),
          ),
        ),
      ),
      body: Consumer<DeviceSyncProvider>(
        builder: (context, provider, _) {
          if (provider.isLoadingReview) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.pendingReview.isEmpty) {
            return _buildEmptyState(theme);
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadPendingReview(),
            child: CustomScrollView(
              slivers: [
                // Info banner
                SliverToBoxAdapter(child: _buildInfoBanner(provider, theme)),
                // Action bar
                SliverToBoxAdapter(child: _buildActionBar(provider, theme)),
                // Operation list
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _buildOpCard(provider.pendingReview[index], theme),
                    childCount: provider.pendingReview.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoBanner(DeviceSyncProvider provider, ThemeData theme) {
    final count = provider.pendingReviewCount;
    final message = TranslationService.translate(
      context,
      'sync_review_banner',
    ).replaceFirst('%d', count.toString());

    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: AppDesign.refinedOceanGradient,
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        ),
        child: Row(
          children: [
            const Icon(Icons.sync_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar(DeviceSyncProvider provider, ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: TranslationService.translate(
                    context,
                    'sync_review_approve_all',
                  ),
                  child: FilledButton.icon(
                    onPressed: () => _approveAll(provider),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      TranslationService.translate(
                        context,
                        'sync_review_approve_all',
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message: TranslationService.translate(
                    context,
                    'sync_review_reject_all',
                  ),
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectAll(provider),
                    icon: Icon(
                      Icons.cancel_outlined,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                    label: Text(
                      TranslationService.translate(
                        context,
                        'sync_review_reject_all',
                      ),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: theme.colorScheme.error),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextButton.icon(
            onPressed: () => _resetAll(provider),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: Text(
              TranslationService.translate(context, 'sync_reset_all'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOpCard(frb.FrbPendingReviewOp op, ThemeData theme) {
    final time = _formatTime(op.createdAt);
    final sourceName = _formatSource(op.source);

    return Semantics(
      label:
          '${op.operation} ${op.entityType} #${op.entityId}, '
          '${TranslationService.translate(context, 'sync_review_from')} $sourceName',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: operation badge + entity type + ID
              Row(
                children: [
                  _operationBadge(op.operation, theme),
                  const SizedBox(width: 8),
                  Text(
                    op.entityType,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '#${op.entityId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              // Payload summary (if present)
              if (op.payload != null && op.payload!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _summarizePayload(op.payload!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 4),
              // Source
              Text(
                '${TranslationService.translate(context, 'sync_review_from')} '
                '$sourceName',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Tooltip(
                    message: TranslationService.translate(
                      context,
                      'tooltip_reject_op',
                    ),
                    child: TextButton(
                      onPressed: () => _rejectOp(op.id),
                      child: Text(
                        TranslationService.translate(
                          context,
                          'sync_review_reject',
                        ),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: TranslationService.translate(
                      context,
                      'tooltip_approve_op',
                    ),
                    child: FilledButton(
                      onPressed: () => _approveOp(op.id),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      child: Text(
                        TranslationService.translate(
                          context,
                          'sync_review_approve',
                        ),
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

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            TranslationService.translate(context, 'sync_review_empty_title'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(context, 'sync_review_empty_subtitle'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _operationBadge(String operation, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    Color bg;
    Color fg;
    switch (operation) {
      case 'INSERT':
        bg = isDark ? Colors.green.shade900 : Colors.green.shade50;
        fg = isDark ? Colors.green.shade300 : Colors.green.shade700;
        break;
      case 'UPDATE':
        bg = isDark ? Colors.blue.shade900 : Colors.blue.shade50;
        fg = isDark ? Colors.blue.shade300 : Colors.blue.shade700;
        break;
      case 'DELETE':
        bg = isDark ? Colors.red.shade900 : Colors.red.shade50;
        fg = isDark ? Colors.red.shade300 : Colors.red.shade700;
        break;
      default:
        bg = isDark ? Colors.grey.shade800 : Colors.grey.shade100;
        fg = isDark ? Colors.grey.shade300 : Colors.grey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        operation,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  // Actions

  Future<void> _approveOp(int id) async {
    final count = await _provider.approveOps([id]);
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(
              context,
              'sync_review_approved',
            ).replaceFirst('%d', count.toString()),
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _rejectOp(int id) async {
    final count = await _provider.rejectOps([id]);
    if (!mounted) return;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(
              context,
              'sync_review_rejected',
            ).replaceFirst('%d', count.toString()),
          ),
        ),
      );
    }
  }

  Future<void> _approveAll(DeviceSyncProvider provider) async {
    final count = await provider.approveAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(
            context,
            'sync_review_approved',
          ).replaceFirst('%d', count.toString()),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _rejectAll(DeviceSyncProvider provider) async {
    final count = await provider.rejectAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(
            context,
            'sync_review_rejected',
          ).replaceFirst('%d', count.toString()),
        ),
      ),
    );
  }

  Future<void> _resetAll(DeviceSyncProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(context, 'sync_reset_all')),
        content: Text(
          TranslationService.translate(context, 'sync_reset_confirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              TranslationService.translate(context, 'delete'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final count = await provider.resetOperationLog();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Reset $count operations')));
  }

  // Helpers

  String _formatTime(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }

  String _formatSource(String source) {
    // source is "device:<id>" - extract the device name/id
    if (source.startsWith('device:')) {
      return 'Device ${source.substring(7)}';
    }
    return source;
  }

  String _summarizePayload(String payload) {
    // Try to extract meaningful info from JSON payload
    try {
      if (payload.length > 100) {
        return '${payload.substring(0, 97)}...';
      }
      return payload;
    } catch (_) {
      return payload;
    }
  }
}
