import 'package:flutter/material.dart';

import '../../core/models/channel_model.dart';
import '../../core/models/player_settings.dart';
import '../../core/services/player_service.dart';

Future<void> openExternalPlayerSheet(
  BuildContext context,
  ChannelModel channel,
  PlayerSettings settings,
) async {
  final opened = await PlayerService.openChannel(
    channelId: channel.id,
    settings: settings,
  );
  if (opened || !context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_circle_outline, size: 54),
          const SizedBox(height: 14),
          Text('تطبيق المشغل غير جاهز',
              style: Theme.of(sheetContext).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'تحتاج هذه القناة إلى تطبيق المشغل المنفصل. بعد تثبيته سيتم فتح القناة مباشرة من هنا.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          if (settings.storeUrl != null && settings.storeUrl!.isNotEmpty)
            FilledButton.icon(
              onPressed: () => PlayerService.openStore(settings),
              icon: const Icon(Icons.download),
              label: const Text('تثبيت تطبيق المشغل'),
            ),
        ],
      ),
    ),
  );
}
