import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../utils/avatars.dart';
import '../models/avatar_config.dart';
import '../widgets/avatar_customizer.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _currentStep = 0;
  String _profileType = 'individual';
  AvatarConfig _avatarConfig = AvatarConfig.defaultConfig;

  Map<String, Map<String, String>> get _t => {
        'en': {
          'welcome_title': 'Welcome',
          'welcome_header': 'Welcome to BiblioGenius!',
          'welcome_body':
              'This app helps you manage your personal library, track loans, and connect with other book lovers.',
          'welcome_footer': 'Let\'s get you set up in just a few steps.',
          'lang_title': 'Select Language',
          'lang_label': 'Choose your preferred language:',
          'theme_title': 'Customize Theme',
          'theme_label': 'Choose a color for your app banner:',
          'finish_title': 'Ready to Go!',
          'finish_header': 'You are all set!',
          'finish_body': 'Click "Finish" to start adding books to your library.',
          'btn_next': 'Next',
          'btn_back': 'Back',
          'btn_finish': 'Finish',
        },
        'fr': {
          'welcome_title': 'Bienvenue',
          'welcome_header': 'Bienvenue sur BiblioGenius !',
          'welcome_body':
              'Gérez votre bibliothèque, suivez vos prêts et connectez-vous avec d\'autres passionnés.',
          'welcome_footer': 'Commençons la configuration.',
          'lang_title': 'Langue',
          'lang_label': 'Choisissez votre langue :',
          'theme_title': 'Thème',
          'theme_label': 'Choisissez la couleur de la bannière :',
          'finish_title': 'C\'est prêt !',
          'finish_header': 'Tout est configuré !',
          'finish_body': 'Cliquez sur "Terminer" pour commencer.',
          'btn_next': 'Suivant',
          'btn_back': 'Retour',
          'btn_finish': 'Terminer',
        },
        'es': {
          'welcome_title': 'Bienvenido',
          'welcome_header': '¡Bienvenido a BiblioGenius!',
          'welcome_body':
              'Gestiona tu biblioteca, sigue tus préstamos y conecta con otros lectores.',
          'welcome_footer': 'Empecemos la configuración.',
          'lang_title': 'Idioma',
          'lang_label': 'Elige tu idioma:',
          'theme_title': 'Tema',
          'theme_label': 'Elige el color del banner:',
          'finish_title': '¡Listo!',
          'finish_header': '¡Todo listo!',
          'finish_body': 'Haz clic en "Terminar" para empezar.',
          'btn_next': 'Siguiente',
          'btn_back': 'Atrás',
          'btn_finish': 'Terminar',
        },
        'de': {
          'welcome_title': 'Willkommen',
          'welcome_header': 'Willkommen bei BiblioGenius!',
          'welcome_body':
              'Verwalten Sie Ihre Bibliothek, verfolgen Sie Ausleihen und verbinden Sie sich mit anderen.',
          'welcome_footer': 'Lassen Sie uns beginnen.',
          'lang_title': 'Sprache',
          'lang_label': 'Wählen Sie Ihre Sprache:',
          'theme_title': 'Thema',
          'theme_label': 'Wählen Sie eine Bannerfarbe:',
          'finish_title': 'Fertig!',
          'finish_header': 'Alles bereit!',
          'finish_body': 'Klicken Sie auf "Fertigstellen", um zu beginnen.',
          'btn_next': 'Weiter',
          'btn_back': 'Zurück',
          'btn_finish': 'Fertigstellen',
        },
      };

  @override
  Widget build(BuildContext context) {
    // Removed Provider.of here to prevent full rebuilds
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final lang = themeProvider.locale.languageCode;
        final strings = _t[lang] ?? _t['en']!;

        return Scaffold(
          appBar: AppBar(
            title: Text(strings['welcome_header']!),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Server Settings',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController(
                        text: Provider.of<ApiService>(context, listen: false).baseUrl,
                      );
                      return AlertDialog(
                        title: const Text("Change Server URL"),
                        content: TextField(
                          controller: controller,
                          decoration: const InputDecoration(labelText: "Server URL"),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel"),
                          ),
                          TextButton(
                            onPressed: () {
                              Provider.of<ApiService>(context, listen: false).setBaseUrl(controller.text);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Switched to ${controller.text}")),
                              );
                            },
                            child: const Text("Save"),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
          body: Stepper(
            currentStep: _currentStep,
            onStepContinue: () {
              if (_currentStep < 5) {
                setState(() {
                  _currentStep += 1;
                });
              } else {
                _finishSetup(context);
              }
            },
            onStepTapped: (step) {
              setState(() {
                _currentStep = step;
              });
            },
            onStepCancel: () {
              if (_currentStep > 0) {
                setState(() {
                  _currentStep -= 1;
                });
              }
            },
            controlsBuilder: (context, details) {
              return Padding(
                padding: const EdgeInsets.only(top: 20.0),
                child: Row(
                  children: [
                    ElevatedButton(
                      onPressed: details.onStepContinue,
                      child: Text(
                        _currentStep == 5
                            ? strings['btn_finish']!
                            : strings['btn_next']!,
                      ),
                    ),
                    if (_currentStep > 0) ...[
                      const SizedBox(width: 10),
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(strings['btn_back']!),
                      ),
                    ],
                  ],
                ),
              );
            },
            steps: [
              Step(
                title: Text(strings['welcome_title']!),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings['welcome_header']!,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(strings['welcome_body']!),
                    const SizedBox(height: 10),
                    Text(strings['welcome_footer']!),
                  ],
                ),
                isActive: _currentStep >= 0,
                state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              ),
              Step(
                title: Text(TranslationService.translate(context, 'choose_profile_type')),
                content: Column(
                  children: [
                    Text(TranslationService.translate(context, 'profile_usage_question')),
                    const SizedBox(height: 16),
                    _buildProfileOption(
                      'librarian',
                      TranslationService.translate(context, 'profile_librarian'),
                      TranslationService.translate(context, 'profile_librarian_desc'),
                      Icons.local_library,
                    ),
                    _buildProfileOption(
                      'individual',
                      TranslationService.translate(context, 'profile_individual'),
                      TranslationService.translate(context, 'profile_individual_desc'),
                      Icons.person,
                    ),
                    _buildProfileOption(
                      'kid',
                      TranslationService.translate(context, 'profile_kid'),
                      TranslationService.translate(context, 'profile_kid_desc'),
                      Icons.child_care,
                    ),
                  ],
                ),
                isActive: _currentStep >= 1,
                state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              ),
              Step(
                title: Text(TranslationService.translate(context, 'customize_avatar')),
                content: SizedBox(
                  height: 500,
                  child: AvatarCustomizer(
                    initialConfig: _avatarConfig,
                    onConfigChanged: (config) {
                      setState(() {
                        _avatarConfig = config;
                      });
                      // Update theme based on avatar colors if desired
                      // For now, we just store the config
                    },
                  ),
                ),
                isActive: _currentStep >= 2,
                state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              ),
              Step(
                title: Text(strings['lang_title']!),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings['lang_label']!),
                    const SizedBox(height: 10),
                    DropdownButton<String>(
                      value: themeProvider.locale.languageCode,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: 'en', child: Text(TranslationService.translate(context, 'lang_en'))),
                        DropdownMenuItem(value: 'fr', child: Text(TranslationService.translate(context, 'lang_fr'))),
                        DropdownMenuItem(value: 'es', child: Text(TranslationService.translate(context, 'lang_es'))),
                        DropdownMenuItem(value: 'de', child: Text(TranslationService.translate(context, 'lang_de'))),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          themeProvider.setLocale(Locale(newValue));
                        }
                      },
                    ),
                  ],
                ),
                isActive: _currentStep >= 3,
                state: _currentStep > 3 ? StepState.complete : StepState.indexed,
              ),
              Step(
                title: Text(strings['theme_title']!),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings['theme_label']!),
                    const SizedBox(height: 10),
                    // Theme Style Selector
                    DropdownButton<String>(
                      value: themeProvider.themeStyle,
                      isExpanded: true,
                      items: [
                        DropdownMenuItem(value: 'default', child: Text(TranslationService.translate(context, 'theme_default'))),
                        DropdownMenuItem(value: 'minimal', child: Text(TranslationService.translate(context, 'theme_minimal'))),
                      ],
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          themeProvider.setThemeStyle(newValue);
                        }
                      },
                    ),

                  ],
                ),
                isActive: _currentStep >= 4,
                state: _currentStep > 4 ? StepState.complete : StepState.indexed,
              ),
              Step(
                title: Text(strings['finish_title']!),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings['finish_header']!,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(strings['finish_body']!),
                  ],
                ),
                isActive: _currentStep >= 5,
                state: _currentStep == 5 ? StepState.complete : StepState.indexed,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _finishSetup(BuildContext context) async {
    try {
      // Call backend setup to create admin user
      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.setup(
        libraryName: 'My Library', // Default name, could be added to UI
        profileType: _profileType,
        theme: Provider.of<ThemeProvider>(context, listen: false).themeStyle,
      );

      if (context.mounted) {
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        // Pass apiService to ensure sync with backend (although setup endpoint does some of this, 
        // setAvatarConfig is needed for the avatar)
        await themeProvider.setProfileType(_profileType, apiService: apiService);
        await themeProvider.setAvatarConfig(_avatarConfig, apiService: apiService);
        await themeProvider.completeSetup();
        
        // Auto-login after setup
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.saveUsername('admin');
        // Note: In a real app, we'd get a token here, but for now we redirect to login
        // or we could have the setup endpoint return a token.
        // For simplicity, let's redirect to login and let them login as admin/admin
        
        if (context.mounted) {
           context.go('/login');
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'setup_failed')}: $e')),
        );
      }
    }
  }
  Widget _buildProfileOption(String value, String title, String description, IconData icon) {
    final isSelected = _profileType == value;
    return GestureDetector(
      onTap: () => setState(() => _profileType = value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 32, color: isSelected ? Colors.blue : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.blue : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.blue),
          ],
        ),
      ),
    );
  }
}
