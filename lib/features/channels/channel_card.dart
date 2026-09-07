import 'package:flutter/material.dart';
import '../../core/models/channel_model.dart';
import '../../core/services/favorites_service.dart';
import '../../core/services/player_launcher.dart';

class ChannelCard extends StatelessWidget {
  final ChannelModel channel;
  const ChannelCard({super.key, required this.channel});

  Color _statusColor(BuildContext context) {
    switch (channel.status) {
      case 'live':
        return Colors.redAccent;
      case 'upcoming':
        return Colors.amber;
      case 'disabled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel() {
    switch (channel.status) {
      case 'live':
        return 'مباشر الآن';
      case 'upcoming':
        return 'قريباً';
      case 'disabled':
        return 'معطّلة';
      default:
        return 'انتهى';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: channel.status == 'disabled'
            ? () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('هذه القناة متوقفة مؤقتاً.')),
                )
            : () => PlayerLauncher.openChannel(context, channel.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                    ? Image.network(
                        channel.logoUrl!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _fallbackLogo(theme),
                      )
                    : _fallbackLogo(theme),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(channel.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(channel.subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(context).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(),
                        style: TextStyle(
                          color: _statusColor(context),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<Set<String>>(
                valueListenable: FavoritesService.favorites,
                builder: (context, favoriteIds, _) {
                  final isFavorite = favoriteIds.contains(channel.id);
                  return IconButton(
                    icon: Icon(
                      isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: isFavorite ? Colors.redAccent : Colors.grey,
                    ),
                    tooltip: isFavorite ? 'إزالة من المفضلة' : 'إضافة للمفضلة',
                    onPressed: () => FavoritesService.toggleFavorite(channel.id),
                  );
                },
              ),
              const Icon(Icons.play_circle_fill, size: 34),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackLogo(ThemeData theme) {
    return Container(
      width: 64,
      height: 64,
      color: theme.colorScheme.primary.withOpacity(0.15),
      child: Icon(Icons.sports_soccer, color: theme.colorScheme.primary),
    );
  }
}
