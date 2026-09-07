import 'package:flutter/material.dart';
import '../../core/services/contact_service.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _channelController = TextEditingController();
  String _type = 'general';
  bool _sending = false;

  @override
  void dispose() {
    _messageController.dispose();
    _channelController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      await ContactService.sendMessage(
        type: _type,
        message: _messageController.text,
        channelInfo: _type == 'broken_link' ? _channelController.text : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال رسالتك، شكراً لك')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال الرسالة، تحقق من الإنترنت وحاول مرة أخرى')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تواصل معنا')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('نوع الرسالة', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'general', label: Text('استفسار عام')),
                ButtonSegment(value: 'broken_link', label: Text('رابط معطوب')),
              ],
              selected: {_type},
              onSelectionChanged: (selection) => setState(() => _type = selection.first),
            ),
            const SizedBox(height: 20),
            if (_type == 'broken_link') ...[
              TextFormField(
                controller: _channelController,
                decoration: const InputDecoration(
                  labelText: 'اسم القناة أو القسم المتعلق (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _messageController,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: _type == 'broken_link' ? 'صف المشكلة بالتفصيل' : 'رسالتك',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if (value == null || value.trim().length < 5) {
                  return 'اكتب رسالة لا تقل عن 5 أحرف';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _sending ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('إرسال'),
            ),
          ],
        ),
      ),
    );
  }
}
