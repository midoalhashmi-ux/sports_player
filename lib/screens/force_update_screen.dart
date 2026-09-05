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
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update_alt_rounded,
                      color: Colors.white, size: 64),
                  const SizedBox(height: 24),
                  const Text(
                    'يوجد تحديث جديد',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الإصدار الحالي من التطبيق قديم ولا يمكن الاستمرار به.\n'
                    'يرجى تحميل آخر تحديث للمتابعة.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _openUpdateUrl(context),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('تحميل التحديث'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
