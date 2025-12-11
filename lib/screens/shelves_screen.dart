
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/tag.dart';
import '../services/api_service.dart';
import '../widgets/genie_app_bar.dart';
import '../services/translation_service.dart';

class ShelvesScreen extends StatefulWidget {
  const ShelvesScreen({super.key});

  @override
  State<ShelvesScreen> createState() => _ShelvesScreenState();
}

class _ShelvesScreenState extends State<ShelvesScreen> {
  late Future<List<Tag>> _tagsFuture;

  @override
  void initState() {
    super.initState();
    _tagsFuture = Provider.of<ApiService>(context, listen: false).getTags();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GenieAppBar(title: 'Shelves'), // "Bibliothèque" or "Étagères" localized? GenieAppBar handles title usually? No, title passed here.
      // We should verify if "Shelves" translation exists or use literal for now and let user know. 
      // Actually, previous task added 'tags' key. Let's use that or add 'shelves' later. 
      // For now, hardcode "Shelves" and add translation key later if needed.
       
      body: Container(
         decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/images/background.jpg'),
            fit: BoxFit.cover,
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: 0.7),
              BlendMode.darken,
            ),
          ),
        ),
        child: FutureBuilder<List<Tag>>(
          future: _tagsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.white)));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(child: Text('No shelves (tags) found.', style: TextStyle(color: Colors.white70)));
            }

            final tags = snapshot.data!;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 120, 16, 16), // Top padding for AppBar
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 2 columns
                  childAspectRatio: 1.5,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: tags.length,
                itemBuilder: (context, index) {
                  final tag = tags[index];
                  return _buildShelf(context, tag);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShelf(BuildContext context, Tag tag) {
    return Card(
      color: Colors.white.withValues(alpha: 0.1),
      elevation: 0,
       shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Navigate to BookListScreen with tag filter
          // We assume BookListScreen can take query params? 
          // Check GoRouter config first? 
          // Or just push named route with extra param?
          // Previous analysis said BookListScreen handles query params.
          context.go('/books?tag=${tag.name}');
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shelves, color: Colors.amber, size: 32),
              const SizedBox(height: 12),
              Text(
                tag.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${tag.count} books',
                 style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
