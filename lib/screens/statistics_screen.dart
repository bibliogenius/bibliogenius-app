import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../widgets/genie_app_bar.dart';

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  List<Book> _books = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final res = await api.getBooks();
      if (res.statusCode == 200) {
        final List<dynamic> data = res.data['books'];
        setState(() {
          _books = data.map((json) => Book.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GenieAppBar(
        title: "Library Insights",
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
              ? const Center(child: Text("No books to analyze yet!"))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Reading Habits"),
                      const SizedBox(height: 16),
                      _buildStatusPieChart(),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Top Authors"),
                      const SizedBox(height: 16),
                      _buildTopAuthorsChart(),
                      const SizedBox(height: 32),
                      _buildSectionTitle("Publication Timeline"),
                      const SizedBox(height: 16),
                      _buildPublicationYearChart(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
    );
  }

  Widget _buildSummaryCards() {
    final totalBooks = _books.length;
    final readBooks = _books.where((b) => b.readingStatus == 'read').length;
    final borrowedBooks = _books.where((b) => b.readingStatus == 'borrowed').length;
    
    // Calculate unique authors
    final uniqueAuthors = _books
        .where((b) => b.author != null && b.author!.isNotEmpty)
        .map((b) => b.author!)
        .toSet()
        .length;
    
    // Calculate completion rate
    final completionRate = totalBooks > 0 
        ? (readBooks / totalBooks * 100).toStringAsFixed(1) 
        : '0.0';
    
    // Find oldest and newest books
    final booksWithYears = _books.where((b) => b.publicationYear != null && b.publicationYear! > 1800).toList();
    final oldestYear = booksWithYears.isEmpty ? null : booksWithYears.map((b) => b.publicationYear!).reduce((a, b) => a < b ? a : b);
    final avgYear = booksWithYears.isEmpty ? null : (booksWithYears.map((b) => b.publicationYear!).reduce((a, b) => a + b) / booksWithYears.length).round();

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard("Total Books", totalBooks.toString(), Icons.library_books, Colors.blue)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard("Read", readBooks.toString(), Icons.check_circle, Colors.green)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard("Borrowed", borrowedBooks.toString(), Icons.people, Colors.purple)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildStatCard("Unique Authors", uniqueAuthors.toString(), Icons.person_outline, Colors.orange)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard("Completion", "$completionRate%", Icons.trending_up, Colors.teal)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard("Oldest Book", oldestYear?.toString() ?? "N/A", Icons.history, Colors.brown)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildStatCard("Avg Year", avgYear?.toString() ?? "N/A", Icons.calendar_today, Colors.indigo)),
            const SizedBox(width: 16),
            Expanded(child: _buildStatCard("Books/Author", uniqueAuthors > 0 ? (totalBooks / uniqueAuthors).toStringAsFixed(1) : "0.0", Icons.auto_graph, Colors.pink)),
            const SizedBox(width: 16),
            const Expanded(child: SizedBox()), // Placeholder for symmetry
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPieChart() {
    final statusCounts = <String, int>{};
    for (var book in _books) {
      final status = book.readingStatus ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }

    final List<PieChartSectionData> sections = [];
    final colors = {
      'read': Colors.green,
      'reading': Colors.blue,
      'to_read': Colors.orange,
      'wanted': Colors.redAccent,
      'borrowed': Colors.purple,
      'unknown': Colors.grey,
    };

    statusCounts.forEach((status, count) {
      final color = colors[status] ?? Colors.grey;
      final percentage = (count / _books.length * 100).toStringAsFixed(1);
      sections.add(
        PieChartSectionData(
          color: color,
          value: count.toDouble(),
          title: '$percentage%',
          radius: 60,
          titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    });

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 40,
                sectionsSpace: 2,
              ),
            ),
          ),
          const SizedBox(width: 24),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: statusCounts.entries.map((e) {
              final color = colors[e.key] ?? Colors.grey;
              final label = e.key.replaceAll('_', ' ').toUpperCase();
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text('$label (${e.value})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTopAuthorsChart() {
    final authorCounts = <String, int>{};
    for (var book in _books) {
      if (book.author != null && book.author!.isNotEmpty) {
        authorCounts[book.author!] = (authorCounts[book.author!] ?? 0) + 1;
      }
    }

    var sortedAuthors = authorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    if (sortedAuthors.length > 5) {
      sortedAuthors = sortedAuthors.sublist(0, 5);
    }

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (sortedAuthors.isEmpty ? 0 : sortedAuthors.first.value).toDouble() + 1,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.blueGrey,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${sortedAuthors[groupIndex].key}\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: (rod.toY - 1).toInt().toString(),
                      style: const TextStyle(color: Colors.yellow),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value.toInt() >= sortedAuthors.length) return const SizedBox.shrink();
                  // Just show first letter or truncate to avoid overlap
                  final author = sortedAuthors[value.toInt()].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      author.length > 8 ? '${author.substring(0, 6)}...' : author,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
                reservedSize: 40,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: sortedAuthors.asMap().entries.map((e) {
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value.toDouble(),
                  color: Colors.indigoAccent,
                  width: 20,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildPublicationYearChart() {
    final yearCounts = <int, int>{};
    for (var book in _books) {
      if (book.publicationYear != null && book.publicationYear! > 1800) {
        // Group by decade? Or just raw if not too many. Let's group by decade.
        final decade = (book.publicationYear! ~/ 10) * 10;
        yearCounts[decade] = (yearCounts[decade] ?? 0) + 1;
      }
    }

    final sortedYears = yearCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedYears.isEmpty) return const Text("No publication year data.");

    return Container(
      height: 300,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  // Only show some labels
                  final index = value.toInt();
                  if (index >= 0 && index < sortedYears.length) {
                     return Padding(
                       padding: const EdgeInsets.only(top: 8.0),
                       child: Text(sortedYears[index].key.toString(), style: const TextStyle(fontSize: 10)),
                     );
                  }
                  return const SizedBox.shrink();
                },
                interval: 1, // Show all points? Might be crowded.
                reservedSize: 30,
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: sortedYears.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value.value.toDouble());
              }).toList(),
              isCurved: true,
              color: Colors.teal,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: Colors.teal.withOpacity(0.2)),
            ),
          ],
        ),
      ),
    );
  }
}
