import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/theme_provider.dart';
import '../screens/invite_screen.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../utils/invite_payload.dart';

/// Generates the invite link and opens the native share sheet directly.
///
/// Shows a brief loading snackbar while generating. Falls back to the
/// invitation screen (which carries the error state and a retry) when the
/// invite cannot be generated. Used by the contextual entries only (the
/// network banner and the post-pairing dialog): the context there is
/// explicit, so sharing stays a one-tap gesture.
Future<void> shareInviteLinkDirect(BuildContext context) async {
  // Capture everything from context before any await
  final messenger = ScaffoldMessenger.of(context);
  final apiService = Provider.of<ApiService>(context, listen: false);
  final libraryName = Provider.of<ThemeProvider>(
    context,
    listen: false,
  ).libraryName;
  final loadingText = TranslationService.translate(
    context,
    'generating_invite_link',
  );
  final messageTemplate = TranslationService.translate(
    context,
    'invite_share_message',
  );

  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Text(loadingText),
        ],
      ),
      duration: const Duration(seconds: 10),
    ),
  );

  try {
    final result = await loadInviteLink(
      libraryName: libraryName,
      fetchLibraryConfig: () async =>
          (await apiService.getLibraryConfig()).data as Map,
      httpPort: ApiService.httpPort,
      hubBaseUrl: ApiService.hubUrl,
    );

    if (result == null) {
      messenger.hideCurrentSnackBar();
      // Cannot generate link: the invitation screen explains why and offers a retry
      if (context.mounted) showInviteScreen(context);
      return;
    }
    final link = result.link;

    messenger.hideCurrentSnackBar();

    final message = messageTemplate
        .replaceAll('{name}', libraryName)
        .replaceAll('{link}', link);

    final box = context.mounted
        ? context.findRenderObject() as RenderBox?
        : null;
    final origin = box != null
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await Share.share(message, sharePositionOrigin: origin);
  } catch (e) {
    debugPrint('shareInviteLinkDirect: error: $e');
    messenger.hideCurrentSnackBar();
    if (context.mounted) showInviteScreen(context);
  }
}
