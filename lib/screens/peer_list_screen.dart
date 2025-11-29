import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../services/api_service.dart';

class PeerListScreen extends StatefulWidget {
  const PeerListScreen({super.key});

  @override
  State<PeerListScreen> createState() => _PeerListScreenState();
}

class _PeerListScreenState extends State<PeerListScreen> {
  List<dynamic> _peers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchPeers();
  }

  Future<void> _fetchPeers() async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final res = await api.getPeers();
      setState(() {
        _peers = res.data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Network Libraries")),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddPeerDialog(context),
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _peers.length,
              itemBuilder: (context, index) {
                final peer = _peers[index];
                return ListTile(
                  title: Text(peer['name']),
                  subtitle: Text(peer['url']),
                  trailing: IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: () async {
                      final api = Provider.of<ApiService>(context, listen: false);
                      await api.syncPeer(peer['id']);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sync started')),
                      );
                    },
                  ),
                  onTap: () {
                    context.push('/peers/${peer['id']}/books', extra: peer);
                  },
                );
              },
            ),
    );
  }

  void _showAddPeerDialog(BuildContext context) {
    final nameController = TextEditingController();
    final urlController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Network Library"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: "Library Name"),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: "Server URL (e.g. http://bibliogenius-b:8000)"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final api = Provider.of<ApiService>(context, listen: false);
              try {
                await api.connectPeer(nameController.text, urlController.text);
                Navigator.pop(context);
                _fetchPeers();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }
}
