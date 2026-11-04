import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../services/recent_shelves_store.dart';
import '../services/shelf_rows.dart';
import '../services/translation_service.dart';
import '../utils/book_genres.dart';
import 'shelf_placement_tree.dart';
import 'shelf_thumbnail.dart';
import 'shelf_tree_rows.dart';

class HierarchicalTagSelector extends StatefulWidget {
  final List<String> selectedTags;
  final Function(List<String>) onTagsChanged;

  /// True when a [GenreChipsSelector] above already lights the book's
  /// genres: a genre is then not repeated as a chip here. It stays in the
  /// selection, and the picker shows it checked.
  final bool genresShownAbove;

  const HierarchicalTagSelector({
    super.key,
    required this.selectedTags,
    required this.onTagsChanged,
    this.genresShownAbove = false,
  });

  @override
  State<HierarchicalTagSelector> createState() =>
      _HierarchicalTagSelectorState();
}

class _HierarchicalTagSelectorState extends State<HierarchicalTagSelector> {
  late List<String> _currentSelection;

  /// Every shelf, to tell a recent name that still exists from one deleted
  /// since. Empty until the first load.
  List<Tag> _allTags = const [];
  List<String> _recentNames = const [];

  @override
  void initState() {
    super.initState();
    _currentSelection = List.from(widget.selectedTags);
    _loadShelves();
  }

