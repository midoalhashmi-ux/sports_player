/// نتيجة مباراة واحدة ضمن آخر 5 مباريات لفريق، أو ضمن سجل المواجهات
/// المباشرة بين فريقين — نسخة مبسّطة (بدون كل حقول MatchModel) كافية
/// لعرض شارة نتيجة (فوز/تعادل/خسارة) + الخصم + التاريخ.
class FormResult {
  final String opponentEn;
  final int teamScore;
  final int opponentScore;
  final String dateEvent; // YYYY-MM-DD
  final String leagueNameEn;

  FormResult({
    required this.opponentEn,
    required this.teamScore,
    required this.opponentScore,
    required this.dateEvent,
    required this.leagueNameEn,
  });

  /// W (فوز) / D (تعادل) / L (خسارة) من منظور الفريق صاحب هذا السجل.
  String get outcome {
    if (teamScore > opponentScore) return 'W';
    if (teamScore < opponentScore) return 'D';
    return 'L';
  }

  factory FormResult.fromJson(Map<String, dynamic> json) => FormResult(
        opponentEn: (json['opponentEn'] ?? '').toString(),
        teamScore: (json['teamScore'] as num?)?.toInt() ?? 0,
        opponentScore: (json['opponentScore'] as num?)?.toInt() ?? 0,
        dateEvent: (json['dateEvent'] ?? '').toString(),
        leagueNameEn: (json['leagueNameEn'] ?? '').toString(),
      );
}

class PreMatchInfo {
  final List<FormResult> homeForm; // آخر 5 مباريات لفريق المضيف
  final List<FormResult> awayForm; // آخر 5 مباريات لفريق الضيف
  final List<FormResult> h2h; // آخر مواجهات مباشرة (من منظور فريق المضيف)

  PreMatchInfo({
    required this.homeForm,
    required this.awayForm,
    required this.h2h,
  });

  factory PreMatchInfo.fromJson(Map<String, dynamic> json) => PreMatchInfo(
        homeForm: ((json['homeForm'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(FormResult.fromJson)
            .toList(),
        awayForm: ((json['awayForm'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(FormResult.fromJson)
            .toList(),
        h2h: ((json['h2h'] as List<dynamic>?) ?? [])
            .whereType<Map<String, dynamic>>()
            .map(FormResult.fromJson)
            .toList(),
      );
}
