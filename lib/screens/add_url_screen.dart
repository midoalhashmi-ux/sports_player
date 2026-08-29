import 'package:flutter/material.dart';

import '../services/saved_link_service.dart';

class AddUrlScreen extends StatefulWidget {
  const AddUrlScreen({super.key});

  @override
  State<AddUrlScreen> createState() => _AddUrlScreenState();
}

class _AddUrlScreenState extends State<AddUrlScreen> {
  final _titleController = TextEditingController();
  final _urlController = TextEditingController();
  final _userAgentController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _urlController.dispose();
    _userAgentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final url = _urlController.text.trim();
    if (title.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل العنوان والرابط.')),
      );
      return;
    }

    setState(() => _saving = true);
    await SavedLinkService.add(SavedLink(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      url: url,
      userAgent: _userAgentController.text.trim().isEmpty
          ? null
          : _userAgentController.text.trim(),
    ));
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إضافة رابط')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'العنوان'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'الرابط'),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _userAgentController,
              decoration: const InputDecoration(
                labelText: 'User Agent',
                helperText: 'اختياري',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('حفظ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
