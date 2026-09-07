import 'package:cloud_firestore/cloud_firestore.dart';

class ChannelModel {
  final String id;
  final String categoryId;
  final String title;
  final String subtitle;
  final String status;
  final DateTime? startTime;
  final String? logoUrl;
  final String? playerChannelKey;
  final String contentType;
  final String? posterUrl;
  final int? releaseYear;
  final String? genre;
  final bool isFeatured;
  final bool isPremium;
  final String? seriesId;
  final int? seasonNumber;
  final int? episodeNumber;

  ChannelModel({
    required this.id,
    required this.categoryId,
    required this.title,
    required this.subtitle,
    required this.status,
    this.startTime,
    this.logoUrl,
    this.playerChannelKey,
    this.contentType = 'channel',
    this.posterUrl,
    this.releaseYear,
    this.genre,
    this.isFeatured = false,
    this.isPremium = false,
    this.seriesId,
    this.seasonNumber,
    this.episodeNumber,
  });

  factory ChannelModel.fromMap(String id, Map<String, dynamic> map) {
    final rawStartTime = map['startTime'];
    final parsedStartTime = rawStartTime is DateTime
        ? rawStartTime
        : rawStartTime is Timestamp
            ? rawStartTime.toDate()
            : rawStartTime is String
                ? DateTime.tryParse(rawStartTime)
                : null;
    return ChannelModel(
      id: id,
      categoryId: map['categoryId'] ?? '',
      title: map['title'] ?? '',
      subtitle: map['subtitle'] ?? '',
      status: map['status'] ?? 'upcoming',
      startTime: parsedStartTime,
      logoUrl: map['logoUrl'],
      playerChannelKey: map['playerChannelKey'],
      contentType: (map['contentType'] ?? 'channel').toString(),
      posterUrl: (map['posterUrl'] as String?)?.trim(),
      releaseYear: _toInt(map['releaseYear']),
      genre: (map['genre'] as String?)?.trim(),
      isFeatured: map['isFeatured'] == true,
      isPremium: map['isPremium'] == true,
      seriesId: (map['seriesId'] as String?)?.trim(),
      seasonNumber: _toInt(map['seasonNumber']),
      episodeNumber: _toInt(map['episodeNumber']),
    );
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}
