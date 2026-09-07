import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/app_update_service.dart';
import '../../core/services/app_settings_service.dart';

class AppUpdateDialog extends StatelessWidget {
  final AppUpdateInfo info;
  final VoidCallback? onUpdate;
  final VoidCallback? onDismiss;

  const AppUpdateDialog({
    super.key,
    required this.info,
    this.onUpdate,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final message = info.message?.trim().isNotEmpty == true
        ? info.message!
        : 'يتوفر تحديث جديد للتطبيق.';

    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.system_update, size: 36),
        title: const Text('تحديث متوفر'),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          if (onDismiss != null)
            TextButton(onPressed: onDismiss, child: const Text('لاحقاً')),
          if (onUpdate != null)
            FilledButton.icon(
              onPressed: onUpdate,
              icon: const Icon(Icons.download),
              label: const Text('تحديث الآن'),
            ),
        ],
      ),
    );
  }
}
