import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';


class PeerListScreen extends StatefulWidget {
  const PeerListScreen({super.key});

  @override
  State<PeerListScreen> createState() => _PeerListScreenState();
}

class _PeerListScreenState extends State<PeerListScreen> {
  List<dynamic> _peers = [];
  bool _isLoading = true;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchPeers();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _fetchPeers(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchPeers({bool silent = false}) async {
    if (!silent && _peers.isEmpty) setState(() => _isLoading = true);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      // Get current library config to know our own URL
      final configRes = await api.getLibraryConfig();
      final myUrl = configRes.data['default_uri'] as String?;
      
      final res = await api.getPeers();
      if (mounted) {
        setState(() {
          // Filter out own library from the list
          final allPeers = (res.data['data'] ?? []) as List;
          _peers = allPeers.where((peer) {
            // Exclude if URL matches our own
            if (myUrl != null && peer['url'] == myUrl) {
              return false;
            }
            return true;
          }).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addToFriends(Map<String, dynamic> peer) async {
    final api = Provider.of<ApiService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isPro = themeProvider.isLibrarian;
    
    try {
      await api.createContact({
        'name': peer['name'],
        'type': isPro ? 'library' : 'borrower',
        'email': null,
        'phone': null,
        'notes': '${TranslationService.translate(context, 'added_from_network')} (URL: ${peer['url']})',
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${peer['name']} ${isPro ? TranslationService.translate(context, 'added_to_borrowers') : TranslationService.translate(context, 'added_to_contacts')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_adding')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(title: TranslationService.translate(context, 'network_libraries_title')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/peers/search'),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchPeers,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _peers.length,
                itemBuilder: (context, index) {
                  final peer = _peers[index];
                  final isPending = peer['status'] == 'pending';
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                      border: Border.all(
                        color: Theme.of(context).dividerColor.withOpacity(0.1),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        radius: 24,
                        backgroundColor: isPending 
                            ? Colors.orange.withOpacity(0.1) 
                            : Colors.indigo.withOpacity(0.1),
                        child: Icon(
                          isPending ? Icons.hourglass_empty : Icons.public,
                          color: isPending ? Colors.orange : Colors.indigo,
                        ),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              peer['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isPending ? Colors.grey[700] : Colors.black87,
                              ),
                            ),
                          ),
                          if (isPending)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.orange.withOpacity(0.3)),
                              ),
                              child: Text(
                                TranslationService.translate(context, 'status_waiting'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          isPending 
                            ? '${peer['url']} • ${TranslationService.translate(context, 'request_sent')}' 
                            : peer['url'],
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                      ),
                      trailing: isPending
                          ? IconButton(
                              icon: const Icon(Icons.cancel_outlined, color: Colors.orange),
                              tooltip: TranslationService.translate(context, 'tooltip_cancel_request'),
                              onPressed: () => _confirmDeletePeer(peer),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.sync, color: Colors.indigo),
                                  tooltip: TranslationService.translate(context, 'tooltip_sync'),
                                  onPressed: () async {
                                    final api = Provider.of<ApiService>(context, listen: false);
                                    await api.syncPeer(peer['url']);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(TranslationService.translate(context, 'sync_started'))),
                                    );
                                  },
                                ),
                                IconButton(
                                icon: const Icon(Icons.person_add_alt_1, color: Colors.green),
                                tooltip: TranslationService.translate(context, 'tooltip_add_contact'),
                                onPressed: () => _addToFriends(peer),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: TranslationService.translate(context, 'tooltip_remove_library'),
                                onPressed: () => _confirmDeletePeer(peer),
                              ),
                              ],
                            ),
                      onTap: isPending 
                        ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(TranslationService.translate(context, 'library_not_accepted'))),
                            );
                          }
                        : () {
                            context.push('/peers/${peer['id']}/books', extra: peer);
                          },
                    ),
                  );
                },
              ),
            ),
    );
  }


  Future<void> _confirmDeletePeer(Map<String, dynamic> peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'dialog_remove_library_title')),
        content: Text(TranslationService.translate(context, 'dialog_remove_library_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'btn_remove')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        await api.deletePeer(peer['id']);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(TranslationService.translate(context, 'library_removed'))),
          );
          _fetchPeers(); // Refresh the list
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${TranslationService.translate(context, 'error_removing')}: $e')),
          );
        }
      }
    }
  }
}
