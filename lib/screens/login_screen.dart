import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart'; // Import DioException
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeIn));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  Future<void> _onLoginSuccess(String token, String username) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    await authService.saveToken(token);
    await authService.saveUsername(username);

    // Fetch user context
    try {
      final meResponse = await apiService.getMe();
      if (meResponse.statusCode == 200) {
        final data = meResponse.data;
        await authService.saveUserId(data['user_id']);
        await authService.saveLibraryId(data['library_id']);
      }
    } catch (e) {
      debugPrint('Failed to fetch user context: $e');
    }

    if (mounted) {
      context.go('/books');
    }
  }

  Future<void> _showMfaDialog(String username, String password) async {
    final codeController = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            TranslationService.translate(context, 'two_factor_auth') ??
                'Two-Factor Authentication',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                TranslationService.translate(context, 'enter_mfa_code') ??
                    'Enter the 6-digit code from your authenticator app.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Code',
                  errorText: errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // Cancel login
              child: Text(
                TranslationService.translate(context, 'cancel') ?? 'Cancel',
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                setState(() => errorText = null);
                final code = codeController.text.trim();
                if (code.length != 6) {
                  setState(() => errorText = 'Invalid code length');
                  return;
                }

                final apiService = Provider.of<ApiService>(
                  context,
                  listen: false,
                );
                try {
                  final response = await apiService.loginMfa(
                    username,
                    password,
                    code,
                  );
                  if (response.statusCode == 200) {
                    Navigator.pop(context); // Close dialog
                    _onLoginSuccess(response.data['token'], username);
                  } else {
                    setState(() => errorText = 'Invalid code');
                  }
                } catch (e) {
                  setState(() => errorText = 'Verification failed');
                }
              },
              child: Text(
                TranslationService.translate(context, 'verify') ?? 'Verify',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);

    try {
      final response = await apiService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (response.statusCode == 200) {
        await _onLoginSuccess(response.data['token'], _usernameController.text);
      } else {
        setState(() {
          _errorMessage = 'Invalid credentials';
        });
      }
    } catch (e) {
      if (e is DioException &&
          e.response?.statusCode == 403 &&
          e.response?.data['error'] == 'mfa_required') {
        // MFA Required
        if (mounted) {
          setState(
            () => _isLoading = false,
          ); // Stop loading indicator on main screen
          _showMfaDialog(_usernameController.text, _passwordController.text);
          return;
        }
      }

      setState(() {
        _errorMessage =
            'Login failed: ${e is DioException ? e.message : e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showServerSettings() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isSorbonne = themeProvider.themeStyle == 'sorbonne';

    // Theme colors
    final primaryColor = Theme.of(context).colorScheme.primary;
    final backgroundColor = Theme.of(context).colorScheme.surface;
    final cardColor = Theme.of(context).cardColor;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final controller = TextEditingController(
          text: Provider.of<ApiService>(context, listen: false).baseUrl,
        );
        return Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.dns, color: primaryColor),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      TranslationService.translate(
                            context,
                            'server_settings_title',
                          ) ??
                          'Server Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: controller,
                  style: TextStyle(color: onSurface),
                  decoration: InputDecoration(
                    labelText:
                        TranslationService.translate(
                          context,
                          'server_url_label',
                        ) ??
                        'Server URL',
                    hintText: 'http://localhost:8000',
                    prefixIcon: Icon(
                      Icons.link,
                      color: isSorbonne ? primaryColor : null,
                    ),
                    filled: true,
                    fillColor: isSorbonne
                        ? Theme.of(context).scaffoldBackgroundColor
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: isSorbonne
                          ? BorderSide(color: primaryColor.withOpacity(0.5))
                          : const BorderSide(),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: isSorbonne
                          ? BorderSide(color: primaryColor.withOpacity(0.3))
                          : const BorderSide(color: Colors.grey),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          foregroundColor: isSorbonne ? primaryColor : null,
                          side: isSorbonne
                              ? BorderSide(color: primaryColor.withOpacity(0.5))
                              : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          TranslationService.translate(context, 'cancel') ??
                              'Cancel',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final authService = Provider.of<AuthService>(
                            context,
                            listen: false,
                          );
                          final apiService = Provider.of<ApiService>(
                            context,
                            listen: false,
                          );
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);

                          await authService.logout();
                          apiService.setBaseUrl(controller.text);
                          navigator.pop();
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                '${TranslationService.translate(context, 'server_changed') ?? 'Server changed to'} ${controller.text}',
                              ),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: primaryColor,
                            ),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: isSorbonne ? 4 : 2,
                        ),
                        child: Text(
                          TranslationService.translate(context, 'save') ??
                              'Save',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go('/books');
                    },
                    child: Text(
                      TranslationService.translate(
                            context,
                            'new_server_setup',
                          ) ??
                          'Setup Wizard',
                      style: TextStyle(color: primaryColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isSorbonne = themeProvider.themeStyle == 'sorbonne';

    // Choose background based on theme
    final Gradient bgGradient = isSorbonne
        ? AppDesign.sorbonnePageGradient
        : AppDesign.primaryGradient;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: bgGradient),
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Logo
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.auto_stories,
                              size: 40,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            TranslationService.translate(context, 'app_title'),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Login Card
                          Container(
                            constraints: const BoxConstraints(maxWidth: 400),
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: AppDesign.elevatedShadow,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  TranslationService.translate(
                                    context,
                                    'login_title',
                                  ),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  TranslationService.translate(
                                        context,
                                        'login_subtitle',
                                      ) ??
                                      'Sign in to access your library',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.color
                                            ?.withOpacity(0.7),
                                      ),
                                ),
                                const SizedBox(height: 24),

                                // Error message
                                if (_errorMessage != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.error,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                TextField(
                                  key: const Key('usernameField'),
                                  controller: _usernameController,
                                  focusNode: _usernameFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                  decoration: InputDecoration(
                                    labelText:
                                        TranslationService.translate(
                                          context,
                                          'username',
                                        ) ??
                                        'Username',
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Password field
                                TextField(
                                  key: const Key('passwordField'),
                                  controller: _passwordController,
                                  focusNode: _passwordFocus,
                                  obscureText: _obscurePassword,
                                  onSubmitted: (_) => _login(),
                                  decoration: InputDecoration(
                                    labelText:
                                        TranslationService.translate(
                                          context,
                                          'password',
                                        ) ??
                                        'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                      onPressed: () {
                                        setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        );
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Login button
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    key: const Key('loginButton'),
                                    onPressed: _isLoading ? null : _login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Theme.of(
                                        context,
                                      ).primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    Colors.white,
                                                  ),
                                            ),
                                          )
                                        : Text(
                                            TranslationService.translate(
                                              context,
                                              'login_btn',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Server settings button
                          TextButton.icon(
                            onPressed: _showServerSettings,
                            icon: const Icon(
                              Icons.settings,
                              color: Colors.white70,
                              size: 18,
                            ),
                            label: Text(
                              TranslationService.translate(
                                    context,
                                    'server_settings_title',
                                  ) ??
                                  'Server Settings',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Version display at bottom
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    'v0.5.0-alpha.2+2',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
