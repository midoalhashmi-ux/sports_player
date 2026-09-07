/// إحصائيات فريق واحد بمباراة (استحواذ، تسديدات، ركنيات، بطاقات...).
class TeamStats {
  final String teamName;
  final Map<String, dynamic> valuesByType;

  TeamStats({required this.teamName, required this.valuesByType});

  factory TeamStats.fromJson(Map<String, dynamic> json) {
    final rawStats = (json['stats'] as List<dynamic>?) ?? [];
    final map = <String, dynamic>{};
    for (final entry in rawStats) {
      if (entry is Map<String, dynamic>) {
        final type = (entry['type'] ?? '').toString();
        if (type.isNotEmpty) map[type] = entry['value'];
      }
    }
    return TeamStats(
      teamName: (json['teamName'] ?? '').toString(),
      valuesByType: map,
    );
  }

  /// يرجّع قيمة إحصائية معينة كنص جاهز للعرض، أو '-' إن لم تتوفر.
  String display(String type) {
    final value = valuesByType[type];
    if (value == null) return '-';
    return value.toString();
  }
}

/// إحصائيات مباراة كاملة (فريقين).
class MatchStats {
  final TeamStats home;
  final TeamStats away;

  MatchStats({required this.home, required this.away});

  /// أنواع الإحصائيات المعروضة بالترتيب، مع تسميتها بالعربي.
  static const orderedTypes = <String, String>{
    'Ball Possession': 'الاستحواذ',
    'Total Shots': 'مجموع التسديدات',
    'Shots on Goal': 'تسديدات على المرمى',
    'Corner Kicks': 'الركنيات',
    'Fouls': 'الأخطاء',
    'Yellow Cards': 'بطاقات صفراء',
    'Red Cards': 'بطاقات حمراء',
    'Offsides': 'التسلل',
  };
}