  @override
  void didUpdateWidget(covariant HierarchicalTagSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedTags != oldWidget.selectedTags) {
      _currentSelection = List.from(widget.selectedTags);
    }
  }

  Future<void> _loadShelves() async {
    try {
      final tagRepo = Provider.of<TagRepository>(context, listen: false);
      final results = await Future.wait([
        tagRepo.getTags(),
        RecentShelvesStore.load(),
      ]);
      if (!mounted) return;
      setState(() {
        _allTags = results[0] as List<Tag>;
        _recentNames = results[1] as List<String>;
      });
    } catch (e) {
      // The row of recent shelves is a shortcut: without it the form still
      // works through the picker.
      debugPrint('HierarchicalTagSelector: could not load shelves: $e');
    }
  }

  /// Exact comparison: two shelves may differ by case or accents alone
  /// (see [_shelfNamed]).
  bool _isSelected(String name) =>
      _currentSelection.any((s) => s.trim() == name.trim());

  /// Recent shelves that still exist.
  List<Tag> get _recentShelves => [
    for (final name in _recentNames)
      if (_shelfNamed(_allTags, name) case final tag?) tag,
  ];

  void _removeTag(String tag) {
    setState(() {
      _currentSelection.remove(tag);
      widget.onTagsChanged(_currentSelection);
    });
  }

  void _addTag(Tag tag) {
    if (_isSelected(tag.name)) return;
    setState(() {
      _currentSelection = [..._currentSelection, tag.fullPath];
      widget.onTagsChanged(_currentSelection);
    });
  }

  Future<void> _showShelfPicker() async {
    final tagRepo = Provider.of<TagRepository>(context, listen: false);
    final tags = await tagRepo.getTags();
    if (!mounted) return;

    final selectedIds = tags
        .where((t) => _isSelected(t.fullPath))
        .map((t) => t.id)
        .toSet();

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _ShelfPickerSheet(
        allTags: tags,
        initialSelectedIds: selectedIds,
        recentNames: _recentNames,
      ),
    );

    if (!mounted) return;
    if (result != null) {
      setState(() {
        _currentSelection = result;
        widget.onTagsChanged(_currentSelection);
      });
    }
    // The picker may have created shelves.
    unawaited(_loadShelves());
  }

  /// Build a concise display label for a tag path.
  /// 1 level: "Fiction"
  /// 2 levels: "Fiction > Policier"
  /// 3+ levels: "... > Parent > Leaf"
  String _displayPath(String tagPath) {
    final parts = tagPath.split(' > ');
    if (parts.length <= 2) return parts.join(' › ');
    return '… › ${parts[parts.length - 2]} › ${parts.last}';
  }

  /// A genre lit by the chips above is not drawn a second time here.
  bool _shownAbove(String shelf) =>
      widget.genresShownAbove && selectedGenres([shelf]).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = _recentShelves.where((t) => !_isSelected(t.name)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.shelves,
                  size: 20,
                  color: theme.colorScheme.primary.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      TranslationService.translate(context, 'tags_label'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color.lerp(
                          theme.colorScheme.primary,
                          Colors.black,
                          0.25,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TranslationService.translate(context, 'tags_helper'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(
                          alpha: 0.85,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Selected Tags Chips + Add Button
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ..._currentSelection.where((s) => !_shownAbove(s)).map((tagPath) {
              final isNested = tagPath.contains(' > ');
              return Tooltip(
                message: tagPath,
                child: Chip(
                  avatar: Icon(
                    isNested
                        ? Icons.subdirectory_arrow_right_rounded
                        : Icons.bookmark_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(_displayPath(tagPath)),
                  onDeleted: () => _removeTag(tagPath),
                ),
              );
            }),

            // Add Button
            ActionChip(
              key: const Key('addShelfChip'),
              avatar: Icon(
                Icons.library_add_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              label: Text(TranslationService.translate(context, 'add_tag')),
              onPressed: _showShelfPicker,
            ),
          ],
        ),

        // Recent shelves: one tap files the book where the last ones went.
        if (recent.isNotEmpty) ...[
          ShelfSectionLabel(
            TranslationService.translate(context, 'recent_shelves'),
            padding: const EdgeInsets.only(top: 12, bottom: 6),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in recent)
                // The "+" says it visually; a screen reader hears the
                // action, not just the name.
                Semantics(
                  key: ValueKey('recentShelf:${tag.name}'),
                  button: true,
                  label: TranslationService.translate(
                    context,
                    'add_shelf_named',
                  ).replaceAll('{name}', tag.name),
                  onTap: () => _addTag(tag),
                  excludeSemantics: true,
                  child: ActionChip(
                    avatar: Icon(
                      Icons.add,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    label: Text(tag.name),
                    onPressed: () => _addTag(tag),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The shelf called exactly [name], if any.
///
/// `tags.name` is unique byte for byte, so "Etagere" and "Étagère" may both
/// exist. What is checked or saved compares names exactly; folding case and
/// accents ([shelfNameKey]) only serves to say a typed name is taken.
Tag? _shelfNamed(List<Tag> tags, String name) {
  final target = name.trim();
  for (final tag in tags) {
    if (tag.name.trim() == target) return tag;
  }
  return null;
}

/// The shelf a reader would take [name] for: same name once case and
/// accents are folded. Used only to offer no "Create" for a taken name.
Tag? _shelfTakenBy(List<Tag> tags, String name) {
  final key = shelfNameKey(name);
  for (final tag in tags) {
    if (shelfNameKey(tag.name) == key) return tag;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Bottom Sheet Picker
// ---------------------------------------------------------------------------

class _ShelfPickerSheet extends StatefulWidget {
  final List<Tag> allTags;
  final Set<String> initialSelectedIds;
  final List<String> recentNames;

  const _ShelfPickerSheet({
    required this.allTags,
    required this.initialSelectedIds,
    required this.recentNames,
  });

  @override
  State<_ShelfPickerSheet> createState() => _ShelfPickerSheetState();
}

class _ShelfPickerSheetState extends State<_ShelfPickerSheet> {
  late Set<String> _selectedIds;
  late List<Tag> _tags;
  String _searchQuery = '';
  bool _isCreating = false;

  /// Showing the placement tree for the name typed, instead of the picker.
  bool _placing = false;

  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
    _tags = List.from(widget.allTags);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _searchQuery = query.trim());
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _searchQuery = '';
  }

  void _toggleTag(Tag tag) {
    setState(() {
      if (_selectedIds.contains(tag.id)) {
        _selectedIds.remove(tag.id);
      } else {
        _selectedIds.add(tag.id);
      }
    });
  }

  /// The shelf the typed name would duplicate, case and accents ignored.
  Tag? _taken(String name) => _shelfTakenBy(_tags, name);

  /// Creates [name] under [parent] (null: first level) and checks it.
  Future<void> _create(String name, Tag? parent) async {
    if (name.isEmpty || _isCreating) return;
    setState(() => _isCreating = true);
    final repo = Provider.of<TagRepository>(context, listen: false);
    try {
      final parentRow = await shelfWithRow(repo, parent);
      final newTag = await repo.createTag(name, parentId: parentRow?.id);
      if (!mounted) return;
      setState(() {
        // A parent known only from subjects now has its row: list that row
        // in its place, and keep it chosen if it was.
        _tags = [
          for (final t in _tags) t.id == parent?.id ? parentRow! : t,
          newTag,
        ];
        if (parent != null && _selectedIds.remove(parent.id)) {
          _selectedIds.add(parentRow!.id);
        }
        _selectedIds.add(newTag.id);
        _placing = false;
        _clearSearch();
      });
    } catch (e) {
      debugPrint('Shelf picker: could not create a shelf: $e');
      // The name may have been taken meanwhile (another device, a sync):
      // pick that shelf rather than surface a constraint error.
      final fresh = await repo.getTags().catchError((_) => _tags);
      if (!mounted) return;
      final existing = _shelfTakenBy(fresh, name);
      setState(() {
        _tags = List.of(fresh);
        _placing = false;
        if (existing != null) {
          _selectedIds.add(existing.id);
          _clearSearch();
        }
      });
      if (existing == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'error_generic'),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  /// Enter in the field: create the name offered, or pick the shelf that
  /// already carries it.
  void _submit(String value) {
    // Settle the debounced query first: the name created is always
    // [_searchQuery], the one the create block shows.
    _debounce?.cancel();
    setState(() => _searchQuery = value.trim());
    if (_searchQuery.isEmpty) return;
    final taken = _taken(_searchQuery);
    if (taken != null) {
      if (!_selectedIds.contains(taken.id)) _toggleTag(taken);
      return;
    }
    _create(_searchQuery, null);
  }

  void _finish() {
    final selectedPaths = _tags
        .where((t) => _selectedIds.contains(t.id))
        .map((t) => t.fullPath)
        .toList();

    Navigator.pop(context, selectedPaths);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      key: const Key('shelfPickerSheet'),
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _buildDragHandle(Theme.of(context)),
            Expanded(
              child: _placing
                  ? _buildPlacement()
                  : _buildPicker(scrollController),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDragHandle(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildPlacement() {
    // The name the create block showed, not the field's latest keystroke.
    final name = _searchQuery;
    return ShelfPlacementTree(
      allTags: _tags,
      title: TranslationService.translate(
        context,
        'create_shelf_in_title',
      ).replaceAll('{name}', name),
      subtitle: TranslationService.translate(
        context,
        'create_shelf_in_subtitle',
      ),
      firstLevelLabel: TranslationService.translate(
        context,
        'create_shelf_first_level_instead',
      ),
      onBack: () => setState(() => _placing = false),
      onPlace: (parent) => _create(name, parent),
    );
  }

  Widget _buildPicker(ScrollController scrollController) {
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildHeader(theme),
        _buildSearchField(),
        Expanded(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            children: _searchQuery.isEmpty
                ? _buildBrowseContent(theme)
                : _buildSearchContent(theme),
          ),
        ),
        _buildBottomBar(theme, _selectedIds.length),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    TranslationService.translate(context, 'choose_shelves'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  TranslationService.translate(
                    context,
                    'choose_shelves_subtitle',
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: TranslationService.translate(context, 'close'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        onSubmitted: _submit,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          // A label, not a hint: a hint (or a label that never floats)
          // leaves the field nameless for a screen reader once text is in.
          labelText: TranslationService.translate(
            context,
            'search_or_create_shelf_hint',
          ),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: TranslationService.translate(context, 'clear'),
                  onPressed: () => setState(_clearSearch),
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  /// Empty field: the recent shelves, then the whole tree, unfolded.
  List<Widget> _buildBrowseContent(ThemeData theme) {
    if (_tags.isEmpty) return [_buildEmptyState(theme)];
    final recent = [
      for (final name in widget.recentNames)
        if (_shelfNamed(_tags, name) case final tag?) tag,
    ];
    return [
      if (recent.isNotEmpty) ...[
        ShelfSectionLabel(
          TranslationService.translate(context, 'recent_shelves'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in recent)
                FilterChip(
                  key: ValueKey('sheetRecentShelf:${tag.name}'),
                  label: Text(tag.name),
                  selected: _selectedIds.contains(tag.id),
                  onSelected: (_) => _toggleTag(tag),
                ),
            ],
          ),
        ),
      ],
      ShelfSectionLabel(TranslationService.translate(context, 'all_shelves')),
      for (final entry in flattenShelfTree(_tags))
        _buildRow(
          entry.tag,
          depth: entry.depth,
          subtitle: entry.depth > shelfTreeMaxIndentDepth
              ? shelfParentPath(context, entry.ancestors)
              : null,
        ),
    ];
  }

  /// Text typed: the taken name or the create block first, then the other
  /// shelves that match, each naming its parent instead of nesting.
  List<Widget> _buildSearchContent(ThemeData theme) {
    final query = shelfNameKey(_searchQuery);
    final taken = _taken(_searchQuery);
    final ancestors = {
      for (final e in flattenShelfTree(_tags)) e.tag.id: e.ancestors,
    };
    String? existsLine(Tag tag) {
      final path = ancestors[tag.id] ?? const <String>[];
      if (path.isEmpty) {
        return TranslationService.translate(context, 'shelf_already_exists');
      }
      return TranslationService.translate(
        context,
        'shelf_already_exists_in',
      ).replaceAll('{path}', path.join(' › '));
    }

    final matches =
        _tags
            .where((t) => t.id != taken?.id)
            .where((t) => shelfNameKey(t.name).contains(query))
            .toList()
          ..sort(compareShelves);

    return [
      const SizedBox(height: 4),
      if (taken == null)
        _buildCreateBlock(theme)
      else ...[
        _buildRow(taken, subtitle: existsLine(taken)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            TranslationService.translate(context, 'shelf_name_taken_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
      if (matches.isNotEmpty) ...[
        ShelfSectionLabel(
          TranslationService.translate(context, 'matching_shelves'),
        ),
        for (final tag in matches)
          _buildRow(
            tag,
            subtitle: shelfParentPath(context, ancestors[tag.id] ?? const []),
          ),
      ],
    ];
  }

  Widget _buildRow(Tag tag, {int depth = 0, String? subtitle}) {
    final checked = _selectedIds.contains(tag.id);
    return ShelfTreeRow(
      key: ValueKey('shelfRow:${tag.name}'),
      name: tag.name,
      depth: depth,
      subtitle: subtitle,
      checked: checked,
      trailing: ShelfCheckMarker(checked: checked),
      onTap: () => _toggleTag(tag),
      thumbnail: ShelfThumbnail(
        size: ShelfThumbnailSize.s,
        coverPaths: tag.coverPaths,
        hasBooks: Tag.getAggregatedCount(tag, _tags) > 0,
      ),
    );
  }

  /// "Create “Night”" at the first level, and the way to place it elsewhere.
  Widget _buildCreateBlock(ThemeData theme) {
    final scheme = theme.colorScheme;
    final name = _searchQuery;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Semantics(
              button: true,
              child: InkWell(
                onTap: _isCreating ? null : () => _create(name, null),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: scheme.primary,
                        child: _isCreating
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: scheme.onPrimary,
                                ),
                              )
                            : Icon(Icons.add, color: scheme.onPrimary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              TranslationService.translate(
                                context,
                                'create_shelf_named',
                              ).replaceAll('{name}', name),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            Text(
                              TranslationService.translate(
                                context,
                                'create_shelf_first_level_hint',
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: scheme.outlineVariant),
            Semantics(
              button: true,
              child: InkWell(
                onTap: _isCreating
                    ? null
                    : () => setState(() => _placing = true),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Icon(
                            Icons.create_new_folder_outlined,
                            color: scheme.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            TranslationService.translate(
                              context,
                              'create_shelf_inside',
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: scheme.onSecondaryContainer,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shelves,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            TranslationService.translate(context, 'no_shelves_yet'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, int selectedCount) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (selectedCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '$selectedCount ${TranslationService.translate(context, 'shelves_selected')}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const Spacer(),
            FilledButton.icon(
              onPressed: _finish,
              icon: const Icon(Icons.check, size: 18),
              label: Text(TranslationService.translate(context, 'done')),
            ),
          ],
        ),
      ),
    );
  }
}
