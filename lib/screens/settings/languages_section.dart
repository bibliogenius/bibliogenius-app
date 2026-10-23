import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:country_picker/country_picker.dart';

import '../../services/city_repository.dart';
import '../../services/translation_service.dart';
import '../../widgets/city_picker_sheet.dart';
import '../../providers/theme_provider.dart';
import '../../providers/hub_directory_provider.dart';
import '../../utils/language_constants.dart';
import 'settings_scope.dart';

const Map<String, String> _availableLanguages = kLanguageNativeNames;

/// Languages accordion
class LanguagesSettingsSection extends StatelessWidget {
  const LanguagesSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, [
      'languages_section',
      'languages_reading',
      'languages_ui',
      'settings_country',
    ])) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('languages_${settingsIsSearching(context)}'),
        initiallyExpanded: settingsIsSearching(context),
        leading: const Icon(Icons.translate),
        title: Semantics(
          header: true,
          child: Text(
            TranslationService.translate(context, 'languages_section'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildLanguageSection(context, themeProvider),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    // Normalize locale tag to match dropdown items (e.g. fr-FR -> fr)
    final rawLocale = themeProvider.localeTag;
    final currentLocale = ThemeProvider.supportedUILanguages.contains(rawLocale)
        ? rawLocale
        : ThemeProvider.supportedUILanguages.contains(
            rawLocale.split('-').first,
          )
        ? rawLocale.split('-').first
        : 'en';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reading languages (extracted so the springboard "Add a reading
        // language" sheet can show the same chips).
        const ReadingLanguagesField(),

        const SizedBox(height: 24),

        // UI language dropdown
        Text(
          TranslationService.translate(context, 'languages_ui') ??
              'Interface language',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          TranslationService.translate(context, 'languages_ui_desc') ??
              'The app will be displayed in this language',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: DropdownButton<String>(
            value: currentLocale,
            isExpanded: true,
            underline: const SizedBox(),
            items: ThemeProvider.supportedUILanguages
                .map(
                  (code) => DropdownMenuItem<String>(
                    value: code,
                    child: Text(_availableLanguages[code] ?? code),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                themeProvider.setLocale(parseLocaleTag(value));
              }
            },
          ),
        ),

        const SizedBox(height: 24),

        // Country
        Text(
          TranslationService.translate(context, 'settings_country') ??
              'Country',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const CountryPickerField(),

        const SizedBox(height: 24),

        // City sharing (ADR-035 §3): opt-in toggle + city picker, both live
        // here so the location preferences cluster in one place.
        const CitySettings(),
      ],
    );
  }
}

/// Reading languages: subtitle + selectable chips.
/// Reading-language subtitle + selectable chips. Self-contained (wraps its
/// own [Consumer]) so it renders in the Languages accordion and in the
/// springboard "Add a reading language" bottom sheet.
class ReadingLanguagesField extends StatelessWidget {
  const ReadingLanguagesField({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        final userLangs = themeProvider.userLanguages;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              TranslationService.translate(context, 'languages_reading') ??
                  'My reading languages',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              TranslationService.translate(context, 'languages_reading_desc') ??
                  'Select the languages you read in',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _availableLanguages.entries.map((entry) {
                final code = entry.key;
                final name = entry.value;
                final isSelected = userLangs.contains(code);
                return FilterChip(
                  label: Text(name),
                  selected: isSelected,
                  onSelected: (selected) {
                    final newLangs = List<String>.from(userLangs);
                    if (selected) {
                      newLangs.add(code);
                    } else {
                      if (newLangs.length <= 1) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              TranslationService.translate(
                                    context,
                                    'languages_min_one',
                                  ) ??
                                  'At least one language required',
                            ),
                          ),
                        );
                        return;
                      }
                      newLangs.remove(code);
                    }
                    themeProvider.setUserLanguages(newLangs);
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}

class CountryPickerField extends StatelessWidget {
  const CountryPickerField({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final countryCode = themeProvider.country;
    Country? current;
    try {
      current = CountryParser.parseCountryCode(countryCode);
    } catch (_) {
      // Unknown code, will show just the code
    }

    final primary = Theme.of(context).colorScheme.primary;

    return Semantics(
      // Says what the field picks, and still names it before a country is
      // chosen, when the row shows nothing.
      button: true,
      label: TranslationService.translate(context, 'country_label'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            showCountryPicker(
              context: context,
              showPhoneCode: false,
              favorite: ['FR', 'BE', 'CH', 'CA'],
              countryListTheme: CountryListThemeData(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                inputDecoration: InputDecoration(
                  hintText:
                      TranslationService.translate(context, 'search') ??
                      'Search',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              onSelect: (Country selected) async {
                await themeProvider.setCountry(selected.countryCode);
                if (!context.mounted) return;
                final hub = context.read<HubDirectoryProvider>();
                // A city belongs to a country. Keeping one from the previous
                // country leaves the picker showing "unknown city" (it resolves
                // selections from the current country file) and, when shared,
                // publishes a country+city pair no directory filter can match.
                await hub.dropCityForCountryChange(selected.countryCode);
                try {
                  await hub.syncLocationCountry(selected.countryCode);
                } catch (e) {
                  debugPrint('Hub locationCountry update failed: $e');
                }
              },
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                // A screen reader names the flag ("flag: France") right before
                // the country name: the name alone is enough.
                ExcludeSemantics(
                  child: Text(
                    current?.flagEmoji ?? '',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    current?.name ?? countryCode,
                    style: TextStyle(
                      color: primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CitySettings extends StatefulWidget {
  const CitySettings({super.key});

  @override
  State<CitySettings> createState() => _CitySettingsState();
}

class _CitySettingsState extends State<CitySettings> {
  /// City block (ADR-035 §3, amended). Two stacked concerns, deliberately in
  /// this order:
  ///
  ///  1. The city itself, a purely local preference. Available to everyone
  ///     who has set a country, whether or not they are listed in the public
  ///     directory. Filling it in writes to the device and nothing else.
  ///  2. "Partager ma ville", the opt-in that publishes it. Still gated on
  ///     the library being listed, since there is no public profile to attach
  ///     a city to otherwise.
  ///
  /// Putting the picker behind the toggle (the pre-amendment layout) made the
  /// city look like a directory feature, and a solo offline user could not
  /// record where they live without opting into publication.
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Consumer<HubDirectoryProvider>(
      builder: (context, hub, _) {
        final cs = Theme.of(context).colorScheme;
        final hasCountry = themeProvider.country.isNotEmpty;
        // Sharing needs a public profile to attach the city to, and a city to
        // put on it. Each missing precondition gets its own explanation.
        final canShareCity = hub.isListed && hub.localCityId != null;
        final String shareSubtitle;
        if (!hub.isListed) {
          shareSubtitle = TranslationService.translate(
            context,
            'settings_share_city_requires_directory',
          );
        } else if (hub.localCityId == null) {
          shareSubtitle = TranslationService.translate(
            context,
            'settings_share_city_requires_city',
          );
        } else {
          shareSubtitle = TranslationService.translate(
            context,
            'settings_share_city_desc',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                TranslationService.translate(context, 'settings_city_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              TranslationService.translate(
                context,
                hasCountry
                    ? 'settings_city_local_desc'
                    : 'settings_city_requires_country',
              ),
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (hasCountry) ...[
              const SizedBox(height: 8),
              _buildCityPicker(context, themeProvider, hub),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                TranslationService.translate(context, 'settings_share_city'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                shareSubtitle,
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              value: hub.isShareCityEnabled && canShareCity,
              activeColor: cs.primary,
              onChanged: canShareCity
                  ? (value) async {
                      await hub.setShareCity(value);
                      // Mirror the decision to the hub, in both directions.
                      // Opting out clears the published copy but deliberately
                      // keeps the local pick: the user withdrew a disclosure,
                      // they did not forget where they live.
                      try {
                        await hub.syncLocationCityId(
                          value ? hub.localCityId : null,
                          country: value ? hub.localCityCountry : null,
                        );
                      } catch (e) {
                        debugPrint('Hub locationCityId update failed: $e');
                      }
                    }
                  : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCityPicker(
    BuildContext context,
    ThemeProvider themeProvider,
    HubDirectoryProvider hub,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    final country = themeProvider.country;
    final pickedId = hub.localCityId;

    // The clear action is a SIBLING of the picker, never a child of it: an
    // actionable widget nested inside a Semantics(button: true) node gives
    // screen readers two overlapping targets in what is declared as one
    // button, and makes hit-testing between the IconButton and the enclosing
    // InkWell ambiguous (RGAA A1).
    return Row(
      children: [
        Expanded(child: _cityPickerField(context, country, hub, primary)),
        if (pickedId != null)
          IconButton(
            icon: const Icon(Icons.clear),
            color: primary,
            tooltip: TranslationService.translate(
              context,
              'settings_city_clear',
            ),
            onPressed: () => hub.clearCity(),
          ),
      ],
    );
  }

  /// The tappable field itself: current selection plus the affordance to open
  /// the picker sheet. Split out of [_buildCityPicker] so the clear action can
  /// sit next to it rather than inside its semantics node.
  Widget _cityPickerField(
    BuildContext context,
    String country,
    HubDirectoryProvider hub,
    Color primary,
  ) {
    final pickedId = hub.localCityId;
    return Material(
      color: Colors.transparent,
      // Semantics(button: true, label: ...) makes the picker discoverable
      // to screen readers; the inner Text still carries the current
      // selection so the announcement reads e.g. "Open city picker, Paris,
      // button" (ADR-035, RGAA A1).
      child: Semantics(
        button: true,
        label:
            TranslationService.translate(
              context,
              'settings_open_city_picker_a11y',
            ) ??
            'Open city picker',
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openCityPicker(context, country, hub),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.location_city_outlined, color: primary),
                const SizedBox(width: 12),
                Expanded(
                  child: pickedId == null
                      ? Text(
                          TranslationService.translate(
                                context,
                                'settings_city_pick',
                              ) ??
                              'Pick a city',
                          style: TextStyle(
                            color: primary,
                            fontWeight: FontWeight.w600,
                          ),
                        )
                      : FutureBuilder<CityRecord?>(
                          future: CityRepository.shared().lookupById(
                            pickedId,
                            country: country,
                          ),
                          builder: (context, snapshot) {
                            final label =
                                snapshot.data?.name ??
                                (TranslationService.translate(
                                      context,
                                      'settings_city_unknown',
                                    ) ??
                                    'Unknown city');
                            final subtitle = snapshot.data?.subtitle;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (subtitle != null)
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: primary.withValues(alpha: 0.75),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
                Icon(Icons.arrow_drop_down, color: primary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCityPicker(
    BuildContext context,
    String country,
    HubDirectoryProvider hub,
  ) async {
    final picked = await showModalBottomSheet<CityRecord>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) => CityPickerSheet(country: country),
    );
    if (picked == null) return;
    // Local first, always: recording where you live is not a publication.
    await hub.setLocalCityId(picked.id, country: picked.country);
    if (!hub.isShareCityEnabled) return;
    // The picked CityRecord knows its country - thread it through so the hub
    // upsert always carries the (city, country) pair. Without this, the city
    // was pushed alone and the hub-stored country could stay NULL, silently
    // excluding this profile from the country+city directory filter
    // (asymmetry observed iPhone-vs-Mac).
    try {
      await hub.syncLocationCityId(picked.id, country: picked.country);
    } catch (e) {
      debugPrint('Hub locationCityId update failed: $e');
    }
  }
}
