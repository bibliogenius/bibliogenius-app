import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/avatar_config.dart';
import '../models/gamification_status.dart';
import '../models/leaderboard_entry.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/ffi_service.dart';
import '../services/mdns_service.dart';
import '../services/translation_service.dart';
import '../widgets/avatar_customizer.dart';
import '../widgets/gamification_widgets.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/invite_share_sheet.dart';
import '../widgets/network_leaderboard_card.dart';

class ProfileScreen extends StatefulWidget {
  final String? initialAction;

  const ProfileScreen({super.key, this.initialAction});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileCache {
  static Map<String, dynamic>? _statusData;
  static DateTime? _cachedAt;
  static const _ttl = Duration(seconds: 60);

  static Map<String, dynamic>? get() {
    if (_statusData != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _ttl) {
      return _statusData;
    }
    return null;
  }

  static void set(Map<String, dynamic> data) {
    _statusData = data;
    _cachedAt = DateTime.now();
  }

  static void invalidate() {
    _statusData = null;
    _cachedAt = null;
  }
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userStatus;
  Map<String, List<LeaderboardEntry>>? _leaderboard;
  String? _lastRefreshed;
  String? _error;
  int _peerViews = 0;
  int _followerViews = 0;
  int _followerCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _fetchViewStats();
    _fetchFollowerCount();
  }

  Future<void> _fetchStatus() async {
    // Check cache first for instant display
    final cached = _ProfileCache.get();
    if (cached != null) {
      setState(() {
        _userStatus = cached;
        _isLoading = false;
      });
      // Refresh in background (non-blocking)
      _fetchFresh(showLoading: false);
      return;
    }

    await _fetchFresh(showLoading: true);
  }

  Future<void> _fetchFresh({required bool showLoading}) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Retroactively unlock pending achievements (e.g. first_book for existing libraries)
      if (apiService.useFfi) {
        try {
          await FfiService().checkAchievements();
        } catch (e) {
          debugPrint('Achievement check failed (non-blocking): $e');
        }
      }

      // Parallel: status + config
      final results = await Future.wait([
        apiService.getUserStatus(),
        apiService.getLibraryConfig(),
      ]);
      final statusRes = results[0];
      final configRes = results[1];

      if (!mounted) return;

      // Library name is managed by ThemeProvider (SharedPreferences + FFI)
      final themeProvider = Provider.of<ThemeProvider>(
        context,
        listen: false,
      );

      // Sync profile type
      final profileType = configRes.data['profile_type'];
      if (profileType != null) {
        themeProvider.setProfileType(profileType);
      }

      // Cache and show profile immediately
      _ProfileCache.set(statusRes.data);
      setState(() {
        _userStatus = statusRes.data;
        _isLoading = false;
      });

