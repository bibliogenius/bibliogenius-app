import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../services/demo_service.dart';
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
  final TextEditingController _libraryNameController = TextEditingController(text: 'My Library');
  bool _importDemo = false;

  Map<String, Map<String, String>> get _t => {
        'en': {
          'welcome_title': 'Welcome',
          'welcome_header': 'Welcome to BiblioGenius!',
          'welcome_body':
              'This app helps you manage your personal library, track loans, and connect with other book lovers.',
          'welcome_footer': 'Let\'s get you set up in just a few steps.',
          'library_info_title': 'Library Info',
          'library_name_label': 'Library Name',
          'library_name_hint': 'e.g. The Book Cave',
          'profile_type_label': 'Profile Type',
          'demo_title': 'Demo Content',
          'demo_header': 'Start with some books?',
          'demo_body': 'We can add a few classic books to your library so you can explore the features immediately.',
          'demo_option_yes': 'Yes, import demo books',
          'demo_option_no': 'No, start empty',
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
          'setup_progress': 'Setting up your library...',
        },
        'fr': {
          'welcome_title': 'Bienvenue',
          'welcome_header': 'Bienvenue sur BiblioGenius !',
          'welcome_body':
              'Gérez votre bibliothèque, suivez vos prêts et connectez-vous avec d\'autres passionnés.',
          'welcome_footer': 'Commençons la configuration.',
          'library_info_title': 'Infos Bibliothèque',
          'library_name_label': 'Nom de la bibliothèque',
          'library_name_hint': 'ex: La Caverne aux Livres',
          'profile_type_label': 'Type de profil',
          'demo_title': 'Contenu Démo',
          'demo_header': 'Commencer avec des livres ?',
          'demo_body': 'Nous pouvons ajouter quelques classiques pour vous permettre de tester les fonctionnalités.',
          'demo_option_yes': 'Oui, importer des livres démo',
          'demo_option_no': 'Non, commencer vide',
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
          'setup_progress': 'Configuration en cours...',
        },
        // ... (other languages kept as is or updated similarly if needed, for brevity assuming EN/FR focus for now)
        'es': {
           'welcome_title': 'Bienvenido',
           'welcome_header': '¡Bienvenido a BiblioGenius!',
           'welcome_body': 'Gestiona tu biblioteca, sigue tus préstamos y conecta con otros lectores.',
           'welcome_footer': 'Empecemos la configuración.',
           'library_info_title': 'Info Biblioteca',
           'library_name_label': 'Nombre de la biblioteca',
           'library_name_hint': 'ej: La Cueva de los Libros',
           'profile_type_label': 'Tipo de perfil',
           'demo_title': 'Contenido Demo',
           'demo_header': '¿Empezar con libros?',
           'demo_body': 'Podemos añadir algunos clásicos para que pruebes las funciones.',
           'demo_option_yes': 'Sí, importar libros demo',
           'demo_option_no': 'No, empezar vacío',
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
           'setup_progress': 'Configurando...',
        },
        'de': {
           'welcome_title': 'Willkommen',
           'welcome_header': 'Willkommen bei BiblioGenius!',
           'welcome_body': 'Verwalten Sie Ihre Bibliothek, verfolgen Sie Ausleihen und verbinden Sie sich mit anderen.',
           'welcome_footer': 'Lassen Sie uns beginnen.',
           'library_info_title': 'Bibliotheksinfo',
           'library_name_label': 'Bibliotheksname',
           'library_name_hint': 'z.B. Die Bücherhöhle',
           'profile_type_label': 'Profiltyp',
           'demo_title': 'Demo-Inhalt',
           'demo_header': 'Mit Büchern starten?',
           'demo_body': 'Wir können einige Klassiker hinzufügen, damit Sie die Funktionen testen können.',
           'demo_option_yes': 'Ja, Demo-Bücher importieren',
           'demo_option_no': 'Nein, leer starten',
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
           'setup_progress': 'Einrichtung läuft...',
        }
      };

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final lang = themeProvider.locale.languageCode;
        final strings = _t[lang] ?? _t['en']!;

        return Scaffold(
          appBar: AppBar(
            title: Text(strings['welcome_header']!),
            automaticallyImplyLeading: false, // Hide back button
          ),
          body: Stepper(
            currentStep: _currentStep,
            onStepContinue: () {
              if (_currentStep < 5) {
                setState(() {
                  _currentStep += 1;
                });
              } else {
                _finishSetup(context, strings);
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
              // Step 0: Welcome
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
              // Step 1: Profile & Library Info
              Step(
                title: Text(strings['library_info_title']!),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _libraryNameController,
                      decoration: InputDecoration(
                        labelText: strings['library_name_label'],
                        hintText: strings['library_name_hint'],
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(TranslationService.translate(context, 'profile_usage_question')),
                    const SizedBox(height: 10),
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
              // Step 2: Avatar
              Step(
                title: Text(TranslationService.translate(context, 'customize_avatar')),
                content: SizedBox(
                  height: 400,
                  child: AvatarCustomizer(
                    initialConfig: _avatarConfig,
                    onConfigChanged: (config) {
                      setState(() {
                        _avatarConfig = config;
                      });
                    },
                  ),
                ),
                isActive: _currentStep >= 2,
                state: _currentStep > 2 ? StepState.complete : StepState.indexed,
              ),
              // Step 3: Demo Content
              Step(
                title: Text(strings['demo_title']!),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings['demo_header']!, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(strings['demo_body']!),
                    const SizedBox(height: 16),
                    RadioListTile<bool>(
                      title: Text(strings['demo_option_yes']!),
                      value: true,
                      groupValue: _importDemo,
                      onChanged: (val) => setState(() => _importDemo = val!),
                    ),
                    RadioListTile<bool>(
                      title: Text(strings['demo_option_no']!),
                      value: false,
                      groupValue: _importDemo,
                      onChanged: (val) => setState(() => _importDemo = val!),
                    ),
                  ],
                ),
                isActive: _currentStep >= 3,
                state: _currentStep > 3 ? StepState.complete : StepState.indexed,
              ),
              // Step 4: Language & Theme (Combined for brevity or keep separate if preferred, keeping separate to match count)
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
                    const SizedBox(height: 20),
                     Text(strings['theme_title']!),
                     const SizedBox(height: 10),
                     Text(strings['theme_label']!),
                     const SizedBox(height: 10),
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
              // Step 5: Finish
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

  Future<void> _finishSetup(BuildContext context, Map<String, String> strings) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(child: CircularProgressIndicator()),
    );

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      
      // 1. Setup Backend
      await apiService.setup(
        libraryName: _libraryNameController.text.isNotEmpty ? _libraryNameController.text : 'My Library',
        profileType: _profileType,
        theme: Provider.of<ThemeProvider>(context, listen: false).themeStyle,
      );

      // 2. Import Demo Data if requested
      if (_importDemo) {
        await DemoService.importDemoBooks(context);
      }

      if (context.mounted) {
        final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
        await themeProvider.setProfileType(_profileType, apiService: apiService);
        await themeProvider.setAvatarConfig(_avatarConfig, apiService: apiService);
        await themeProvider.completeSetup();
        
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.saveUsername('admin');
        
        // Close loading dialog
        Navigator.of(context).pop();

        if (context.mounted) {
           context.go('/login');
        }
      }
    } catch (e) {
      // Close loading dialog
      if (context.mounted) Navigator.of(context).pop();
      
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
