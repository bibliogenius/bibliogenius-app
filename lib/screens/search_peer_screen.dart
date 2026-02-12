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
          _error =
              '${TranslationService.translate(context, 'connection_error')}: $e';
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
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'request_sent_to')} ${peer['name']}',
            ),
          ),
        );
        context.pop(true); // Return true to refresh list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'connection_error')}: $e',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'nav_network'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: TranslationService.translate(context, 'nav_network'),
                hintText: TranslationService.translate(
                  context,
                  'peer_search_hint',
                ),
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
                        Icon(
                          Icons.person_search,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          TranslationService.translate(
                            context,
                            'peer_search_hint',
                          ),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            context.push('/p2p');
                          },
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(
                            TranslationService.translate(
                              context,
                              'scan_qr_code',
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final peer = _results[index];
                      final isLocal = peer['source'] == 'local';
                      final isConnected =
                          peer['status'] == 'active' ||
                          peer['status'] == 'pending';

                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white.withAlpha(13)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow:
                              Theme.of(context).brightness == Brightness.dark
                              ? []
                              : [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(13),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                          border: Border.all(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withAlpha(26)
                                : Colors.grey.withAlpha(26),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    (peer['status'] == 'active'
                                            ? Colors.indigo
                                            : (peer['status'] == 'pending'
                                                  ? Colors.orange
                                                  : Colors.teal))
                                        .withAlpha(26),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                peer['status'] == 'active'
                                    ? Icons.public_rounded
                                    : (peer['status'] == 'pending'
                                          ? Icons.hourglass_top_rounded
                                          : Icons.library_add_rounded),
                                color: peer['status'] == 'active'
                                    ? Colors.indigo
                                    : (peer['status'] == 'pending'
                                          ? Colors.orange
                                          : Colors.teal),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    peer['name'],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    peer['url'],
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (peer['status'] == 'active') ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withAlpha(26),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'CONNECTED',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                  if (peer['status'] == 'pending') ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withAlpha(26),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'PENDING',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (peer['status'] == 'active')
                              ElevatedButton(
                                onPressed: () {
                                  context.push(
                                    '/peers/${peer['id']}/books',
                                    extra: {
                                      'id': peer['id'],
                                      'name': peer['name'],
                                      'url': peer['url'],
                                    },
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.indigo,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text(
                                  'Browse',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              )
                            else if (peer['status'] == 'pending')
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withAlpha(26),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.orange.withAlpha(51),
                                  ),
                                ),
                                child: const Text(
                                  'Sent',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              )
                            else
                              ElevatedButton(
                                onPressed: () => _connect(peer),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  TranslationService.translate(
                                    context,
                                    'add_peer_btn',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
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
