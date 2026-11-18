import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../services/web_cover_service.dart';
import '../utils/isbn_validator.dart';
import 'cached_book_cover.dart';

/// Asks for the address of a book's page on a publisher's site (or of the
/// cover image itself), fetches the cover into a temp file and shows it for
/// the user to keep, refuse, or replace by the page's next image. Resolves to
/// the kept cover, still under its temp name, or null; a refused or abandoned
/// preview is deleted. [isbn], when the book has one, ranks the images named
/// after it first.
///
/// When [book] has an ISBN whose publisher's site the engine's table knows,
/// a button offers to look for the cover there: the search sends the
/// publisher the book looked up, so the tap is the consent. The setting
/// ([PublisherCoverSearch]) can start it as the dialog opens instead, for a
/// book without a cover only, or remove the button. The address field stays
/// usable meanwhile, and is the way on when the search finds nothing.
///
/// [currentCoverUrl] is the book's cover, if it has one: the preview shows it
/// beside the new one, to replace or keep.
Future<WebCoverPick?> showWebCoverDialog(
  BuildContext context, {
  String? isbn,
  PublisherBook? book,
  String? currentCoverUrl,
  WebCoverService? service,
}) {
  final settings = context.read<ThemeProvider>();
  final mode = settings.publisherCoverSearch;
  return showDialog<WebCoverPick>(
    context: context,
    builder: (_) => WebCoverDialog(
      isbn: isbn,
      book: book,
      currentCoverUrl: currentCoverUrl,
      service: service ?? WebCoverService(),
      searchMode: mode,
      offerAutomatic:
          mode == PublisherCoverSearch.onDemand &&
          !settings.publisherCoverAutoOffered,
      onSearchModeChosen: settings.setPublisherCoverSearch,
    ),
  );
}

class WebCoverDialog extends StatefulWidget {
  final String? isbn;
  final PublisherBook? book;
  final String? currentCoverUrl;
  final WebCoverService service;
  final PublisherCoverSearch searchMode;

  /// Whether a cover found on the publisher's site comes with the offer to
  /// search automatically from then on ([onSearchModeChosen] hears the
  /// answer).
  final bool offerAutomatic;
  final ValueChanged<PublisherCoverSearch>? onSearchModeChosen;

  const WebCoverDialog({
    super.key,
    this.isbn,
    this.book,
    this.currentCoverUrl,
    required this.service,
    this.searchMode = PublisherCoverSearch.onDemand,
    this.offerAutomatic = false,
    this.onSearchModeChosen,
  });

  @override
  State<WebCoverDialog> createState() => _WebCoverDialogState();
}

