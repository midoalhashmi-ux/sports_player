import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../core/services/app_settings_service.dart';
import '../features/contact/contact_screen.dart';
import '../features/legal/legal_screen.dart';

/// القائمة الجانبية للشاشة الرئيسية. تُبنى تدريجياً — كل بند جديد من
/// القسم 3 (مشاركة، تواصل معنا، الشروط، الخصوصية) يُضاف هنا.
class AppDrawer extends StatelessWidget {
  final VoidCallback? onClose;

  const AppDrawer({super.key, this.onClose});

  Future<void> _shareApp(BuildContext context) async {
    final settings = await AppSettingsService.fetchSettings();
    final link = settings.appStoreUrl.trim();
    final text = link.isNotEmpty
        ? '${settings.shareMessage}\n$link'
        : settings.shareMessage;
    await Share.share(text);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  'BinSheikh',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('مشاركة التطبيق'),
              onTap: () {
                onClose?.call();
                _shareApp(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent),
              title: const Text('تواصل معنا'),
              onTap: () {
                onClose?.call();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ContactScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('الشروط والأحكام'),
              onTap: () {
                onClose?.call();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LegalScreen(
                      field: 'terms',
                      title: 'الشروط والأحكام',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('سياسة الخصوصية'),
              onTap: () {
                onClose?.call();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LegalScreen(
                      field: 'privacy',
                      title: 'سياسة الخصوصية',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
