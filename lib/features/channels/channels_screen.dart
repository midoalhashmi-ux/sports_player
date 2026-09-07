import 'package:flutter/material.dart';
import '../../core/models/category_model.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';
import 'channel_card.dart';

class ChannelsScreen extends StatelessWidget {
  final CategoryModel category;
  const ChannelsScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(category.title)),
      body: StreamBuilder<List<CategoryModel>>(
        stream: ContentService.watchChildCategories(category.id),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('تعذر تحميل الأقسام الفرعية.\nتحقق من اتصال الإنترنت.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final childCategories = snapshot.data!;
          if (childCategories.isNotEmpty) {
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: childCategories.length,
              itemBuilder: (context, index) {
                final child = childCategories[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  child: InkWell(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChannelsScreen(category: child),
                      ),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (child.iconUrl != null && child.iconUrl!.isNotEmpty)
                          Image.network(
                            child.iconUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withOpacity(0.15),
                            ),
                          )
                        else
                          Container(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.15),
                          ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            color: Colors.black54,
                            child: Text(
                              child.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }
          return _ChannelsList(categoryId: category.id);
        },
      ),
    );
  }
}

class _ChannelsList extends StatelessWidget {
  final String categoryId;
  const _ChannelsList({required this.categoryId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ChannelModel>>(
      stream: ContentService.watchChannelsForCategory(categoryId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_off, size: 42),
                  const SizedBox(height: 10),
                  const Text(
                    'تعذر تحميل القنوات.\nتحقق من اتصال الإنترنت وحاول مرة أخرى.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => ChannelsScreen(
                          category: CategoryModel(
                            id: categoryId,
                            parentId: null,
                            title: 'القنوات',
                            iconUrl: null,
                            order: 0,
                          ),
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final channels = snapshot.data!;
        if (channels.isEmpty) {
          return const Center(child: Text('لا توجد قنوات بعد في هذا القسم'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: channels.length,
          itemBuilder: (context, index) => ChannelCard(channel: channels[index]),
        );
      },
    );
  }
}
