import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ad_service.dart';
import '../services/saved_link_service.dart';
import '../services/session_log_service.dart';
import '../theme/app_theme.dart';
import 'add_url_screen.dart';
import 'contact_screen.dart';
import 'terms_privacy_screen.dart';
import 'watch_screen.dart';

const _fallbackStoreUrl =
    'https://play.google.com/store/apps/details?id=com.midoalhashmi.zoltrastream';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<SavedLink> _links = [];
  bool _loading = true;
  String _storeUrl = _fallbackStoreUrl;

  // زر "الاشتراك المميز" — مخفي تماماً افتراضياً، ولا يظهر إلا لو فعّله
  // المطوّر من لوحة التحكم (settings/player.premiumEnabled) وعبّى رابطاً.
  // أي فشل بجلب الإعدادات يبقيه مخفياً (fail-safe)، بعكس رابط المتجر
  // الذي له قيمة احتياطية.
  bool _premiumEnabled = false;
  String _premiumUrl = '';
  String _premiumButtonText = 'الاشتراك المميز';

  // زر "تصدير سجل التشخيص" — مخفي تماماً افتراضياً، ولا يظهر إلا لو فعّله
  // المطوّر من لوحة التحكم (settings/player.diagnosticLogEnabled — نفس
  // الحقل الذي تكتبه لوحة التحكم فعلياً، راجع AHMED-dashboard/app.js).
  bool _debugLogButtonEnabled = false;

  BannerAd? _bannerAd;
  bool _bannerFailed = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadStoreUrl();
    _loadPremiumSettings();
    _loadDebugLogSetting();
    // تهيئة خدمة الإعلانات هنا (بدل main.dart المحمي) — آمنة الاستدعاء
    // أكثر من مرة، وتضمن أن الإعلان البيني يكون جاهزاً غالباً قبل ما
    // يفتح المستخدم أول قناة.
    AdService.instance.initialize().then((_) {
      if (mounted) _loadBanner();
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final links = await SavedLinkService.loadAll();
    if (!mounted) return;
    setState(() {
      _links = links;
      _loading = false;
    });
  }

  Future<void> _loadStoreUrl() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .get();
      final data = snapshot.data();
      final url = data?['storeUrl'] as String?;
      if (mounted) {
        setState(() {
          if (url != null && url.isNotEmpty) _storeUrl = url;
        });
      }
    } catch (_) {
      // نبقي على القيم الاحتياطية
    }
  }

  Future<void> _loadPremiumSettings() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      final data = snapshot.data();
      final enabled = data?['premiumEnabled'] == true;
      final url = (data?['premiumUrl'] as String?)?.trim() ?? '';
      final text = (data?['premiumButtonText'] as String?)?.trim() ?? '';
      if (mounted) {
        setState(() {
          // يظهر فقط لو التفعيل صريح ورابط فعلي موجود، وإلا يبقى مخفياً.
          _premiumEnabled = enabled && url.isNotEmpty;
          _premiumUrl = url;
          if (text.isNotEmpty) _premiumButtonText = text;
        });
      }
    } catch (_) {
      // أي خطأ (بدون إنترنت مثلاً) يبقي الزر مخفياً افتراضياً.
    }
  }

  Future<void> _openPremium() async {
    final uri = Uri.tryParse(_premiumUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _loadDebugLogSetting() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('player')
          .get();
      final enabled = snapshot.data()?['diagnosticLogEnabled'] == true;
      if (mounted) {
        setState(() => _debugLogButtonEnabled = enabled);
      }
    } catch (_) {
      // أي خطأ (بدون إنترنت مثلاً) يبقي الزر مخفياً افتراضياً.
    }
  }

  Future<void> _exportDebugLog() async {
    final file = await SessionLogService.instance.exportAsTxt();
    if (!mounted) return;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد سجل تشخيص بعد — شغّل قناة أولاً ثم أعد المحاولة')),
      );
      return;
    }
    await Share.shareXFiles([XFile(file.path)], text: 'سجل تشخيص BinSheikh Player');
  }

  void _loadBanner() {
    if (!AdService.instance.adsEnabled) return;
    // مهم: لا نُسند البانر إلى _bannerAd فور إنشائه (كان الخطأ سابقاً) —
    // في تلك اللحظة لا يزال التحميل جارياً ولم يجهز بعد، وبدون setState
    // لم تكن الواجهة تُعاد بناؤها إطلاقاً فلا يظهر البانر حتى لو نجح
    // تحميله. الآن ننتظر onAdLoaded فعلياً قبل عرضه.
    AdService.instance.createBannerAd(
      onAdLoaded: (ad) {
        if (!mounted) {
          ad.dispose();
          return;
        }
        setState(() => _bannerAd = ad);
      },
      onLoadFailed: () {
        if (mounted) setState(() => _bannerFailed = true);
      },
    );
  }

  Future<void> _openAddUrl() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddUrlScreen()),
    );
    if (added == true) _reload();
  }

  Future<void> _openEditUrl(SavedLink link) async {
    final edited = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddUrlScreen(existingLink: link)),
    );
    if (edited == true) _reload();
  }

  void _play(SavedLink link) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchScreen(
          externalUrl: link.url,
          externalUserAgent: link.userAgent,
          title: link.title,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(SavedLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف الرابط؟'),
        content: Text('راح يُحذف "${link.title}" نهائياً من قائمتك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SavedLinkService.delete(link.id);
      _reload();
    }
  }

  void _openContact() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ContactScreen()),
    );
  }

  void _openTermsPrivacy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TermsPrivacyScreen()),
    );
  }

  void _shareApp() {
    Share.share('جرّب BinSheikh Player:\n$_storeUrl');
  }

  Future<void> _rateApp() async {
    final uri = Uri.parse(_storeUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BinSheikh Player'),
        actions: [
          IconButton(
            tooltip: 'إضافة رابط بث',
            icon: const Icon(Icons.add_link),
            onPressed: _openAddUrl,
          ),
        ],
      ),
      drawer: _buildDrawer(accent),
      floatingActionButton: Padding(
        // نرفع الزر بارتفاع البانر (إن وُجد) حتى لا يظهر فوق جزء منه.
        padding: EdgeInsets.only(
          bottom: (_bannerAd != null && !_bannerFailed)
              ? _bannerAd!.size.height.toDouble()
              : 0,
        ),
        child: FloatingActionButton.extended(
          onPressed: _openAddUrl,
          icon: const Icon(Icons.add),
          label: const Text('إضافة رابط'),
        ),
      ),
      body: Column(
        children: [
          // زر الاشتراك المميز — مخفي بالكامل ما لم يُفعَّل صراحةً من
          // لوحة التحكم (راجع _loadPremiumSettings). لا يحجز أي مساحة
          // ولا يظهر بشكل معطّل عند الإخفاء.
          if (_premiumEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openPremium,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: Text(_premiumButtonText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(
              children: [
                Text(
                  'الروابط المحفوظة',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                if (_links.isNotEmpty)
                  Text(
                    '${_links.length}',
                    style: const TextStyle(
                      color: AppTheme.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _links.isEmpty
                    ? _buildEmptyState(accent)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: _links.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) => _LinkCard(
                          link: _links[index],
                          accent: accent,
                          onTap: () => _play(_links[index]),
                          onEdit: () => _openEditUrl(_links[index]),
                          onDelete: () => _confirmDelete(_links[index]),
                        ),
                      ),
          ),
          // بانر الإعلانات — في الشاشة الرئيسية فقط، لا يظهر إطلاقاً في
          // شاشة المشاهدة.
          if (_bannerAd != null && !_bannerFailed)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color accent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.live_tv_outlined, size: 40, color: accent),
            ),
            const SizedBox(height: 20),
            const Text(
              'لا توجد روابط محفوظة بعد',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'أضف رابط بث أو أي مصدر فيديو لتشغيله من هنا مباشرة',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.onSurfaceMuted, height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _openAddUrl,
              icon: const Icon(Icons.add_link),
              label: const Text('إضافة رابط الآن'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(Color accent) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.live_tv, color: accent, size: 28),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'BinSheikh Player',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerItem(
                    icon: Icons.mail_outline,
                    label: 'اتصل بنا',
                    onTap: () {
                      Navigator.of(context).pop();
                      _openContact();
                    },
                  ),
                  _drawerItem(
                    icon: Icons.share_outlined,
                    label: 'مشاركة التطبيق',
                    onTap: () {
                      Navigator.of(context).pop();
                      _shareApp();
                    },
                  ),
                  _drawerItem(
                    icon: Icons.star_outline,
                    label: 'قيّم التطبيق',
                    onTap: () {
                      Navigator.of(context).pop();
                      _rateApp();
                    },
                  ),
                  const Divider(height: 24),
                  _drawerItem(
                    icon: Icons.description_outlined,
                    label: 'الشروط والخصوصية',
                    onTap: () {
                      Navigator.of(context).pop();
                      _openTermsPrivacy();
                    },
                  ),
                  // مخفي تماماً ما لم يُفعَّل صراحةً من لوحة التحكم — أداة
                  // تشخيص داخلية، ليست ميزة للمستخدم العادي.
                  if (_debugLogButtonEnabled)
                    _drawerItem(
                      icon: Icons.bug_report_outlined,
                      label: 'تصدير سجل التشخيص',
                      onTap: () {
                        Navigator.of(context).pop();
                        _exportDebugLog();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
    );
  }
}

class _LinkCard extends StatelessWidget {
  final SavedLink link;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _LinkCard({
    required this.link,
    required this.accent,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.play_arrow_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      link.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      link.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'تعديل',
                icon: const Icon(Icons.edit_outlined, size: 21),
                onPressed: onEdit,
              ),
              IconButton(
                tooltip: 'حذف',
                icon: const Icon(Icons.delete_outline, size: 21),
                color: Colors.redAccent,
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
