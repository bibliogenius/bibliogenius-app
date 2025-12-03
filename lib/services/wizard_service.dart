import 'package:flutter/material.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/translation_service.dart';

class WizardService {
  static const String _kHasSeenDashboardWizard = 'has_seen_dashboard_wizard_v1';

  static Future<bool> hasSeenDashboardWizard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenDashboardWizard) ?? false;
  }

  static Future<void> markDashboardWizardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenDashboardWizard, true);
  }

  static Future<void> resetWizard() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHasSeenDashboardWizard);
  }

  static void showDashboardWizard({
    required BuildContext context,
    required GlobalKey addKey,
    required GlobalKey searchKey,
    required GlobalKey statsKey,
    required GlobalKey menuKey,
    required Function() onFinish,
  }) {
    final theme = Theme.of(context);
    
    List<TargetFocus> targets = [
      TargetFocus(
        identify: "menu_key",
        keyTarget: menuKey,
        alignSkip: Alignment.bottomRight,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_menu_title'),
                TranslationService.translate(context, 'wizard_menu_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "add_key",
        keyTarget: addKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_add_title'),
                TranslationService.translate(context, 'wizard_add_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "search_key",
        keyTarget: searchKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_search_title'),
                TranslationService.translate(context, 'wizard_search_desc'),
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: theme.primaryColor,
      textSkip: TranslationService.translate(context, 'wizard_skip'),
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        markDashboardWizardSeen();
        onFinish();
      },
      onSkip: () {
        markDashboardWizardSeen();
        return true;
      },
    ).show(context: context);
  }

  static const String _kHasSeenBooksWizard = 'has_seen_books_wizard_v1';

  static Future<bool> hasSeenBooksWizard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenBooksWizard) ?? false;
  }

  static Future<void> markBooksWizardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenBooksWizard, true);
  }

  static void showBooksTutorial({
    required BuildContext context,
    required GlobalKey searchKey,
    required GlobalKey viewKey,
    required GlobalKey scanKey,
    required GlobalKey externalSearchKey,
    required GlobalKey addKey,
  }) {
    final theme = Theme.of(context);
    
    List<TargetFocus> targets = [
      TargetFocus(
        identify: "add_key",
        keyTarget: addKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_books_add_title'),
                TranslationService.translate(context, 'wizard_books_add_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "scan_key",
        keyTarget: scanKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_books_scan_title'),
                TranslationService.translate(context, 'wizard_books_scan_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "search_key",
        keyTarget: searchKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_books_search_title'),
                TranslationService.translate(context, 'wizard_books_search_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "external_search_key",
        keyTarget: externalSearchKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_books_external_title'),
                TranslationService.translate(context, 'wizard_books_external_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "view_key",
        keyTarget: viewKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_books_view_title'),
                TranslationService.translate(context, 'wizard_books_view_desc'),
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: theme.primaryColor,
      textSkip: TranslationService.translate(context, 'wizard_skip'),
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        markBooksWizardSeen();
      },
      onSkip: () {
        markBooksWizardSeen();
        return true;
      },
    ).show(context: context);
  }

  static const String _kHasSeenContactsWizard = 'has_seen_contacts_wizard_v1';

  static Future<bool> hasSeenContactsWizard() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kHasSeenContactsWizard) ?? false;
  }

  static Future<void> markContactsWizardSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHasSeenContactsWizard, true);
  }

  static void showContactsTutorial({
    required BuildContext context,
    required GlobalKey addKey,
    required GlobalKey filterKey,
  }) {
    final theme = Theme.of(context);
    
    List<TargetFocus> targets = [
      TargetFocus(
        identify: "add_key",
        keyTarget: addKey,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_contacts_add_title'),
                TranslationService.translate(context, 'wizard_contacts_add_desc'),
              );
            },
          ),
        ],
      ),
      TargetFocus(
        identify: "filter_key",
        keyTarget: filterKey,
        contents: [
          TargetContent(
            align: ContentAlign.bottom,
            builder: (context, controller) {
              return _buildWizardContent(
                context,
                TranslationService.translate(context, 'wizard_contacts_filter_title'),
                TranslationService.translate(context, 'wizard_contacts_filter_desc'),
              );
            },
          ),
        ],
      ),
    ];

    TutorialCoachMark(
      targets: targets,
      colorShadow: theme.primaryColor,
      textSkip: TranslationService.translate(context, 'wizard_skip'),
      paddingFocus: 10,
      opacityShadow: 0.8,
      onFinish: () {
        markContactsWizardSeen();
      },
      onSkip: () {
        markContactsWizardSeen();
        return true;
      },
    ).show(context: context);
  }

  static Widget _buildWizardContent(BuildContext context, String title, String desc) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: const TextStyle(color: Colors.black87),
          ),
        ],
      ),
    );
  }
}
