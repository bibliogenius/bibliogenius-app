import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/translation_service.dart';
import '../models/audio_resource.dart';

/// Compact audio player widget for streaming audiobooks.
///
/// Features:
/// - Play/pause toggle
/// - Progress bar with seek
/// - Playback speed adjustment (1x, 1.25x, 1.5x, 2x)
/// - Chapter selection (if available)
/// - Current position / total duration display
///
/// This widget is self-contained and manages its own AudioPlayer instance.
class AudioPlayerWidget extends StatefulWidget {
  final AudioResource audioResource;
  final VoidCallback? onOpenInBrowser;

  const AudioPlayerWidget({
    super.key,
    required this.audioResource,
    this.onOpenInBrowser,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late AudioPlayer _player;
  bool _isInitialized = false;
  String? _errorMessage;
  int _currentChapterIndex = 0;
  double _playbackSpeed = 1.0;

  static const List<double> _speedOptions = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      final url = _getInitialUrl();
      if (url == null || url.isEmpty) {
        // No direct streaming URL - this is expected for some sources
        setState(() {
          _errorMessage =
              'browser_only'; // Special marker for browser-only audio
        });
        return;
      }

      await _player.setUrl(url);
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('[AudioPlayerWidget] Init error: $e');
      setState(() {
        _errorMessage = 'Failed to load audio';
      });
    }
  }

  String? _getInitialUrl() {
    debugPrint('[AudioPlayerWidget] _getInitialUrl()');
    debugPrint('  streamUrl: ${widget.audioResource.streamUrl}');
    debugPrint('  chapters: ${widget.audioResource.chapters?.length ?? 0}');

    // Priority: direct stream URL > first chapter URL
    if (widget.audioResource.streamUrl != null &&
        widget.audioResource.streamUrl!.isNotEmpty &&
        widget.audioResource.streamUrl!.endsWith('.mp3')) {
      debugPrint('  -> Using streamUrl');
      return widget.audioResource.streamUrl;
    }

    final chapters = widget.audioResource.chapters;
    if (chapters != null && chapters.isNotEmpty) {
      final firstChapter = chapters.first;
      debugPrint('  firstChapter.url: ${firstChapter.url}');
      if (firstChapter.url.isNotEmpty) {
        debugPrint('  -> Using first chapter URL');
        return firstChapter.url;
      }
    }

    // Fallback: check if streamUrl is actually streamable
    if (widget.audioResource.streamUrl != null &&
        widget.audioResource.streamUrl!.isNotEmpty) {
      final url = widget.audioResource.streamUrl!;

      // Archive.org /details/ pages are not directly streamable
      if (url.contains('archive.org/details/')) {
        debugPrint('  -> Archive.org page URL (not streamable, use browser)');
        return null;
      }

      // Only use if it looks like a media file
      if (url.endsWith('.mp3') ||
          url.endsWith('.m4a') ||
          url.endsWith('.ogg')) {
        debugPrint('  -> Using streamUrl as fallback');
        return url;
      }

      debugPrint('  -> URL does not appear to be streamable: $url');
      return null;
    }

    debugPrint('  -> No URL found!');
    return null;
  }

  Future<void> _playChapter(int index) async {
    final chapters = widget.audioResource.chapters;
    if (chapters == null || index >= chapters.length) return;

    final chapter = chapters[index];
    if (chapter.url.isEmpty) return;

    try {
      await _player.stop();
      await _player.setUrl(chapter.url);
      await _player.play();
      setState(() {
        _currentChapterIndex = index;
      });
    } catch (e) {
      debugPrint('[AudioPlayerWidget] Error playing chapter: $e');
    }
  }

  Future<void> _setSpeed(double speed) async {
    await _player.setSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_errorMessage != null) {
      return _buildErrorState(context, colorScheme);
    }

    if (!_isInitialized) {
      return _buildLoadingState(context, colorScheme);
    }

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with source info
          _buildHeader(context, colorScheme),

          // Progress bar
          _buildProgressBar(context, colorScheme),

          // Controls
          _buildControls(context, colorScheme),

