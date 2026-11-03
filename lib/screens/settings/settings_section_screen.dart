import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/hub_directory_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/api_service.dart';
import '../../services/translation_service.dart';
import '../../theme/app_design.dart';
import '../../widgets/genie_app_bar.dart';
import 'settings_scope.dart';
import 'settings_sections.dart';

/// `/settings/<name>`: one section on its own page. Goes under the
/// `/settings` route; an unknown name leads back to the section list.
final settingsSectionRoute = GoRoute(
  path: ':section',
  redirect: (context, state) =>
      settingsSectionNamed(state.pathParameters['section']!) == null
      ? '/settings'
      : null,
  builder: (context, state) => SettingsSectionScreen(
    section: settingsSectionNamed(state.pathParameters['section']!)!,
  ),
);

/// One settings section on its own page, unfiltered.
class SettingsSectionScreen extends StatefulWidget {
  const SettingsSectionScreen({super.key, required this.section});

  final SettingsSectionInfo section;

  @override
  State<SettingsSectionScreen> createState() => _SettingsSectionScreenState();
}

class _SettingsSectionScreenState extends State<SettingsSectionScreen> {
  @override
  void initState() {
    super.initState();
    // Opened from the section list, the data is already loading. After the
    // frame, like the list: loading notifies listeners that may be building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SettingsData>().ensureLoaded(
        context.read<ApiService>(),
        context.read<ThemeProvider>(),
        context.read<HubDirectoryProvider>(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<SettingsData>();
    final themeProvider = Provider.of<ThemeProvider>(context);
    final section = widget.section;

    return SettingsScope(
      data: data,
      query: '',
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: GenieAppBar(
          title: TranslationService.translate(context, section.titleKey),
          showQuickActions: false,
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: AppDesign.pageGradientForTheme(themeProvider.themeStyle),
          ),
          child: SafeArea(
            child: data.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: data.reload,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: AppDesign.maxContentWidth,
                          ),
                          child: section.builder(),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
