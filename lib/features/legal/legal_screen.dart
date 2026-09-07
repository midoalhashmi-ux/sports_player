import 'package:flutter/material.dart';
import '../../core/services/legal_service.dart';

/// شاشة عامة تعرض نصاً ثابتاً من Firestore (settings/legal).
/// تُستخدم لكل من "الشروط والأحكام" و"سياسة الخصوصية" عبر تمرير
/// [field] المناسب ('terms' أو 'privacy') و[title] المعروض بالأعلى.
class LegalScreen extends StatefulWidget {
  final String field;
  final String title;

  const LegalScreen({super.key, required this.field, required this.title});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late final Future<String> _textFuture;

  @override
  void initState() {
    super.initState();
    _textFuture = LegalService.fetchText(widget.field);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: _textFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snapshot.data ?? '',
              style: const TextStyle(height: 1.6, fontSize: 15),
            ),
          );
        },
      ),
    );
  }
}
