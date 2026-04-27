import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../providers/theme_provider.dart';
import '../services/translation_service.dart';

/// A microphone button that appends speech-to-text results to a [TextEditingController].
///
/// Handles initialization, permission requests, listening state,
/// and graceful degradation (hides itself if speech is not available).
class SpeechNoteButton extends StatefulWidget {
  final TextEditingController controller;

  const SpeechNoteButton({super.key, required this.controller});

  @override
  State<SpeechNoteButton> createState() => _SpeechNoteButtonState();
}

class _SpeechNoteButtonState extends State<SpeechNoteButton> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _listening = false;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    _available = await _speech.initialize(
      onStatus: (_) {
        if (mounted) setState(() => _listening = _speech.isListening);
      },
      onError: (error) {
        if (mounted) setState(() => _listening = false);
        debugPrint('SpeechToText error: ${error.errorMsg}');
      },
    );
    _initialized = true;
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    // Capture context-dependent values before any async gap
    final locale = context.read<ThemeProvider>().locale;
    final localeId =
        '${locale.languageCode}_${locale.countryCode ?? locale.languageCode.toUpperCase()}';
    final notAvailableMsg = TranslationService.translate(
      context,
      'speech_not_available',
    );

    await _ensureInitialized();

    if (!_available) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notAvailableMsg)));
      }
      return;
    }

    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    } else {
      if (mounted) setState(() => _listening = true);
      await _speech.listen(
        onResult: (result) {
          if (result.finalResult && result.recognizedWords.isNotEmpty) {
            final current = widget.controller.text;
            final sep = current.isNotEmpty && !current.endsWith(' ') ? ' ' : '';
            widget.controller.text = '$current$sep${result.recognizedWords}';
            widget.controller.selection = TextSelection.fromPosition(
              TextPosition(offset: widget.controller.text.length),
            );
          }
        },
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_listening) _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _toggleListening,
      icon: Icon(
        _listening ? Icons.mic : Icons.mic_none,
        color: _listening ? Theme.of(context).colorScheme.primary : null,
      ),
      tooltip: _listening
          ? TranslationService.translate(context, 'speech_listening')
          : TranslationService.translate(context, 'tooltip_dictate_note'),
    );
  }
}
