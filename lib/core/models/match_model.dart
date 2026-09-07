/// حالة المباراة بشكل مبسّط نستخدمه في الواجهة.
enum MatchStatus { upcoming, live, finished, postponed }

class MatchModel {
  final String id;
  final String leagueNameEn;
  // اسم الدولة كما يرد من المصدر (بالإنجليزي) — ضروري لأن بعض أسماء
  // الدوريات تتكرر بنفس الشكل بالضبط لأكثر من دولة (مثال: "Premier
  // League" لمصر وإنجلترا معاً)، فلا يكفي الاعتماد على leagueNameEn وحده
  // للتفريق أو الترجمة أو التجميع.
  final String leagueCountryEn;
  final String? leagueLogo;
  final String homeTeamEn;
  final String awayTeamEn;
  final String? homeLogo;
  final String? awayLogo;
  final String? homeTeamId; // معرّف الفريق في API-Football — لجلب معلومات ما قبل المباراة
  final String? awayTeamId;
  final DateTime kickoff; // بتوقيت الجهاز المحلي
  final int? homeScore;
  final int? awayScore;
  final MatchStatus status;
  final String? venue;
  final String? round; // مثال: "Regular Season - 2" — من league.round في API-Football
  final String? referee; // حكم المباراة، إن كان متوفراً من المصدر

  MatchModel({
    required this.id,
    required this.leagueNameEn,
    this.leagueCountryEn = '',
    this.leagueLogo,
    required this.homeTeamEn,
    required this.awayTeamEn,
    this.homeLogo,
    this.awayLogo,
    this.homeTeamId,
    this.awayTeamId,
    required this.kickoff,
    this.homeScore,
    this.awayScore,
    required this.status,
    this.venue,
    this.round,
    this.referee,
  });

  bool get hasScore => homeScore != null && awayScore != null;

  /// يبني نموذج مباراة من استجابة TheSportsDB (eventsday.php).
  factory MatchModel.fromTheSportsDb(Map<String, dynamic> json) {
    DateTime kickoff;
    try {
      final dateStr = (json['dateEvent'] ?? '').toString();
      final timeStr = (json['strTime'] ?? '00:00:00').toString();
      // التوقيت القادم من TheSportsDB بتوقيت UTC.
      kickoff = DateTime.parse('${dateStr}T$timeStr' 'Z').toLocal();
    } catch (_) {
      kickoff = DateTime.now();
    }

    final statusRaw = (json['strStatus'] ?? '').toString().toUpperCase();
    final homeScoreRaw = json['intHomeScore'];
    final awayScoreRaw = json['intAwayScore'];
    final homeScore = homeScoreRaw == null ? null : int.tryParse('$homeScoreRaw');
    final awayScore = awayScoreRaw == null ? null : int.tryParse('$awayScoreRaw');

    MatchStatus status;
    if (statusRaw.contains('PST') || statusRaw.contains('POSTPON')) {
      status = MatchStatus.postponed;
    } else if (statusRaw == 'FT' ||
        statusRaw == 'AET' ||
        statusRaw == 'PEN' ||
        statusRaw.contains('MATCH FINISHED')) {
      status = MatchStatus.finished;
    } else if (statusRaw.isNotEmpty &&
        (statusRaw.contains('1H') ||
            statusRaw.contains('2H') ||
            statusRaw.contains('LIVE') ||
            statusRaw == 'HT' ||
            RegExp(r"^\d+'?$").hasMatch(statusRaw))) {
      status = MatchStatus.live;
    } else if (homeScore != null &&
        awayScore != null &&
        kickoff.isBefore(DateTime.now().subtract(const Duration(hours: 2)))) {
      status = MatchStatus.finished;
    } else {
      status = MatchStatus.upcoming;
    }

    return MatchModel(
      id: (json['idEvent'] ?? '').toString(),
      leagueNameEn: (json['strLeague'] ?? '').toString(),
      leagueCountryEn: (json['strLeagueCountry'] ?? '').toString(),
      leagueLogo: (json['strLeagueBadge'] as String?)?.trim().isNotEmpty == true
          ? json['strLeagueBadge']
          : null,
      homeTeamEn: (json['strHomeTeam'] ?? '').toString(),
      awayTeamEn: (json['strAwayTeam'] ?? '').toString(),
      homeLogo: (json['strHomeTeamBadge'] as String?)?.trim().isNotEmpty == true
          ? json['strHomeTeamBadge']
          : null,
      awayLogo: (json['strAwayTeamBadge'] as String?)?.trim().isNotEmpty == true
          ? json['strAwayTeamBadge']
          : null,
      homeTeamId: (json['homeTeamId'] ?? '').toString().trim().isNotEmpty
          ? json['homeTeamId'].toString()
          : null,
      awayTeamId: (json['awayTeamId'] ?? '').toString().trim().isNotEmpty
          ? json['awayTeamId'].toString()
          : null,
      kickoff: kickoff,
      homeScore: homeScore,
      awayScore: awayScore,
      status: status,
      venue: (json['strVenue'] as String?)?.trim().isEmpty == true
          ? null
          : json['strVenue'],
      round: (json['strRound'] as String?)?.trim().isEmpty == true
          ? null
          : json['strRound'],
      referee: (json['strReferee'] as String?)?.trim().isEmpty == true
          ? null
          : json['strReferee'],
    );
  }
}
