import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../providers/theme_provider.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkSetupStatus();
  }

  Future<void> _checkSetupStatus() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final apiService = Provider.of<ApiService>(context, listen: false);

    // 1. Check local preference first
    if (themeProvider.isSetupComplete) {
      if (mounted) context.go('/login');
      return;
    }

    // 2. Check backend
    try {
      final res = await apiService.getLibraryConfig();
      if (res.statusCode == 200) {
        // Setup is already done on backend!
        await themeProvider.completeSetup();
        if (mounted) context.go('/login');
      } else {
        // Not set up
        if (mounted) context.go('/setup');
      }
    } catch (e) {
      // Error connecting or 404, assume setup needed or offline
      // For now, go to setup if we can't confirm config exists
      if (mounted) context.go('/setup');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
