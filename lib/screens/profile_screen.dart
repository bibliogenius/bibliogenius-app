import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/avatar_config.dart';
import '../models/gamification_status.dart';
import '../models/leaderboard_entry.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../widgets/avatar_customizer.dart';
import '../widgets/gamification_widgets.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/network_leaderboard_card.dart';

class ProfileScreen extends StatefulWidget {
  final String? initialAction;

  const ProfileScreen({super.key, this.initialAction});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userStatus;
  Map<String, List<LeaderboardEntry>>? _leaderboard;
  String? _lastRefreshed;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final statusRes = await apiService.getUserStatus();
      final configRes = await apiService.getLibraryConfig();

      if (mounted) {
        // Sync library name
        final name = configRes.data['library_name'] ?? configRes.data['name'];
        if (name != null) {
          Provider.of<ThemeProvider>(
            context,
            listen: false,
          ).setLibraryName(name);
        }

        // Sync profile type
        final profileType = configRes.data['profile_type'];
        if (profileType != null) {
          Provider.of<ThemeProvider>(
            context,
            listen: false,
          ).setProfileType(profileType);
        }

        // Fetch leaderboard if network gamification is enabled
        final themeProvider = Provider.of<ThemeProvider>(
          context,
          listen: false,
        );
        if (themeProvider.networkGamificationEnabled) {
          try {
            final leaderboardRes = await apiService.refreshLeaderboard();
            if (mounted && leaderboardRes.statusCode == 200) {
              final data = leaderboardRes.data as Map<String, dynamic>;
              _leaderboard = {};
              for (final domain in [
                'collector',
                'reader',
                'lender',
                'cataloguer',
              ]) {
                _leaderboard![domain] =
                    (data[domain] as List<dynamic>?)
                        ?.map(
                          (e) => LeaderboardEntry.fromJson(
                            e as Map<String, dynamic>,
                          ),
                        )
                        .toList() ??
                    [];
              }
              _lastRefreshed = data['last_refreshed'] as String?;
            }
          } catch (e) {
            debugPrint('Leaderboard fetch failed: $e');
          }
        }

        setState(() {
          _userStatus = statusRes.data;
          _isLoading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'profile'),
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
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
      onRefresh: _fetchStatus,
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
                        Container(
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
                        Positioned(
                          bottom: 0,
                          right: 0,
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
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

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
                    );
                  },
                ),
                const SizedBox(height: 32),

                // Reading Goals
                _buildReadingGoalsSection(),

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
    final monthlyGoal = _userStatus?['config']?['reading_goal_monthly'] ?? 0;
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
        // Example: "Goal for December 2024: 3 books"
      ],
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
            Stack(
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