      // Defer leaderboard (non-blocking)
      if (themeProvider.networkGamificationEnabled) {
        _fetchLeaderboard(apiService, themeProvider.libraryName);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchLeaderboard(
    ApiService apiService,
    String localName,
  ) async {
    try {
      final leaderboardRes = await apiService.refreshLeaderboard();
      if (!mounted || leaderboardRes.statusCode != 200) return;

      final data = leaderboardRes.data as Map<String, dynamic>;
      final leaderboard = <String, List<LeaderboardEntry>>{};
      for (final domain in [
        'collector',
        'reader',
        'lender',
        'cataloguer',
      ]) {
        leaderboard[domain] =
            (data[domain] as List<dynamic>?)
                ?.map((e) {
                  final entry = LeaderboardEntry.fromJson(
                    e as Map<String, dynamic>,
                  );
                  // Override self entry name with ThemeProvider name
                  // (DB may be stale in FFI mode)
                  if (entry.isSelf && localName != 'My Library') {
                    return LeaderboardEntry(
                      libraryName: localName,
                      level: entry.level,
                      current: entry.current,
                      isSelf: true,
                      peerId: entry.peerId,
                    );
                  }
                  return entry;
                })
                .toList() ??
            [];
      }

      setState(() {
        _leaderboard = leaderboard;
        _lastRefreshed = data['last_refreshed'] as String?;
      });
    } catch (e) {
      debugPrint('Leaderboard fetch failed: $e');
    }
  }

  Future<void> _refreshStatus() async {
    _ProfileCache.invalidate();
    await _fetchFresh(showLoading: false);
    _fetchViewStats();
    _fetchFollowerCount();
  }

  Future<void> _fetchViewStats() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      if (apiService.useFfi) {
        final data = await FfiService().getLibraryViewStats();
        if (!mounted) return;
        setState(() {
          _peerViews = (data['total_peer'] as num?)?.toInt() ?? 0;
          _followerViews = (data['total_follower'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      debugPrint('View stats fetch failed: $e');
    }
  }

  Future<void> _fetchFollowerCount() async {
    try {
      final dirProvider =
          Provider.of<HubDirectoryProvider>(context, listen: false);
      await dirProvider.loadFollowers();
      if (!mounted) return;
      setState(() {
        _followerCount =
            dirProvider.followers.where((f) => f.isActive).length;
      });
    } catch (e) {
      debugPrint('Follower count fetch failed: $e');
    }
  }

  Widget _buildFollowerCountChip(BuildContext context) {
    if (_followerCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label:
            '$_followerCount ${TranslationService.translate(context, _followerCount == 1 ? 'profile_follower' : 'profile_followers')}',
        child: Chip(
          avatar: Icon(
            Icons.people_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          label: Text(
            '$_followerCount ${TranslationService.translate(context, _followerCount == 1 ? 'profile_follower' : 'profile_followers')}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          side: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildViewCountChip(BuildContext context) {
    final total = _peerViews + _followerViews;
    if (total == 0) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label:
            '${TranslationService.translate(context, 'profile_views')}: $total',
        child: Tooltip(
          message: _peerViews > 0 && _followerViews > 0
              ? '$_peerViews ${TranslationService.translate(context, 'profile_views_peers')}, '
                  '$_followerViews ${TranslationService.translate(context, 'profile_views_followers')}'
              : '',
          child: Chip(
            avatar: Icon(
              Icons.visibility_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            label: Text(
              '$total ${TranslationService.translate(context, total == 1 ? 'profile_view' : 'profile_views')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            side: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'profile'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                '${TranslationService.translate(context, 'error')}: $_error',
              ),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_userStatus == null) {
      return Center(
        child: Text(TranslationService.translate(context, 'no_data')),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshStatus,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: MediaQuery.of(context).size.width > 600 ? 32.0 : 16.0,
          vertical: 24.0,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width > 600
                  ? 900
                  : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    final themeColor = Theme.of(context).primaryColor;
                    return Stack(
                      children: [
                        Semantics(
                          image: true,
                          label: TranslationService.translate(context, 'profile_avatar'),
                          child: Container(
                            width: 140,
                            height: 140,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: themeColor, width: 4),
                              color: themeProvider.avatarConfig?.style == 'genie'
                                  ? Color(
                                      int.parse(
                                        'FF${themeProvider.avatarConfig?.genieBackground ?? "fbbf24"}',
                                        radix: 16,
                                      ),
                                    )
                                  : Colors.grey[100],
                            ),
                            child: ClipOval(
                              child:
                                  (themeProvider.avatarConfig?.isGenie ?? false)
                                  ? Image.asset(
                                      themeProvider.avatarConfig?.assetPath ??
                                          'assets/genie_mascot.jpg',
                                      fit: BoxFit.cover,
                                    )
                                  : CachedNetworkImage(
                                      imageUrl:
                                          themeProvider.avatarConfig?.toUrl(
                                            size: 140,
                                            format: 'png',
                                          ) ??
                                          '',
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) =>
                                          const Icon(
                                            Icons.person,
                                            size: 60,
                                            color: Colors.grey,
                                          ),
                                    ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Semantics(
                            button: true,
                            label: TranslationService.translate(context, 'tooltip_edit_avatar'),
                            child: GestureDetector(
                              onTap: () =>
                                  _showAvatarPicker(context, themeProvider),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Library Name (editable)
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    final libraryName = themeProvider.libraryName;
                    return GestureDetector(
                      onTap: () => _showEditLibraryNameDialog(libraryName),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              libraryName,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: Colors.grey[400],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 4),

                // Share invite link (discreet)
                TextButton.icon(
                  onPressed: () => showInviteShareSheet(context),
                  icon: Icon(
                    Icons.share_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    TranslationService.translate(
                        context, 'profile_share_invite'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                const SizedBox(height: 8),

                // Library View Counter
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    if (!themeProvider.showViewCount) {
                      return const SizedBox.shrink();
                    }
                    return _buildViewCountChip(context);
                  },
                ),

                // Follower count
                _buildFollowerCountChip(context),

                // Gamification Card
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    if (!themeProvider.gamificationEnabled) {
                      return const SizedBox.shrink();
                    }
                    return GamificationSummaryCard(
                      status: GamificationStatus.fromJson(_userStatus!),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Reading Goals
                _buildReadingGoalsSection(),
                const SizedBox(height: 16),

                // Quick Statistics Summary
                _buildStatsSummarySection(),
                const SizedBox(height: 16),

                // Network Leaderboard Card
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    if (!themeProvider.networkGamificationEnabled ||
                        _leaderboard == null) {
                      return const SizedBox.shrink();
                    }
                    return NetworkLeaderboardCard(
                      leaderboard: _leaderboard!,
                      lastRefreshed: _lastRefreshed,
                      onRefresh: _refreshStatus,
                    );
                  },
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingGoalsSection() {
    // Get current goals from status
    final yearlyGoal = _userStatus?['config']?['reading_goal_yearly'] ?? 12;
    final booksRead = _userStatus?['config']?['reading_goal_progress'] ?? 0;
    final yearlyProgress = yearlyGoal > 0
        ? (booksRead / yearlyGoal).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Yearly Goal Card
        _buildGoalCard(
          icon: Icons.calendar_today,
          color: Colors.teal,
          title: TranslationService.translate(context, 'yearly_goal'),
          subtitle:
              '$yearlyGoal ${TranslationService.translate(context, 'books_per_year')}',
          progress: yearlyProgress,
          current: booksRead,
          onEdit: () => _showEditGoalDialog(yearlyGoal, isMonthly: false),
        ),

        // TODO: Monthly goals per month (backlog)
      ],
    );
  }

  Widget _buildStatsSummarySection() {
    final tracks = _userStatus?['tracks'] as Map<String, dynamic>?;
    final config = _userStatus?['config'] as Map<String, dynamic>?;
    final streak = _userStatus?['streak'] as Map<String, dynamic>?;

    final totalBooks =
        (tracks?['collector']?['current'] as num?)?.toInt() ?? 0;
    final booksRead = (config?['total_books_read'] as num?)?.toInt() ?? 0;
    final currentStreak = (streak?['current'] as num?)?.toInt() ?? 0;
    final booksThisYear =
        (config?['reading_goal_progress'] as num?)?.toInt() ?? 0;

    if (totalBooks == 0 && booksRead == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.2),
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.insights,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  TranslationService.translate(
                    context,
                    'profile_stats_title',
                  ).toUpperCase(),
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatMiniCard(
                  theme,
                  Icons.menu_book,
                  totalBooks.toString(),
                  TranslationService.translate(context, 'my_books'),
                  const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatMiniCard(
                  theme,
                  Icons.check_circle,
                  booksRead.toString(),
                  TranslationService.translate(context, 'stat_read'),
                  const Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatMiniCard(
                  theme,
                  Icons.local_fire_department,
                  currentStreak.toString(),
                  TranslationService.translate(context, 'reading_streak'),
                  const Color(0xFFEF4444),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatMiniCard(
                  theme,
                  Icons.calendar_today,
                  booksThisYear.toString(),
                  TranslationService.translate(
                    context,
                    'books_finished_year',
                  ),
                  const Color(0xFFF97316),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => context.push('/dashboard?tab=1'),
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: Text(
                TranslationService.translate(context, 'see_more_stats'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMiniCard(
    ThemeData theme,
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required double progress,
    required int current,
    required VoidCallback onEdit,
    bool isOptional = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withValues(alpha: 0.2),
                          color.withValues(alpha: 0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isOptional ? Icons.add_circle_outline : Icons.edit_outlined,
                    color: Colors.grey[500],
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                subtitle.split(' ').first,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey[800],
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                subtitle.split(' ').skip(1).join(' '),
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          if (!isOptional && progress > 0) ...[
            const SizedBox(height: 20),
            Semantics(
              label: '${TranslationService.translate(context, 'progress')} : ${(progress * 100).toInt()}%, $current ${TranslationService.translate(context, 'books_read')}',
              child: Stack(
              children: [
                Container(
                  height: 10,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      height: 10,
                      width: constraints.maxWidth * progress,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [color, color.withValues(alpha: 0.8)],
                        ),
                        borderRadius: BorderRadius.circular(5),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$current ${TranslationService.translate(context, 'books_read')}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: progress >= 1.0
                        ? Colors.green[50]
                        : color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: progress >= 1.0 ? Colors.green[700] : color,
                    ),
                  ),
                ),
              ],
            ),
            if (progress >= 1.0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.emoji_events_rounded,
                        color: Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        TranslationService.translate(
                          context,
                          'goal_reached_congrats',
                        ),
                        style: TextStyle(
                          color: Colors.green[800],
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _showEditGoalDialog(
    int currentGoal, {
    required bool isMonthly,
  }) async {
    double sliderValue = currentGoal > 0
        ? currentGoal.toDouble()
        : (isMonthly ? 2.0 : 12.0);
    final color = isMonthly ? Colors.orange : Colors.teal;
    final maxValue = isMonthly ? 20.0 : 100.0;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            TranslationService.translate(
              context,
              isMonthly ? 'edit_monthly_goal' : 'edit_yearly_goal',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${sliderValue.toInt()} ${TranslationService.translate(context, isMonthly ? 'books_per_month' : 'books_per_year')}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 24),
              Slider(
                value: sliderValue,
                min: isMonthly ? 0 : 1,
                max: maxValue,
                divisions: maxValue.toInt() - (isMonthly ? 0 : 1),
                activeColor: color,
                label:
                    '${sliderValue.toInt()} ${TranslationService.translate(context, 'books')}',
                onChanged: (value) {
                  setState(() => sliderValue = value);
                },
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isMonthly
                        ? '0 (${TranslationService.translate(context, 'disabled')})'
                        : '1 ${TranslationService.translate(context, 'book')}',
                  ),
                  Text(
                    '${maxValue.toInt()} ${TranslationService.translate(context, 'books')}',
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(TranslationService.translate(context, 'cancel')),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await _updateReadingGoal(
                  sliderValue.toInt(),
                  isMonthly: isMonthly,
                );
              },
              style: FilledButton.styleFrom(backgroundColor: color),
              child: Text(TranslationService.translate(context, 'save')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateReadingGoal(
    int newGoal, {
    required bool isMonthly,
  }) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      if (isMonthly) {
        await api.updateGamificationConfig(readingGoalMonthly: newGoal);
      } else {
        await api.updateGamificationConfig(readingGoalYearly: newGoal);
      }
      _ProfileCache.invalidate();
      _fetchStatus(); // Refresh
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'goal_updated'),
            ),
            backgroundColor: isMonthly ? Colors.orange : Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_updating')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showEditLibraryNameDialog(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'edit_library_name'),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: TranslationService.translate(context, 'library_name'),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(TranslationService.translate(context, 'save')),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && result != currentName) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        await api.updateLibraryConfig(name: result);
        if (mounted) {
          final themeProvider = Provider.of<ThemeProvider>(
            context,
            listen: false,
          );
          themeProvider.setLibraryName(result);
          // Restart mDNS with updated library name
          if (themeProvider.networkDiscoveryEnabled) {
            try {
              await MdnsService.stop();
              final authService =
                  Provider.of<AuthService>(context, listen: false);
              final libraryUuid =
                  await authService.getOrCreateLibraryUuid();
              await MdnsService.startAnnouncing(
                result,
                ApiService.httpPort,
                libraryId: libraryUuid,
              );
              await MdnsService.startDiscovery();
            } catch (e) {
              debugPrint('mDNS restart after name change failed: $e');
            }
          }
          // Update hub profile with new name (if registered)
          try {
            final hubProvider = Provider.of<HubDirectoryProvider>(
              context,
              listen: false,
            );
            final hubConfig = hubProvider.config;
            if (hubConfig != null) {
              final bookCount = await FfiService().countBooks();
              await hubProvider.register(
                nodeId: hubConfig.nodeId,
                displayName: result,
                bookCount: bookCount,
                isListed: hubConfig.isListed,
                requiresApproval: hubConfig.requiresApproval,
                acceptFrom: hubConfig.acceptFrom,
                allowBorrowing: hubConfig.allowBorrowing,
              );
            }
          } catch (e) {
            debugPrint('Hub name update failed: $e');
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'library_updated'),
              ),
            ),
          );
          // Refresh leaderboard with the new name to avoid stale/duplicate entries
          _fetchLeaderboard(api, result);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'error')}: $e',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _showAvatarPicker(BuildContext context, ThemeProvider themeProvider) {
    // Create a local copy of the config to avoid updating the provider immediately
    // This allows the user to cancel changes
    AvatarConfig currentConfig =
        themeProvider.avatarConfig ?? AvatarConfig.defaultConfig;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SizedBox(
              height: MediaQuery.of(context).size.height * 0.85,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          TranslationService.translate(
                            context,
                            'customize_avatar',
                          ),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AvatarCustomizer(
                      initialConfig: currentConfig,
                      onConfigChanged: (newConfig) {
                        setState(() {
                          currentConfig = newConfig;
                        });
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () async {
                          try {
                            // Show loading indicator if needed, or just close and update
                            final api = Provider.of<ApiService>(
                              context,
                              listen: false,
                            );
                            await themeProvider.setAvatarConfig(
                              currentConfig,
                              apiService: api,
                            );

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    TranslationService.translate(
                                      context,
                                      'avatar_updated',
                                    ),
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${TranslationService.translate(context, 'error_saving_avatar')}: $e',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                        child: Text(
                          TranslationService.translate(context, 'save_changes'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
