// Bottom-sheet typeahead city picker (ADR-035 Phase 1+2).
//
// Loads the country file via [CityRepository] (lazy download on first
// use), debounces user input, and pops the chosen [CityRecord] back to
// the caller. Used by both the settings "share my city" picker and the
// network screen filter picker - extracted into widgets/ so the two
// share the same UX, accessibility, and download lifecycle.

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/city_repository.dart';
import '../services/translation_service.dart';

class CityPickerSheet extends StatefulWidget {
  const CityPickerSheet({super.key, required this.country});

  final String country;

  @override
  State<CityPickerSheet> createState() => _CityPickerSheetState();
}

class _CityPickerSheetState extends State<CityPickerSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _repo = CityRepository.shared();

  Timer? _debounce;
  bool _loading = true;
  bool _available = false;
  List<CityRecord> _results = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
    _focusNode.requestFocus();
  }

  Future<void> _bootstrap() async {
    final ok = await _repo.ensureDownloaded(widget.country);
    if (!mounted) return;
    setState(() {
      _available = ok;
      _loading = false;
    });
    if (ok) await _runSearch('');
  }

  Future<void> _runSearch(String query) async {
    final results = await _repo.search(query, widget.country);
    if (!mounted) return;
    setState(() => _results = results);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // 150 ms is short enough to feel instant on the keystroke but stops
    // a long paste from triggering one search per intermediate state.
    _debounce = Timer(const Duration(milliseconds: 150), () {
      _runSearch(value);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final maxHeight = mediaQuery.size.height * 0.75;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText:
                      TranslationService.translate(context, 'search') ??
                      'Search',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_available) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          TranslationService.translate(context, 'settings_city_unavailable') ??
              'No city data is available for this country yet. Please try again later.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700]),
        ),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          TranslationService.translate(context, 'settings_city_no_match') ??
              'No matching city.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[700]),
        ),
      );
    }
    return ListView.builder(
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final r = _results[index];
        final subtitle = r.subtitle;
        return ListTile(
          title: Text(r.name),
          subtitle: subtitle != null ? Text(subtitle) : null,
          onTap: () => Navigator.of(context).pop(r),
        );
      },
    );
  }
}
