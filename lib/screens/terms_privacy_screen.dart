import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class TermsPrivacyScreen extends StatefulWidget {
  const TermsPrivacyScreen({super.key});

  @override
  State<TermsPrivacyScreen> createState() => _TermsPrivacyScreenState();
}

class _TermsPrivacyScreenState extends State<TermsPrivacyScreen> {
  bool _loading = true;
  String _terms = '';
  String _privacy = '';

  static const _fallbackTerms =
      'باستخدامك هذا التطبيق فإنك توافق على استخدامه فقط للأغراض المشروعة '
      'ووفق حقوق البث المرخّصة المتاحة داخل التطبيق.';
  static const _fallbackPrivacy =
      'لا نقوم بجمع بيانات شخصية حساسة. تُستخدم بيانات الاستخدام الأساسية '
      'فقط لتحسين أداء التطبيق واستقرار البث.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('settings')
          .doc('legal')
          .get();
      final data = snapshot.data();
      _terms = (data?['terms'] as String?)?.trim() ?? '';
      _privacy = (data?['privacy'] as String?)?.trim() ?? '';
    } catch (_) {
      // تعذر الجلب — سنعرض النص الاحتياطي
    }
    if (_terms.isEmpty) _terms = _fallbackTerms;
    if (_privacy.isEmpty) _privacy = _fallbackPrivacy;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الشروط والخصوصية'),
          bottom: const TabBar(tabs: [
            Tab(text: 'الشروط والأحكام'),
            Tab(text: 'سياسة الخصوصية'),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildTextTab(_terms),
                  _buildTextTab(_privacy),
                ],
              ),
      ),
    );
  }

  Widget _buildTextTab(String text) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white70, height: 1.6),
      ),
    );
  }
}
