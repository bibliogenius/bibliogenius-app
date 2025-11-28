import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/api_service.dart';
import '../widgets/status_badge.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userStatus;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  Future<void> _fetchStatus() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.getUserStatus();
      setState(() {
        _userStatus = response.data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _exportData() async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Preparing backup...')));

      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.exportData();

      final directory = await getTemporaryDirectory();
      final filename =
          'bibliogenius_backup_${DateTime.now().toIso8601String().split('T')[0]}.json';
      final file = File('${directory.path}/$filename');
      await file.writeAsBytes(response.data);

      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'My BiblioGenius Backup');
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_userStatus == null) return const Center(child: Text('No data'));

    final level = _userStatus!['level'] as String;
    final loansCount = _userStatus!['loans_count'] as int;
    final editsCount = _userStatus!['edits_count'] as int;
    final progress = (_userStatus!['next_level_progress'] as num).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 20),
          const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50)),
          const SizedBox(height: 16),
          Text('Librarian', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          StatusBadge(level: level, size: 32),
          const SizedBox(height: 32),

          // Progress Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Next Level Progress',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(progress * 100).toInt()}% to next level',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Stats Grid
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Loans',
                  loansCount.toString(),
                  Icons.book,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'Edits',
                  editsCount.toString(),
                  Icons.edit,
                  Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Data Management
          Text(
            'Data Management',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _exportData,
            icon: const Icon(Icons.download),
            label: const Text('Export Library Backup'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
