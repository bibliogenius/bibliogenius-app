import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      final response = await apiService.login(
        _usernameController.text,
        _passwordController.text,
      );

      if (response.statusCode == 200) {
        final token = response.data['token'];
        await authService.saveToken(token);
        await authService.saveUsername(_usernameController.text);
        if (mounted) {
          context.go('/books');
        }
      } else {
        setState(() {
          _errorMessage = 'Login failed: ${response.statusMessage}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(TranslationService.translate(context, 'login_title')),
        leading: IconButton(
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
                      onPressed: () async {
                        // Clear any stored auth token/username when switching servers
                        final authService = Provider.of<AuthService>(context, listen: false);
                        await authService.logout();
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
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  TextField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(TranslationService.translate(context, 'login_btn')),
                          ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/setup'),
                    child: Text(TranslationService.translate(context, 'new_server_setup')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
