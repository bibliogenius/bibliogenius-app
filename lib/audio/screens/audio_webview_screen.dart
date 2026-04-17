import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/translation_service.dart';

/// Full-screen audio webview page for playing audiobooks.
///
/// This screen displays a WebView with the audiobook source site,
/// allowing users to listen to audiobooks without leaving the app.
class AudioWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const AudioWebViewScreen({super.key, required this.url, required this.title});

  @override
  State<AudioWebViewScreen> createState() => _AudioWebViewScreenState();
}

class _AudioWebViewScreenState extends State<AudioWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  double _loadingProgress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() {
              _loadingProgress = progress / 100;
              if (progress == 100) {
                _isLoading = false;
              }
            });
          },
          onPageStarted: (_) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: TranslationService.translate(context, 'close'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: TranslationService.translate(context, 'tooltip_refresh'),
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: TranslationService.translate(context, 'open_in_browser'),
            onPressed: () async {
              // Open in external browser as alternative
              final uri = Uri.parse(widget.url);
              // Using url_launcher would require importing it
              // For now just show info
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('URL: ${widget.url}')));
            },
          ),
        ],
        bottom: _isLoading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  value: _loadingProgress,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
