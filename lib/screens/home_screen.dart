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

  BannerAd? _bannerAd;
  bool _bannerFailed = false;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadStoreUrl();
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
      final url = snapshot.data()?['storeUrl'] as String?;
      if (url != null && url.isNotEmpty && mounted) {
        setState(() => _storeUrl = url);
      }
    } catch (_) {
      // نبقي على الرابط الاحتياطي
    }
  }

  void _loadBanner() {
    if (!AdService.instance.adsEnabled) return;
    final ad = AdService.instance.createBannerAd(
      onLoadFailed: () {
        if (mounted) setState(() => _bannerFailed = true);
      },
    );
    _bannerAd = ad;
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
      ),
      drawer: _buildDrawer(),
      body: Column(
        children: [
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
                    ? const Center(
                        child: Text(
                          'لا توجد روابط محفوظة',
                          style: TextStyle(color: Colors.white54, fontSize: 16),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddUrl,
        child: const Icon(Icons.add),
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
