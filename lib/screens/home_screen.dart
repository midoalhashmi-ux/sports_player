import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ad_service.dart';
import '../services/saved_link_service.dart';
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

  BannerAd? _bannerAd;
  bool _bannerFailed = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadStoreUrl();
    _loadPremiumSettings();
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

  void _play(SavedLink link) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchScreen(
          externalUrl: link.url,
          externalUserAgent: link.userAgent,
        ),
      ),
    );
  }

  Future<void> _delete(SavedLink link) async {
    await SavedLinkService.delete(link.id);
    _reload();
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
      drawer: _buildDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddUrl,
        icon: const Icon(Icons.add),
        label: const Text('إضافة رابط'),
      ),
      body: Column(
        children: [
          // زر الاشتراك المميز — مخفي بالكامل ما لم يُفعَّل صراحةً من
          // لوحة التحكم (راجع _loadPremiumSettings). لا يحجز أي مساحة
          // ولا يظهر بشكل معطّل عند الإخفاء.
          if (_premiumEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openPremium,
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: Text(_premiumButtonText),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الروابط المحفوظة',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _links.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.live_tv_outlined,
                                size: 48, color: Colors.white38),
                            const SizedBox(height: 12),
                            const Text(
                              'لا توجد روابط محفوظة',
                              style:
                                  TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'اضغط "إضافة رابط" لإضافة رابط بث أو أي مصدر تشغيله',
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: Colors.white38, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: _openAddUrl,
                              icon: const Icon(Icons.add_link),
                              label: const Text('إضافة رابط الآن'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _links.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final link = _links[index];
                          return Card(
                            child: ListTile(
                              title: Text(link.title),
                              subtitle: Text(
                                link.url,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _play(link),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(link),
                              ),
                            ),
                          );
                        },
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

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.live_tv, size: 40, color: Colors.white),
                  SizedBox(height: 8),
                  Text('BinSheikh Player',
                      style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('اتصل بنا'),
              onTap: () {
                Navigator.of(context).pop();
                _openContact();
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('مشاركة التطبيق'),
              onTap: () {
                Navigator.of(context).pop();
                _shareApp();
              },
            ),
            ListTile(
              leading: const Icon(Icons.star_outline),
              title: const Text('قيّم التطبيق'),
              onTap: () {
                Navigator.of(context).pop();
                _rateApp();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('الشروط والخصوصية'),
              onTap: () {
                Navigator.of(context).pop();
                _openTermsPrivacy();
              },
            ),
          ],
        ),
      ),
    );
  }
}
