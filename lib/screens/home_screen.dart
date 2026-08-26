import 'package:flutter/material.dart';

import '../services/saved_link_service.dart';
import 'add_url_screen.dart';
import 'watch_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedLink> _links = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final links = await SavedLinkService.loadAll();
    if (!mounted) return;
    setState(() {
      _links = links;
      _loading = false;
    });
  }

  Future<void> _openAddUrl() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddUrlScreen()),
    );
    if (added == true) _reload();
  }

  void _play(SavedLink link) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchScreen(
          externalUrl: link.url,
          externalUserAgent: link.userAgent,
        ),
      ),
    );
  }

  Future<void> _delete(SavedLink link) async {
    await SavedLinkService.delete(link.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مشغل البث الرياضي'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _links.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد روابط محفوظة',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _links.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final link = _links[index];
                    return Card(
                      child: ListTile(
                        title: Text(link.title),
                        subtitle: Text(
                          link.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _play(link),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(link),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddUrl,
        child: const Icon(Icons.add),
      ),
    );
  }
}