class _WebCoverDialogState extends State<WebCoverDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _errorKey;

  /// The covers shown so far, in order, and which one is on screen. Kept so
  /// "previous image" is instant; nothing outside this dialog knows about
  /// them until the user keeps one.
  List<WebCoverPick> _shown = [];
  int _position = 0;
  bool _kept = false;

  WebCoverPick? get _preview => _shown.isEmpty ? null : _shown[_position];

  /// The page's usable images, best first, and the next one to fetch.
  List<String> _candidates = const [];
  int _nextToTry = 0;

  /// Set once stepping ran out of images that could be shown.
  bool _noMoreImages = false;

  /// The publisher's site the button names, once the engine's table has
  /// told it; null while unknown, or when there is none.
  String? _site;

  /// The search on the publisher's site, started by its button (or as the
  /// dialog opens, when the setting says so).
  bool _searchingPublisher = false;

  /// Completed when the running search's result is no longer wanted (an
  /// address won, the dialog closed): its next images are not tried then.
  Completer<void>? _searchDropped;

  /// Completed as the dialog closes: stops stepping to a next image.
  final _closed = Completer<void>();

  /// Set once the offer of the automatic search has been answered.
  bool _offerAnswered = false;

  /// Why that search found nothing, as an i18n key.
  String? _publisherErrorKey;

  /// What the search is doing, and the seconds left of a wait the site asks
  /// for, counted down here between two steps.
  PublisherLookupStep? _step;
  int _waitLeft = 0;
  Timer? _countdown;

  /// The steps the dialog knows how to say; another is shown as nothing.
  static const _sayableSteps = {
    'rules',
    'product_page',
    'search',
    'search_result',
    'site_map',
    'waiting',
    'queued',
    'cover',
  };

  /// The publisher's site the images on screen come from; null for images
  /// from an address the user gave.
  String? _foundOnSite;

  /// A cover the search found while the user was typing an address: set
  /// aside rather than shown over their typing, until they ask to see it.
  WebCoverPick? _setAside;

  /// The book's ISBN, for ranking a page's images: the book's own, unless the
  /// caller gave one.
  String? get _isbn => widget.isbn ?? widget.book?.isbn;

  /// Whether the dialog may look on the publisher's site: the setting
  /// allows it, and the ISBN is valid, not one still being typed in the add
  /// form.
  bool get _mayAskPublisher =>
      widget.searchMode != PublisherCoverSearch.never &&
      IsbnValidator.isValid(widget.book?.isbn);

  bool get _hasCurrentCover => widget.currentCoverUrl?.isNotEmpty ?? false;

  /// Whether the search starts as the dialog opens: by the setting, and
  /// never for a book that already has a cover.
  bool get _searchesOnOpening =>
      _mayAskPublisher &&
      widget.searchMode == PublisherCoverSearch.automatic &&
      !_hasCurrentCover;

  @override
  void initState() {
    super.initState();
    if (_mayAskPublisher) _nameSite(widget.book!);
  }

  /// Asks the engine's table which site the search would look on, for the
  /// button to name it (no request is sent), then starts the search if the
  /// setting says so and the user has not begun with an address.
  Future<void> _nameSite(PublisherBook book) async {
    final site = await widget.service.publisherSite(book);
    if (!mounted || site == null) return;
    setState(() => _site = site);
    final userBusy =
        _loading || _shown.isNotEmpty || _controller.text.trim().isNotEmpty;
    if (_searchesOnOpening && !userBusy) _startPublisherSearch();
  }

  void _startPublisherSearch() {
    final book = widget.book;
    if (book == null || _site == null || _searchingPublisher) return;
    final dropped = Completer<void>();
    setState(() {
      _searchingPublisher = true;
      _publisherErrorKey = null;
      _searchDropped = dropped;
    });
    _searchPublisherSite(book, dropped);
  }

  /// The running search's result is no longer wanted: it stops at its next
  /// step, and its steps are no longer shown. Call inside setState.
  void _dropPublisherSearch() {
    widget.service.stopHearingSteps(_onSearchStep);
    final dropped = _searchDropped;
    if (dropped != null && !dropped.isCompleted) dropped.complete();
    _countdown?.cancel();
    _searchingPublisher = false;
    _step = null;
  }

  /// Shows the cover the publisher's site gives, unless the user has moved
  /// on meanwhile (an address fetched, the dialog left): it is deleted then.
  Future<void> _searchPublisherSite(
    PublisherBook book,
    Completer<void> dropped,
  ) async {
    String? errorKey;
    WebCoverPick? pick;
    try {
      pick = await widget.service.findOnPublisherSiteAndSave(
        book,
        onStep: _onSearchStep,
        abandoned: dropped.future,
      );
    } on PublisherCoverException catch (e) {
      errorKey = e.translationKey;
    } catch (e) {
      // The service maps every failure; this only keeps the dialog usable
      // should something slip through.
      debugPrint('[WEB-COVER] unexpected publisher search failure: $e');
      errorKey = PublisherCoverException('network').translationKey;
    }
    // Dropped (an address won, the dialog left), or the user has a cover
    // from an address on screen: too late.
    if (!mounted || dropped.isCompleted || _shown.isNotEmpty) {
      if (pick != null) widget.service.discard(pick);
      if (mounted && !dropped.isCompleted) {
        _countdown?.cancel();
        setState(() => _searchingPublisher = false);
      }
      return;
    }
    _countdown?.cancel();
    // The user is typing or fetching an address: not over their typing.
    final busy = _loading || _controller.text.trim().isNotEmpty;
    setState(() {
      _searchingPublisher = false;
      _publisherErrorKey = errorKey;
      if (pick == null) return;
      if (busy) {
        _setAside = pick;
      } else {
        _showFirst(pick);
      }
    });
    if (pick != null && !busy) {
      _announcePreview();
    } else if (errorKey != null && !busy) {
      _focus.requestFocus();
    }
  }

  void _showSetAside() {
    final pick = _setAside;
    if (pick == null || _loading) return;
    setState(() {
      _setAside = null;
      _errorKey = null;
      _showFirst(pick);
    });
    _announcePreview();
  }

  bool get _hasPreviousImage => _position > 0;
  bool get _hasNextImage =>
      _position < _shown.length - 1 || _nextToTry < _candidates.length;

  /// A step of the search, shown while it runs only: a dropped search may
  /// still say one, which would land under a next image's progress bar.
  void _onSearchStep(PublisherLookupStep step) {
    if (_searchingPublisher) _onStep(step);
  }

  void _onStep(PublisherLookupStep step) {
    if (!mounted) return;
    _countdown?.cancel();
    final left = step.secondsLeft(DateTime.now());
    setState(() {
      _step = step;
      _waitLeft = left;
    });
    if (step.kind == 'waiting' && left > 1) {
      _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _waitLeft <= 1) {
          timer.cancel();
          return;
        }
        setState(() => _waitLeft--);
      });
    }
  }

  /// [step] in words; a wait with [seconds] left. Null for a step the dialog
  /// does not know.
  String? _sayStep(PublisherLookupStep step, int seconds) {
    if (!_sayableSteps.contains(step.kind)) return null;
    return TranslationService.translate(
      context,
      step.translationKey,
      params: {
        'site': step.site,
        'attempt': '${step.attempt}',
        'of': '${step.of}',
        'seconds': '$seconds',
      },
    );
  }

  @override
  void dispose() {
    _countdown?.cancel();
    widget.service.stopHearingSteps(_onSearchStep);
    final dropped = _searchDropped;
    if (dropped != null && !dropped.isCompleted) dropped.complete();
    _closed.complete();
    final setAside = _setAside;
    if (setAside != null) widget.service.discard(setAside);
    // However the dialog closes (cancel, barrier, back), the previews that
    // were not kept must not stay on disk.
    _discardShown(except: _kept ? _preview : null);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _discardShown({WebCoverPick? except}) {
    for (final pick in _shown) {
      if (!identical(pick, except)) widget.service.discard(pick);
    }
  }

  Future<void> _fetch() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    String? errorKey;
    WebCoverPick? pick;
    try {
      pick = await widget.service.fetchAndSave(url, isbn: _isbn);
    } on WebCoverException catch (e) {
      errorKey = e.translationKey;
    } catch (e) {
      // The service maps every failure; this only keeps the dialog usable
      // should something slip through.
      debugPrint('[WEB-COVER] unexpected failure: $e');
      errorKey = WebCoverException('network').translationKey;
    }
    if (!mounted) {
      if (pick != null) widget.service.discard(pick);
      return;
    }
    final setAside = pick == null ? null : _setAside;
    setState(() {
      _loading = false;
      _errorKey = errorKey;
      if (pick != null) {
        _showFirst(pick);
        // The address gave a cover: the search's outcome no longer applies,
        // nor does the search itself.
        _publisherErrorKey = null;
        _setAside = null;
        if (_searchingPublisher) _dropPublisherSearch();
      }
    });
    if (setAside != null) widget.service.discard(setAside);
    if (errorKey != null) {
      _focus.requestFocus();
    } else {
      _announcePreview();
    }
  }

  /// Puts [pick] on screen as the first of its page's images. Call inside
  /// setState.
  void _showFirst(WebCoverPick pick) {
    _shown = [pick];
    _position = 0;
    _candidates = pick.candidates;
    _nextToTry = _candidates.indexOf(pick.imageUrl) + 1;
    _noMoreImages = false;
    _foundOnSite = pick.site;
  }

  /// The preview replaces the address field: a screen reader would otherwise
  /// not say that the cover has arrived.
  void _announcePreview() {
    SemanticsService.sendAnnouncement(
      View.of(context),
      TranslationService.translate(context, 'web_cover_preview_label'),
      Directionality.of(context),
    );
  }

  void _previousImage() {
    if (_loading || !_hasPreviousImage) return;
    setState(() {
      _position--;
      _noMoreImages = false;
    });
  }

  /// Shows the next image: one already seen, or else the page's next image
  /// that can be fetched, skipping those that fail; says so when none is
  /// left. The dialog can be left meanwhile, which stops the search.
  Future<void> _nextImage() async {
    if (_loading || !_hasNextImage) return;
    if (_position < _shown.length - 1) {
      setState(() => _position++);
      return;
    }
    _countdown?.cancel();
    setState(() {
      _loading = true;
      _step = null;
    });
    WebCoverPick? next;
    var index = _nextToTry;
    for (; index < _candidates.length && mounted; index++) {
      try {
        next = await widget.service.fetchCandidateAndSave(
          _candidates[index],
          fromPublisherSite: _foundOnSite != null,
          // A publisher's image goes through the lookup's rules: its
          // pauses are said as the search's were.
          onStep: _onStep,
          abandoned: _closed.future,
        );
        break;
      } catch (e) {
        debugPrint('[WEB-COVER] candidate $index skipped: $e');
      }
    }
    if (!mounted) {
      if (next != null) widget.service.discard(next);
      return;
    }
    _countdown?.cancel();
    setState(() {
      _loading = false;
      _step = null;
      if (next != null) {
        _shown = [..._shown, next];
        _position = _shown.length - 1;
        _nextToTry = index + 1;
      } else {
        _nextToTry = _candidates.length;
        _noMoreImages = true;
      }
    });
  }

  void _tryAnother() {
    _discardShown();
    setState(() {
      _shown = [];
      _position = 0;
      _candidates = const [];
      _noMoreImages = false;
      _foundOnSite = null;
    });
    _focus.requestFocus();
  }

  void _keep() {
    _kept = true;
    Navigator.of(context).pop(_preview);
  }

  void _answerOffer(PublisherCoverSearch mode) {
    widget.onSearchModeChosen?.call(mode);
    setState(() => _offerAnswered = true);
  }

  bool get _offersAutomatic =>
      widget.offerAutomatic &&
      !_offerAnswered &&
      widget.onSearchModeChosen != null &&
      _foundOnSite != null;

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    final preview = _preview;
    // The dialog can be left at any time, a fetch included: a result landing
    // after that is deleted (see the !mounted branch of _fetch).
    return AlertDialog(
      scrollable: true,
      title: Semantics(header: true, child: Text(t('web_cover_dialog_title'))),
      content: preview == null
          ? _buildAddressForm(t)
          : _buildPreview(preview, t),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            t(
              preview != null && _hasCurrentCover
                  ? 'web_cover_keep_current'
                  : 'cancel',
            ),
          ),
        ),
        if (preview == null)
          FilledButton(
            onPressed: _loading ? null : _fetch,
            child: Text(t('web_cover_dialog_fetch')),
          )
        else ...[
          TextButton(
            onPressed: _loading ? null : _tryAnother,
            child: Text(t('web_cover_try_another')),
          ),
          if (_hasPreviousImage)
            TextButton(
              onPressed: _loading ? null : _previousImage,
              child: Text(t('web_cover_previous_image')),
            ),
          if (_hasNextImage)
            TextButton(
              onPressed: _loading ? null : _nextImage,
              child: Text(t('web_cover_next_image')),
            ),
          FilledButton(
            onPressed: _loading ? null : _keep,
            child: Text(
              t(_hasCurrentCover ? 'web_cover_replace' : 'web_cover_use'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAddressForm(String Function(String) t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searchingPublisher) ...[
          Semantics(
            liveRegion: true,
            label: t('publisher_cover_searching'),
            child: ExcludeSemantics(
              child: Text(t('publisher_cover_searching')),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            semanticsLabel: t('publisher_cover_searching'),
          ),
          ..._buildStep(),
          const SizedBox(height: 16),
        ] else if (_setAside != null) ...[
          // Appears while the user types: said to screen readers too.
          Semantics(
            liveRegion: true,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _loading ? null : _showSetAside,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  TranslationService.translate(
                    context,
                    'publisher_cover_show_found',
                    params: {'site': _setAside!.site ?? ''},
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else ...[
          if (_publisherErrorKey != null) ...[
            Semantics(liveRegion: true, child: Text(t(_publisherErrorKey!))),
            const SizedBox(height: 12),
          ],
          if (_site != null) ..._buildSearchButton(),
        ],
        Text(t('web_cover_dialog_help')),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          focusNode: _focus,
          // No keyboard over the search's button on a phone: the user may
          // only have to tap it, or wait for its result.
          autofocus: !_mayAskPublisher,
          // readOnly rather than disabled: a disabled field drops the focus,
          // and the user would have to tap it again after an error.
          readOnly: _loading,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: t('web_cover_dialog_field'),
            hintText: 'https://',
            errorText: _errorKey == null ? null : t(_errorKey!),
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _fetch(),
        ),
        if (_loading) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            label: t('web_cover_dialog_loading'),
            child: const LinearProgressIndicator(),
          ),
        ],
      ],
    );
  }

  /// The button that starts the search on the publisher's site, and what
  /// tapping it sends.
  List<Widget> _buildSearchButton() {
    return [
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: _loading ? null : _startPublisherSearch,
          icon: const Icon(Icons.travel_explore),
          label: Text(
            TranslationService.translate(
              context,
              'publisher_cover_search_on',
              params: {'site': _site!},
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        TranslationService.translate(context, 'publisher_cover_search_notice'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 16),
    ];
  }

  /// The search's current step under its progress bar. Screen readers hear
  /// each step once, as it starts, not every second of a countdown.
  List<Widget> _buildStep() {
    final step = _step;
    if (step == null) return const [];
    final shown = _sayStep(step, _waitLeft);
    if (shown == null) return const [];
    return [
      const SizedBox(height: 8),
      Semantics(
        liveRegion: true,
        label: _sayStep(step, step.seconds),
        child: ExcludeSemantics(
          child: Text(shown, style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    ];
  }

  Widget _buildPreview(WebCoverPick preview, String Function(String) t) {
    final current = widget.currentCoverUrl;
    final found = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(preview.path),
        key: ValueKey(preview.path),
        height: _hasCurrentCover ? 180 : 240,
        fit: BoxFit.contain,
        semanticLabel: t('web_cover_preview_label'),
        errorBuilder: (_, _, _) => SizedBox(
          width: _hasCurrentCover ? 120 : 160,
          height: _hasCurrentCover ? 180 : 240,
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (current != null && current.isNotEmpty)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _captioned(
                  t('web_cover_current'),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedBookCover(
                      imageUrl: current,
                      width: 120,
                      height: 180,
                      fit: BoxFit.contain,
                      semanticLabel: t('web_cover_current'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _captioned(t('web_cover_new'), found)),
            ],
          )
        else
          Center(child: found),
        if (_foundOnSite != null) ...[
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(
              context,
              'publisher_cover_found_on',
              params: {'site': _foundOnSite!},
            ),
            textAlign: TextAlign.center,
          ),
        ],
        if (_loading) ...[
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            label: t('web_cover_dialog_loading'),
            child: const LinearProgressIndicator(),
          ),
          ..._buildStep(),
        ],
        if (_noMoreImages) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Text(t('web_cover_no_more_images')),
          ),
        ],
        if (_offersAutomatic) ..._buildOffer(t),
      ],
    );
  }

  /// [image] with [caption] under it; the caption is said by the image's own
  /// label.
  Widget _captioned(String caption, Widget image) {
    return Column(
      children: [
        image,
        const SizedBox(height: 4),
        ExcludeSemantics(
          child: Text(
            caption,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  /// After a cover found on the publisher's site: whether to search there
  /// as the dialog opens from now on, for books without a cover.
  List<Widget> _buildOffer(String Function(String) t) {
    return [
      const SizedBox(height: 16),
      Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('publisher_cover_auto_offer')),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => _answerOffer(PublisherCoverSearch.onDemand),
                  child: Text(t('publisher_cover_auto_offer_no')),
                ),
                TextButton(
                  onPressed: () => _answerOffer(PublisherCoverSearch.automatic),
                  child: Text(t('publisher_cover_auto_offer_yes')),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}
