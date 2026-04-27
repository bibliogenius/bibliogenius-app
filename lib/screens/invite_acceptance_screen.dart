import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../providers/flash_message_provider.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';

/// Screen shown when the user opens an invite link (deep link or QR).
/// Displays the inviting library name and lets the user accept or decline.
class InviteAcceptanceScreen extends StatefulWidget {
  final Map<String, dynamic> payload;

  const InviteAcceptanceScreen({super.key, required this.payload});

  @override
  State<InviteAcceptanceScreen> createState() => _InviteAcceptanceScreenState();
}

class _InviteAcceptanceScreenState extends State<InviteAcceptanceScreen> {
  bool _isConnecting = false;
  String? _error;

  String get _libraryName =>
      widget.payload['name'] as String? ?? 'BiblioGenius';
  String? get _url {
    final raw = widget.payload['url'] as String?;
    if (raw == null || raw.isEmpty) return null;
    // Ensure scheme is present so Dio can parse the URL
    if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
      return 'http://$raw';
    }
    return raw;
  }

  String? get _ed25519Key => widget.payload['ed25519_public_key'] as String?;
  String? get _x25519Key => widget.payload['x25519_public_key'] as String?;
  String? get _libraryUuid => widget.payload['library_uuid'] as String?;
  String? get _relayUrl => widget.payload['relay_url'] as String?;
  String? get _mailboxId => widget.payload['mailbox_id'] as String?;
  String? get _relayWriteToken =>
      widget.payload['relay_write_token'] as String?;

  Future<void> _acceptInvite() async {
    // Accept if we have a LAN URL or relay credentials (or both)
    final hasLanUrl = _url != null && _url!.isNotEmpty;
    final hasRelay = _relayUrl != null && _mailboxId != null;

    if (!hasLanUrl && !hasRelay) {
      setState(
        () => _error = 'Invalid invite: missing URL and relay credentials',
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    final api = context.read<ApiService>();

    try {
      // Block self-connection: compare E2EE public keys
      final configRes = await api.getLibraryConfig();
      final myEd25519 = configRes.data['ed25519_public_key'] as String?;
      final inviteEd25519 = widget.payload['ed25519_public_key'] as String?;
      if (myEd25519 != null &&
          inviteEd25519 != null &&
          myEd25519 == inviteEd25519) {
        if (!mounted) return;
        setState(() {
          _isConnecting = false;
          _error = TranslationService.translate(context, 'invite_self_error');
        });
        return;
      }

      // Use empty URL for relay-only connections
      final connectUrl = _url ?? '';

      final response = await api.connectPeer(
        _libraryName,
        connectUrl,
        libraryUuid: _libraryUuid,
        ed25519PublicKey: _ed25519Key,
        x25519PublicKey: _x25519Key,
        relayUrl: _relayUrl,
        mailboxId: _mailboxId,
        relayWriteToken: _relayWriteToken,
      );

      // connectLocalPeer returns error responses instead of throwing
      if (response.statusCode != null && response.statusCode! >= 400) {
        final rawMsg = response.data is Map
            ? response.data['error'] ?? 'Connection failed'
            : response.data?.toString() ?? 'Connection failed';
        final errorMsg = TranslationService.translate(context, rawMsg);
        throw Exception(errorMsg);
      }

      if (!mounted) return;

      // Extract peer ID from connect response for prefetch
      final peerId = response.data is Map ? response.data['id'] as int? : null;

      context.read<FlashMessageProvider>().addEphemeralPeer(
        EphemeralPeerFlash(
          peerId: peerId ?? (connectUrl).hashCode & 0x7FFFFFFF,
          peerName: _libraryName,
          peerUrl: hasLanUrl ? _url : null,
          hasRelayCredentials: hasRelay,
          connectedAt: DateTime.now(),
        ),
      );

      // Prefetch peer's library in background so it's cached when user browses
      if (peerId != null && hasRelay) {
        _prefetchPeerLibrary(api, peerId);
      }

      context.go('/network');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnecting = false;
        _error = e.toString();
      });
    }
  }

  /// Fire-and-forget: prefetch peer library via relay so it's cached
  /// when the user navigates to the peer's book list.
  void _prefetchPeerLibrary(ApiService api, int peerId) {
    if (kDebugMode) debugPrint('Prefetch: starting background library fetch');
    () async {
      try {
        final manifest = await api.requestPeerManifest(peerId);
        if (manifest == null) {
          // Relay pending - poll and retry once
          await api.pollRelayNow();
          await Future.delayed(const Duration(seconds: 5));
          final retry = await api.requestPeerManifest(peerId);
          if (retry == null) {
            if (kDebugMode)
              debugPrint(
                'Prefetch: manifest not available yet, will load on browse',
              );
            return;
          }
          await _prefetchPages(api, peerId, retry);
        } else {
          await _prefetchPages(api, peerId, manifest);
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Prefetch error: $e');
      }
    }();
  }

  Future<void> _prefetchPages(
    ApiService api,
    int peerId,
    Map<String, dynamic> manifest,
  ) async {
    final totalBooks = manifest['total_books'] as int? ?? 0;
    if (totalBooks == 0) return;

    List<Map<String, dynamic>> allBooksJson = [];
    int? cursor;

    while (true) {
      final page = await api.requestPeerPage(peerId, cursor: cursor);
      if (page == null) break;

      final books = page['books'] as List? ?? [];
      allBooksJson.addAll(books.cast<Map<String, dynamic>>());

      cursor = page['next_cursor'] as int?;
      if (cursor == null) break;
    }

    if (allBooksJson.isNotEmpty) {
      final books = allBooksJson.map((json) => Book.fromJson(json)).toList();
      await api.cachePeerBooks(peerId, books);
      if (kDebugMode) debugPrint('Prefetch: cached ${books.length} books');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Library icon
                  Semantics(
                    image: true,
                    label: TranslationService.translate(
                      context,
                      'invite_library_icon',
                    ),
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.local_library_rounded,
                        size: 44,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // "Invitation from" label
                  Semantics(
                    header: true,
                    child: Text(
                      TranslationService.translate(context, 'invite_title'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Library name
                  Text(
                    _libraryName,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // Description
                  Text(
                    TranslationService.translate(context, 'invite_description'),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Connection info badges
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      if (_ed25519Key != null)
                        _buildBadge(
                          context,
                          Icons.lock_rounded,
                          TranslationService.translate(
                            context,
                            'invite_encrypted',
                          ),
                        ),
                      if (_relayUrl != null)
                        _buildBadge(
                          context,
                          Icons.cloud_rounded,
                          TranslationService.translate(
                            context,
                            'invite_remote_ready',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Error message
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 20,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Connect button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _isConnecting ? null : _acceptInvite,
                      icon: _isConnecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.handshake_rounded),
                      label: Text(
                        _isConnecting
                            ? TranslationService.translate(
                                context,
                                'invite_connecting',
                              )
                            : TranslationService.translate(
                                context,
                                'invite_connect',
                              ),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Decline button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _isConnecting
                          ? null
                          : () => context.go('/books'),
                      child: Text(
                        TranslationService.translate(context, 'invite_decline'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
