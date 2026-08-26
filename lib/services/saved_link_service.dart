import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedLink {
  final String id;
  final String title;
  final String url;
  final String? userAgent;

  const SavedLink({
    required this.id,
    required this.title,
    required this.url,
    this.userAgent,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'userAgent': userAgent,
      };

  factory SavedLink.fromJson(Map<String, dynamic> json) => SavedLink(
        id: json['id'] as String,
        title: json['title'] as String,
        url: json['url'] as String,
        userAgent: json['userAgent'] as String?,
      );
}

class SavedLinkService {
  static const _key = 'saved_links_v1';

  static Future<List<SavedLink>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    return raw
        .map((e) => SavedLink.fromJson(jsonDecode(e) as Map<String, dynamic>))
        .toList();
  }

  static Future<void> add(SavedLink link) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    raw.add(jsonEncode(link.toJson()));
    await prefs.setStringList(_key, raw);
  }

  static Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final kept = raw.where((e) {
      final map = jsonDecode(e) as Map<String, dynamic>;
      return map['id'] != id;
    }).toList();
    await prefs.setStringList(_key, kept);
  }
}
