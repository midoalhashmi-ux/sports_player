import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/version_check_service.dart';

/// شاشة تحديث إجباري — تُعرض بدل التطبيق بالكامل عندما يكون الإصدار
/// المثبَّت أقل من الحد الأدنى المضبوط من لوحة التحكم (settings/player ->
/// minVersion). لا يوجد أي طريق للخروج منها غير زر التحميل: ممنوعة
/// إيماءة/زر الرجوع (PopScope) وليس فيها AppBar ولا أي عنصر تنقّل آخر.
class ForceUpdateScreen extends StatelessWidget {
  final ForceUpdateInfo info;
  const ForceUpdateScreen({super.key, required this.info});

  Future<void> _openUpdateUrl(BuildContext context) async {
    final uri = Uri.tryParse(info.updateUrl);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح رابط التحديث.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.system_update_alt_rounded,
                        color: accent, size: 46),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'يوجد تحديث جديد',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'الإصدار الحالي من التطبيق قديم ولا يمكن الاستمرار به.\n'
                    'يرجى تحميل آخر تحديث للمتابعة.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 15, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () => _openUpdateUrl(context),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('تحميل التحديث'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
