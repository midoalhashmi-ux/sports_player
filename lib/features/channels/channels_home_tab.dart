import 'package:flutter/material.dart';
import '../../core/services/content_service.dart';
import 'channels_screen.dart';

/// تبويب "القنوات": شبكة الأقسام الرئيسية. الضغط على أي قسم يفتح
/// [ChannelsScreen] التي تتفرّع تلقائياً لأقسام فرعية أو قائمة قنوات.
class ChannelsHomeTab extends StatelessWidget {
  const ChannelsHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: ContentService.watchRootCategories(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
              child: Text('تعذر تحميل الأقسام. تحقق من اتصال الإنترنت وقواعد Firebase.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final categories = snapshot.data!;
        if (categories.isEmpty) return const Center(child: Text('لا توجد أقسام بعد'));
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: categories.length,
          itemBuilder: (context, index) {
            final category = categories[index];
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChannelsScreen(category: category)),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (category.iconUrl?.isNotEmpty == true)
                      Image.network(category.iconUrl!,
                          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback(context))
                    else
                      _fallback(context),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.all(10),
                        child: Text(category.title,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _fallback(BuildContext context) => Container(
        color: Theme.of(context).colorScheme.primary.withOpacity(.18),
        child: Icon(Icons.sports_soccer, size: 42, color: Theme.of(context).colorScheme.primary),
      );
}
