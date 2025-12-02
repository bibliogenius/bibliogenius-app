import 'package:flutter/material.dart';
import '../widgets/genie_app_bar.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/translation_service.dart';

class BorrowRequestsScreen extends StatefulWidget {
  const BorrowRequestsScreen({super.key});

  @override
  State<BorrowRequestsScreen> createState() => _BorrowRequestsScreenState();
}

class _BorrowRequestsScreenState extends State<BorrowRequestsScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;
  late TabController _tabController;
  bool _isLoading = false;
  List<dynamic> _incomingRequests = [];
  List<dynamic> _outgoingRequests = [];
  List<dynamic> _connectionRequests = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchRequests();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchRequests(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchRequests({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final inRes = await api.getIncomingRequests();
      final outRes = await api.getOutgoingRequests();
      final connRes = await api.getPendingPeers();
      if (mounted) {
        setState(() {
          _incomingRequests = inRes.data;
          _outgoingRequests = outRes.data;
          _connectionRequests = connRes.data['requests'] ?? [];
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${TranslationService.translate(context, 'snack_error_fetching')}: $e")),
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateStatus(String id, String status) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.updateRequestStatus(id, status);
      _fetchRequests(); // Refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${TranslationService.translate(context, 'snack_error_updating')}: $e")),
        );
      }
    }
  }

  Future<void> _updatePeerStatus(int id, String status) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.updatePeerStatus(id, status);
      _fetchRequests();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${TranslationService.translate(context, 'snack_connection_updated')}: $status")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error updating peer status: $e")),
        );
      }
    }
  }

  Future<void> _deleteRequest(String id, {bool isOutgoing = false}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'dialog_delete_title')),
        content: Text(TranslationService.translate(context, 'dialog_delete_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(TranslationService.translate(context, 'dialog_delete_confirm'), style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final api = Provider.of<ApiService>(context, listen: false);
    try {
      if (isOutgoing) {
        await api.deleteOutgoingRequest(id);
      } else {
        await api.deleteRequest(id);
      }
      _fetchRequests(); // Refresh
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error deleting request: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'borrow_requests_title'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).appBarTheme.foregroundColor,
          unselectedLabelColor: Theme.of(context).appBarTheme.foregroundColor?.withValues(alpha: 0.7),
          indicatorColor: Theme.of(context).appBarTheme.foregroundColor,
          tabs: [
            Tab(icon: const Icon(Icons.move_to_inbox), text: TranslationService.translate(context, 'tab_incoming')),
            Tab(icon: const Icon(Icons.outbox), text: TranslationService.translate(context, 'tab_outgoing')),
            Tab(icon: const Icon(Icons.link), text: TranslationService.translate(context, 'tab_connections')),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRequests,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                RefreshIndicator(
                  onRefresh: _fetchRequests,
                  child: _buildIncomingList(),
                ),
                RefreshIndicator(
                  onRefresh: _fetchRequests,
                  child: _buildOutgoingList(),
                ),
                RefreshIndicator(
                  onRefresh: _fetchRequests,
                  child: _buildConnectionList(),
                ),
              ],
            ),
    );
  }

  Widget _buildIncomingList() {
    if (_incomingRequests.isEmpty) {
      return _buildEmptyState(TranslationService.translate(context, 'no_incoming_requests'));
    }
    return ListView.builder(
      itemCount: _incomingRequests.length,
      itemBuilder: (context, index) {
        final req = _incomingRequests[index];
        return _buildRequestTile(req, isIncoming: true);
      },
    );
  }

  Widget _buildOutgoingList() {
    if (_outgoingRequests.isEmpty) {
      return _buildEmptyState(TranslationService.translate(context, 'no_outgoing_requests'));
    }
    return ListView.builder(
      itemCount: _outgoingRequests.length,
      itemBuilder: (context, index) {
        final req = _outgoingRequests[index];
        return _buildRequestTile(req, isIncoming: false);
      },
    );
  }

  Widget _buildConnectionList() {
    if (_connectionRequests.isEmpty) {
      return _buildEmptyState(TranslationService.translate(context, 'no_pending_connections'));
    }
    return ListView.builder(
      itemCount: _connectionRequests.length,
      itemBuilder: (context, index) {
        final req = _connectionRequests[index];
        return Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                backgroundColor: Colors.purple.withOpacity(0.1),
                child: const Icon(Icons.link, color: Colors.purple),
              ),
              title: Text(
                req['name'] ?? TranslationService.translate(context, 'unknown_library'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(req['url'] ?? ''),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => _updatePeerStatus(req['id'], 'active'),
                    child: Text(TranslationService.translate(context, 'btn_accept')),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: () => _updatePeerStatus(req['id'], 'rejected'),
                    child: Text(TranslationService.translate(context, 'btn_reject')),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: 72),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTile(Map<String, dynamic> req, {required bool isIncoming}) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: isIncoming ? Colors.orange.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
            child: Icon(
              isIncoming ? Icons.download : Icons.upload,
              color: isIncoming ? Colors.orange : Colors.blue,
              size: 20,
            ),
          ),
          title: Text(
            req['book_title'] ?? TranslationService.translate(context, 'unknown_book'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isIncoming ? "${TranslationService.translate(context, 'from')}: ${req['peer_name']}" : "${TranslationService.translate(context, 'to')}: ${req['peer_name']}"),
              const SizedBox(height: 4),
              _buildStatusText(req['status']),
            ],
          ),
          trailing: _buildActionButtons(req, isIncoming: isIncoming),
        ),
        const Divider(height: 1, indent: 72),
      ],
    );
  }

  Widget _buildStatusText(String status) {
    Color color;
    switch (status) {
      case 'pending': color = Colors.orange; break;
      case 'accepted': color = Colors.green; break;
      case 'rejected': color = Colors.red; break;
      case 'returned': color = Colors.blue; break;
      default: color = Colors.grey;
    }
    return Text(
      status.toUpperCase(),
      style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
    );
  }


  Widget _buildActionButtons(Map<String, dynamic> req, {required bool isIncoming}) {
    final status = req['status'];
    final id = req['id'];

    if (isIncoming) {
      if (status == 'pending') {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 16),
              label: Text(TranslationService.translate(context, 'btn_accept')),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _updateStatus(id, 'accepted'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.close, size: 16),
              label: Text(TranslationService.translate(context, 'btn_reject')),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
              onPressed: () => _updateStatus(id, 'rejected'),
            ),
          ],
        );
      } else if (status == 'accepted') {
        return ElevatedButton.icon(
          icon: const Icon(Icons.assignment_return, size: 16),
          label: Text(TranslationService.translate(context, 'btn_mark_returned')),
          onPressed: () => _updateStatus(id, 'returned'),
        );
      }
    } else {
      // Outgoing
      if (status == 'pending') {
        return OutlinedButton.icon(
          icon: const Icon(Icons.cancel, size: 16),
          label: Text(TranslationService.translate(context, 'btn_cancel_request')),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => _deleteRequest(id, isOutgoing: true),
        );
      }
    }

    // Allow deleting finished/rejected requests to clean up list
    if (['rejected', 'returned', 'cancelled'].contains(status)) {
       return TextButton.icon(
        icon: const Icon(Icons.delete_outline, size: 16),
        label: Text(TranslationService.translate(context, 'btn_remove')),
        style: TextButton.styleFrom(foregroundColor: Colors.grey),
        onPressed: () => _deleteRequest(id, isOutgoing: !isIncoming),
      );
    }

    return const SizedBox.shrink();
  }
}
