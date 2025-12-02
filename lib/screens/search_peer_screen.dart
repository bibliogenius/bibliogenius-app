import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart';

class SearchPeerScreen extends StatefulWidget {
  const SearchPeerScreen({super.key});

  @override
  State<SearchPeerScreen> createState() => _SearchPeerScreenState();
}

class _SearchPeerScreenState extends State<SearchPeerScreen> {
  final _searchController = TextEditingController();
  List<dynamic> _results = [];
  bool _isLoading = false;
  String? _error;

  Future<void> _search(String query) async {
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // We need to add searchPeers to ApiService first, but assuming it exists or using direct call for now
      // Actually, let's use the dio instance from ApiService if possible, or add the method.
      // For now, I'll assume we added searchPeers to ApiService.
      final response = await api.searchPeers(query);
      
      if (mounted) {
        setState(() {
          _results = response.data['data'] ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '${TranslationService.translate(context, 'connection_error')}: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _connect(Map<String, dynamic> peer) async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      await api.connectPeer(peer['name'], peer['url']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'request_sent_to')} ${peer['name']}')),
        );
        context.pop(true); // Return true to refresh list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'connection_error')}: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(title: TranslationService.translate(context, 'nav_network')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'nav_network'),
                hintText: TranslationService.translate(context, 'peer_search_hint'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () => _search(_searchController.text),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onSubmitted: _search,
            ),
          ),
          if (_isLoading)
            const LinearProgressIndicator()
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          TranslationService.translate(context, 'peer_search_hint'),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            // TODO: Navigate to QR Scan
                          }, 
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(TranslationService.translate(context, 'scan_qr_code')),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final peer = _results[index];
                      final isLocal = peer['source'] == 'local';
                      final isConnected = peer['status'] == 'active' || peer['status'] == 'pending';

                      return ListTile(
                        leading: CircleAvatar(
                          child: Icon(isLocal ? Icons.bookmark : Icons.public),
                        ),
                        title: Text(peer['name']),
                        subtitle: Text(peer['url']),
                        trailing: isConnected
                            ? Chip(label: Text(TranslationService.translate(context, 'already_connected')))
                            : ElevatedButton(
                                onPressed: () => _connect(peer),
                                child: Text(TranslationService.translate(context, 'add_peer_btn')),
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
