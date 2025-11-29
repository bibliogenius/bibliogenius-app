import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../services/api_service.dart';

class BorrowRequestsScreen extends StatefulWidget {
  const BorrowRequestsScreen({super.key});

  @override
  State<BorrowRequestsScreen> createState() => _BorrowRequestsScreenState();
}

class _BorrowRequestsScreenState extends State<BorrowRequestsScreen>
    with SingleTickerProviderStateMixin {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      if (mounted) {
        setState(() {
          _incomingRequests = inRes.data;
          _outgoingRequests = outRes.data;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error fetching requests: $e")),
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
          SnackBar(content: Text("Error updating status: $e")),
        );
      }
    }
  }

  Future<void> _deleteRequest(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Request'),
        content: const Text('Are you sure you want to delete this request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.deleteRequest(id);
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
      appBar: AppBar(
        title: const Text("Borrow Requests"),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: "Incoming"), Tab(text: "Outgoing")],
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
              ],
            ),
    );
  }

  Widget _buildIncomingList() {
    if (_incomingRequests.isEmpty) {
      return const Center(child: Text("No incoming requests"));
    }
    return ListView.builder(
      itemCount: _incomingRequests.length,
      itemBuilder: (context, index) {
        final req = _incomingRequests[index];
        return Card(
          child: ListTile(
            title: Text(req['book_title']),
            subtitle: Text("From: ${req['peer_name']}\nStatus: ${req['status']}"),
            trailing: _buildActionButtons(req, isIncoming: true),
          ),
        );
      },
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
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: () => _updateStatus(id, 'accepted'),
              tooltip: 'Accept',
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => _updateStatus(id, 'rejected'),
              tooltip: 'Reject',
            ),
          ],
        );
      } else if (status == 'accepted') {
        return ElevatedButton(
          onPressed: () => _updateStatus(id, 'returned'),
          child: const Text("Mark Returned"),
        );
      }
    } else {
      // Outgoing
      if (status == 'pending') {
        return TextButton(
          onPressed: () => _deleteRequest(id),
          child: const Text("Cancel", style: TextStyle(color: Colors.red)),
        );
      }
    }

    // Allow deleting finished/rejected requests to clean up list
    if (['rejected', 'returned', 'cancelled'].contains(status)) {
       return IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.grey),
        onPressed: () => _deleteRequest(id),
        tooltip: 'Remove from list',
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildOutgoingList() {
    if (_outgoingRequests.isEmpty) {
      return const Center(child: Text("No outgoing requests"));
    }
    return ListView.builder(
      itemCount: _outgoingRequests.length,
      itemBuilder: (context, index) {
        final req = _outgoingRequests[index];
        return Card(
          child: ListTile(
            title: Text(req['book_title']),
            subtitle: Text("To: ${req['peer_name']}\nStatus: ${req['status']}"),
            trailing: _buildActionButtons(req, isIncoming: false),
          ),
        );
      },
    );
  }
}
