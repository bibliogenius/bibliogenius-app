import 'package:flutter/material.dart';
import '../services/backend_service.dart';

class AppLifecycleObserver extends StatefulWidget {
  final Widget child;
  final BackendService backendService;

  const AppLifecycleObserver({
    super.key,
    required this.child,
    required this.backendService,
  });

  @override
  State<AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<AppLifecycleObserver> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      debugPrint('App detached, stopping backend...');
      widget.backendService.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
