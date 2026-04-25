// Renders the country + (optional) city label for a public-directory
// profile (ADR-035 Phase 1). City resolution is asynchronous because
// the publisher's country file may not be cached locally yet — the
// widget kicks off a lazy download via [CityRepository] and falls back
// to country-only text while it's pending.
//
// Lives in widgets/ rather than inside each screen so the three call
// sites (network list, peer book list header, library catalog header)
// share one source of truth for both the label format and the lazy-
// load behavior. Per AGENTS.md DRY rule: business logic centralized.

import 'package:flutter/material.dart';

import '../services/city_repository.dart';

class HubLocationLabel extends StatefulWidget {
  const HubLocationLabel({
    super.key,
    required this.country,
    required this.cityId,
    this.style,
  });

  /// ISO 3166-1 alpha-2 country code from the hub profile, may be null
  /// or empty for libraries that did not opt in to share country.
  final String? country;

  /// GeoNames id from the hub profile, may be null for libraries that
  /// share country only.
  final int? cityId;

  /// Optional override; defaults to the ambient `bodySmall` style so the
  /// label inherits the parent text scale and color.
  final TextStyle? style;

  @override
  State<HubLocationLabel> createState() => _HubLocationLabelState();
}

class _HubLocationLabelState extends State<HubLocationLabel> {
  Future<CityRecord?>? _lookup;

  @override
  void initState() {
    super.initState();
    _maybeStartLookup();
  }

  @override
  void didUpdateWidget(covariant HubLocationLabel old) {
    super.didUpdateWidget(old);
    if (old.country != widget.country || old.cityId != widget.cityId) {
      _maybeStartLookup();
    }
  }

  void _maybeStartLookup() {
    final id = widget.cityId;
    final cc = widget.country;
    if (id == null || cc == null || cc.isEmpty) {
      _lookup = null;
      return;
    }
    _lookup = CityRepository.shared().lookupById(id, country: cc);
  }

  @override
  Widget build(BuildContext context) {
    final cc = widget.country;
    final fallbackStyle = widget.style ?? Theme.of(context).textTheme.bodySmall;
    if (cc == null || cc.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_lookup == null) {
      return Text(cc, style: fallbackStyle);
    }

    return FutureBuilder<CityRecord?>(
      future: _lookup,
      builder: (context, snapshot) {
        // While loading or on miss, show the country alone — the screen
        // never has to deal with a flicker from an empty placeholder.
        final city = snapshot.data?.name;
        final label = city == null ? cc : '$cc · $city';
        return Text(label, style: fallbackStyle);
      },
    );
  }
}
