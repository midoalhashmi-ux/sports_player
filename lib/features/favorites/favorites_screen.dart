import 'package:flutter/material.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/content_service.dart';
import '../../core/services/favorites_service.dart';
import '../channels/channel_card.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المفضلة')),
      body: ValueListenableBuilder<Set<String>>(
        valueListenable: FavoritesService.favorites,
        builder: (context, favoriteIds, _) {
          if (favoriteIds.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'لا توجد قنوات مفضلة بعد.\nاضغط أيقونة القلب بجانب أي قناة لإضافتها هنا.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return FutureBuilder<List<ChannelModel>>(
            future: ContentService.fetchChannelsByIds(favoriteIds.toList()),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final channels = snapshot.data!;
              if (channels.isEmpty) {
                return const Center(
                  child: Text('تعذر تحميل القنوات المفضلة، حاول لاحقاً'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: channels.length,
                itemBuilder: (context, index) =>
                    ChannelCard(channel: channels[index]),
              );
            },
          );
        },
      ),
    );
  }
}
