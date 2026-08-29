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

// كود وصول احتياطي لشاشة "إضافة رابط" (المطوّر فقط) لو ما ضُبط
// settings/app.devAccessCode من لوحة التحكم بعد. يُفضَّل ضبط كود
// حقيقي من لوحة التحكم وعدم الاعتماد على هذا الاحتياطي.
const _fallbackDevAccessCode = '112233';

class _HomeScreenState extends State<HomeScreen> {
  List<SavedLink> _links = [];
  bool _loading = true;
  String _storeUrl = _fallbackStoreUrl;
  String _devAccessCode = _fallbackDevAccessCode;

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
      final data = snapshot.data();
      final url = data?['storeUrl'] as String?;
      final devCode = data?['devAccessCode'] as String?;
      if (mounted) {
        setState(() {
          if (url != null && url.isNotEmpty) _storeUrl = url;
          if (devCode != null && devCode.isNotEmpty) _devAccessCode = devCode;
        });
      }
    } catch (_) {
      // نبقي على القيم الاحتياطية
    }
  }

  // شاشة "إضافة رابط" لم تعد ظاهرة كزر عادي (كانت خطراً نشرياً: تسمح لأي
  // مستخدم بتشغيل أي رابط بث خارجي داخل التطبيق، وليست ميزة تحتاجها
  // الغالبية). صارت مقيّدة بكود وصول للمطوّر فقط عبر ضغط طويل مخفي.
  Future<void> _requestAddUrlAccess() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('كود الوصول'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'أدخل الكود'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('دخول'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (controller.text.trim() != _devAccessCode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('كود غير صحيح.')),
      );
      return;
    }
    _openAddUrl();
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

  // زر تشخيص مؤقت — يعرض حالة تهيئة الإعلانات الحيّة (نجاح/فشل كل خطوة
  // مع رسالة الخطأ الحقيقية من Google لو فشلت) بدون حاجة لـ Logcat أو
  // أي أدوات مطوّر. يمكن حذفه لاحقاً بعد التأكد أن كل شيء يعمل.
  void _showAdsDiagnostics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تشخيص الإعلانات'),
        content: SingleChildScrollView(
          child: Text(
            AdService.instance.debugStatus,
            textAlign: TextAlign.right,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showAdsDiagnostics();
            },
            child: const Text('تحديث'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: _requestAddUrlAccess,
          child: const Text('BinSheikh Player'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'تشخيص الإعلانات',
            onPressed: _showAdsDiagnostics,
          ),
        ],
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