          // Chapter selector (if multiple chapters)
          if (widget.audioResource.chapters != null &&
              widget.audioResource.chapters!.length > 1)
            _buildChapterSelector(context, colorScheme),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
      child: Row(
        children: [
          Icon(Icons.headphones, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Audiobook',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                Text(
                  widget.audioResource.source.displayName,
                  style: TextStyle(
                    fontSize: 10,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Speed selector
          _buildSpeedButton(colorScheme),
          // Open in browser
          if (widget.onOpenInBrowser != null)
            IconButton(
              icon: Icon(
                Icons.open_in_new,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              onPressed: widget.onOpenInBrowser,
              tooltip: TranslationService.translate(context, 'open_in_browser'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeedButton(ColorScheme colorScheme) {
    return PopupMenuButton<double>(
      initialValue: _playbackSpeed,
      onSelected: _setSpeed,
      tooltip: TranslationService.translate(context, 'playback_speed'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${_playbackSpeed}x',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      itemBuilder: (context) => _speedOptions
          .map((speed) => PopupMenuItem(value: speed, child: Text('${speed}x')))
          .toList(),
    );
  }

  Widget _buildProgressBar(BuildContext context, ColorScheme colorScheme) {
    return StreamBuilder<Duration>(
      stream: _player.positionStream,
      builder: (context, positionSnapshot) {
        return StreamBuilder<Duration?>(
          stream: _player.durationStream,
          builder: (context, durationSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final duration = durationSnapshot.data ?? Duration.zero;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                      overlayShape: const RoundSliderOverlayShape(
                        overlayRadius: 12,
                      ),
                      activeTrackColor: colorScheme.primary,
                      inactiveTrackColor: colorScheme.surfaceContainerHighest,
                      thumbColor: colorScheme.primary,
                    ),
                    child: Slider(
                      value: duration.inMilliseconds > 0
                          ? position.inMilliseconds
                                .clamp(0, duration.inMilliseconds)
                                .toDouble()
                          : 0,
                      max: duration.inMilliseconds > 0
                          ? duration.inMilliseconds.toDouble()
                          : 1,
                      onChanged: (value) {
                        _player.seek(Duration(milliseconds: value.toInt()));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(position),
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          _formatDuration(duration),
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
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

  Widget _buildControls(BuildContext context, ColorScheme colorScheme) {
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final playing = playerState?.playing ?? false;
        final processingState = playerState?.processingState;

        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Rewind 10s
              IconButton(
                icon: const Icon(Icons.replay_10),
                tooltip: TranslationService.translate(context, 'tooltip_rewind_10s'),
                onPressed: () {
                  final newPos = _player.position - const Duration(seconds: 10);
                  _player.seek(newPos < Duration.zero ? Duration.zero : newPos);
                },
                color: colorScheme.onSurface,
                iconSize: 28,
              ),

              const SizedBox(width: 8),

              // Play/Pause
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    processingState == ProcessingState.loading ||
                            processingState == ProcessingState.buffering
                        ? Icons.hourglass_top
                        : playing
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  onPressed: () {
                    if (playing) {
                      _player.pause();
                    } else {
                      _player.play();
                    }
                  },
                  color: colorScheme.onPrimary,
                  iconSize: 32,
                ),
              ),

              const SizedBox(width: 8),

              // Forward 30s
              IconButton(
                icon: const Icon(Icons.forward_30),
                tooltip: TranslationService.translate(context, 'tooltip_forward_30s'),
                onPressed: () {
                  final duration = _player.duration ?? Duration.zero;
                  final newPos = _player.position + const Duration(seconds: 30);
                  _player.seek(newPos > duration ? duration : newPos);
                },
                color: colorScheme.onSurface,
                iconSize: 28,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChapterSelector(BuildContext context, ColorScheme colorScheme) {
    final chapters = widget.audioResource.chapters!;
    final currentChapter = chapters[_currentChapterIndex];

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
        ),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(
          Icons.list,
          size: 18,
          color: colorScheme.onSurfaceVariant,
        ),
        title: Text(
          currentChapter.title,
          style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Chapter ${_currentChapterIndex + 1} of ${chapters.length}',
          style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
        ),
        trailing: Icon(Icons.expand_more, color: colorScheme.onSurfaceVariant),
        onTap: () => _showChapterPicker(context, chapters, colorScheme),
      ),
    );
  }

  void _showChapterPicker(
    BuildContext context,
    List<AudioChapter> chapters,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Chapters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    final chapter = chapters[index];
                    final isSelected = index == _currentChapterIndex;

                    return ListTile(
                      selected: isSelected,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: isSelected
                            ? colorScheme.primary
                            : colorScheme.surfaceContainerHighest,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      title: Text(
                        chapter.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: chapter.formattedDuration != '--:--'
                          ? Text(
                              chapter.formattedDuration,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        _playChapter(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLoadingState(BuildContext context, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading audiobook...',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ColorScheme colorScheme) {
    // Special case: audio exists but not streamable directly
    if (_errorMessage == 'browser_only') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.headphones, color: colorScheme.primary, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Livre audio disponible',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Écouter sur ${widget.audioResource.source.displayName}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onOpenInBrowser != null)
              FilledButton.icon(
                onPressed: widget.onOpenInBrowser,
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Écouter'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Regular error state
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage ?? 'Failed to load audiobook',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (widget.onOpenInBrowser != null)
            TextButton(
              onPressed: widget.onOpenInBrowser,
              child: const Text('Open in Browser'),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
