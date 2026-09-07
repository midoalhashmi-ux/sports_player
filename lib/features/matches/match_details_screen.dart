import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/data/football_ar_translations.dart';
import '../../core/models/match_model.dart';
import '../../core/models/match_stats_model.dart';
import '../../core/models/pre_match_info_model.dart';
import '../../core/services/match_stats_service.dart';
import '../../core/services/pre_match_service.dart';

/// شاشة تفاصيل مباراة واحدة: النتيجة + معلومات اللقاء + آخر النتائج
/// (نموذج الفريقين والمواجهات المباشرة) + إحصائيات (استحواذ، تسديدات،
/// ركنيات، بطاقات...) عند توفرها.
///
/// ملاحظة تصميم مهمة: هذه الشاشة تعرض فقط الحقول المتوفرة فعلياً من
/// المصدر الحالي (matches_daily عبر الووركر + getPreMatchInfo +
/// getMatchStats)، بما فيها الجولة وحكم المباراة (يُستخرجان الآن من
/// نفس استجابة /fixtures بدون أي طلب API إضافي). لا يوجد هنا أي عنصر
/// يحتاج طلب API إضافي غير مُستخدَم أصلاً — لا تبويب ترتيب، ولا تشكيلة
/// متوقعة، ولا هدافين، ولا قنوات ناقلة/معلقين (هذي البيانات غير متوفرة
/// في API-Football أصلاً وتحتاج إدخال يدوي من لوحة تحكم لا توجد بعد).
/// الإحصائيات لا تُستدعى إطلاقاً للمباريات التي لم تبدأ بعد — لا توجد
/// إحصائيات لها.
class MatchDetailsScreen extends StatefulWidget {
  final MatchModel match;
  const MatchDetailsScreen({super.key, required this.match});

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  late Future<MatchStatsResult>? _future;
  late Future<PreMatchResult>? _preMatchFuture;

  // مؤقّت العدّ التنازلي لموعد الانطلاق — حساب محلي بحت من DateTime
  // المباراة (المتوفر أصلاً)، بدون أي اتصال شبكة إضافي.
  Timer? _countdownTimer;

  static const _weekdaysAr = [
    'الاثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  @override
  void initState() {
    super.initState();
    final match = widget.match;
    final canHaveStats = match.status == MatchStatus.live ||
        match.status == MatchStatus.finished;

    _future = canHaveStats
        ? MatchStatsService.fetchStats(
            fixtureId: match.id,
            matchFinished: match.status == MatchStatus.finished,
          )
        : null;

    // معلومات ما قبل المباراة (آخر 5 مباريات + المواجهات المباشرة) تعتمد
    // فقط على هوية الفريقين، مفيدة قبل المباراة وأثناءها وبعدها — تُجلب
    // طالما معرّفا الفريقين متوفران (مباريات الدوريات الصغيرة القديمة
    // المخزّنة قبل هذا التحديث قد لا تملكهما).
    _preMatchFuture = (match.homeTeamId != null && match.awayTeamId != null)
        ? PreMatchService.fetchInfo(
            homeTeamId: match.homeTeamId!,
            awayTeamId: match.awayTeamId!,
          )
        : null;

    if (match.status == MatchStatus.upcoming) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${FootballTranslations.team(match.homeTeamEn)} ضد ${FootballTranslations.team(match.awayTeamEn)}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildScoreHeader(context, match),
          const SizedBox(height: 16),
          _buildMatchInfoCard(context, match),
          const SizedBox(height: 24),
          _buildPreMatchSection(context, match),
          const SizedBox(height: 24),
          _buildStatsSection(context, match),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // رأس الشاشة: شعار الفريقين + النتيجة أو العدّ التنازلي + حالة المباراة
  // -------------------------------------------------------------------
  Widget _buildScoreHeader(BuildContext context, MatchModel match) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
        child: Row(
          children: [
            Expanded(child: _teamHeader(match.homeTeamEn, match.homeLogo)),
            SizedBox(
              width: 110,
              child: _buildCenterStatus(context, match, primary),
            ),
            Expanded(child: _teamHeader(match.awayTeamEn, match.awayLogo)),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterStatus(BuildContext context, MatchModel match, Color primary) {
    if (match.status == MatchStatus.upcoming) {
      final remaining = match.kickoff.difference(DateTime.now());
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            FootballTranslations.formatTime12(match.kickoff),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (!remaining.isNegative)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatCountdown(remaining),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            )
          else
            const Text('لم تبدأ بعد',
                style: TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (match.hasScore)
          Text(
            '${match.homeScore} - ${match.awayScore}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          )
        else
          const Text('- : -',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white38)),
        const SizedBox(height: 6),
        _statusChip(match.status),
      ],
    );
  }

  Widget _statusChip(MatchStatus status) {
    late Color color;
    late String label;
    switch (status) {
      case MatchStatus.live:
        color = Colors.redAccent;
        label = 'مباشر الآن';
        break;
      case MatchStatus.finished:
        color = Colors.white54;
        label = 'انتهت المباراة';
        break;
      case MatchStatus.postponed:
        color = Colors.orangeAccent;
        label = 'مؤجلة';
        break;
      case MatchStatus.upcoming:
        color = Colors.white54;
        label = 'لم تبدأ بعد';
        break;
    }
    if (status == MatchStatus.live) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: const Text('مباشر الآن',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    return Text(label, style: TextStyle(fontSize: 12, color: color));
  }

  /// يهيّئ عدّاً تنازلياً بصيغة سهلة القراءة: "س:د:ث"، ويضيف الأيام في
  /// المقدمة فقط إذا تجاوز الفارق يوماً كاملاً.
  String _formatCountdown(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    final hh = hours.toString().padLeft(2, '0');
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (days > 0) return '$days يوم $hh:$mm:$ss';
    return '$hh : $mm : $ss';
  }

  Widget _teamHeader(String nameEn, String? logo) {
    return Column(
      children: [
        if (logo != null)
          Image.network(logo, width: 48, height: 48,
              errorBuilder: (_, __, ___) => const Icon(Icons.shield_outlined, size: 48))
        else
          const Icon(Icons.shield_outlined, size: 48),
        const SizedBox(height: 8),
        Text(FootballTranslations.team(nameEn),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // -------------------------------------------------------------------
  // معلومات اللقاء: البطولة، الجولة وحكم المباراة (إن توفّرا من المصدر —
  // مستخرَجان الآن في normalizeFixture من نفس استجابة /fixtures بدون أي
  // طلب API إضافي)، الملعب إن وُجد، وقت المباراة، تاريخ المباراة.
  // -------------------------------------------------------------------
  Widget _buildMatchInfoCard(BuildContext context, MatchModel match) {
    final rows = <Widget>[
      _infoRow(
        label: 'البطولة',
        value: FootballTranslations.leagueWithCountry(match.leagueNameEn, match.leagueCountryEn),
        leadingImage: match.leagueLogo,
      ),
    ];

    if (match.round != null && match.round!.trim().isNotEmpty) {
      rows.add(_infoRow(label: 'الجولة', value: _formatRound(match.round!)));
    }

    if (match.venue != null && match.venue!.trim().isNotEmpty) {
      rows.add(_infoRow(label: 'ملعب المباراة', value: match.venue!));
    }

    if (match.referee != null && match.referee!.trim().isNotEmpty) {
      rows.add(_infoRow(label: 'حكم المباراة', value: match.referee!));
    }

    rows.add(_infoRow(
      label: 'وقت المباراة',
      value: FootballTranslations.formatTime12(match.kickoff),
    ));

    rows.add(_infoRow(
      label: 'تاريخ المباراة',
      value: _formatDate(match.kickoff),
    ));

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 6, 14, 4),
              child: Text('معلومات اللقاء',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
            for (int i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i != rows.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow({required String label, required String value, String? leadingImage}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
          Row(
            children: [
              Flexible(
                child: Text(value,
                    textAlign: TextAlign.left,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
              ),
              if (leadingImage != null) ...[
                const SizedBox(width: 8),
                Image.network(leadingImage, width: 18, height: 18,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink()),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// يحوّل صيغة الجولة القادمة من API-Football (مثل "Regular Season - 2")
  /// إلى "الجولة 2". أي صيغة أخرى غير معروفة (أدوار كأسية مثلاً) تُعرض
  /// كما وردت من المصدر بدل إخفائها.
  String _formatRound(String raw) {
    final match = RegExp(r'-\s*(\d+)\s*$').firstMatch(raw);
    if (match != null) return 'الجولة ${match.group(1)}';
    return raw;
  }

  String _formatDate(DateTime dt) {
    final weekday = _weekdaysAr[dt.weekday - 1];
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$weekday ($dd-$mm-${dt.year})';
  }

  // -------------------------------------------------------------------
  // قبل المباراة: نموذج آخر 5 مباريات لكل فريق + آخر مواجهات مباشرة
  // -------------------------------------------------------------------
  Widget _buildPreMatchSection(BuildContext context, MatchModel match) {
    if (_preMatchFuture == null) return const SizedBox.shrink();

    return FutureBuilder<PreMatchResult>(
      future: _preMatchFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        final result = snapshot.data;
        if (result is! PreMatchSuccess) return const SizedBox.shrink();
        final info = result.info;
        if (info.homeForm.isEmpty && info.awayForm.isEmpty && info.h2h.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('قبل المباراة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                if (info.homeForm.isNotEmpty)
                  _formRow(FootballTranslations.team(match.homeTeamEn), info.homeForm),
                if (info.awayForm.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _formRow(FootballTranslations.team(match.awayTeamEn), info.awayForm),
                ],
                if (info.h2h.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 4),
                  Text('آخر ${info.h2h.length} مواجهات مباشرة',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  _formRow(null, info.h2h),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _formRow(String? label, List<FormResult> results) {
    return Row(
      children: [
        if (label != null)
          SizedBox(
            width: 90,
            child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
          ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: results.map(_outcomeBadge).toList(),
          ),
        ),
      ],
    );
  }

  Widget _outcomeBadge(FormResult result) {
    late Color color;
    late String letter;
    switch (result.outcome) {
      case 'W':
        color = Colors.green;
        letter = 'ف';
        break;
      case 'L':
        color = Colors.redAccent;
        letter = 'خ';
        break;
      default:
        color = Colors.orangeAccent;
        letter = 'ت';
    }
    return Tooltip(
      message:
          '${result.teamScore} - ${result.opponentScore} ضد ${FootballTranslations.team(result.opponentEn)}',
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Text(letter,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // -------------------------------------------------------------------
  // الإحصائيات (بعد بداية المباراة فقط)
  // -------------------------------------------------------------------
  Widget _buildStatsSection(BuildContext context, MatchModel match) {
    if (_future == null) {
      return _buildInfoMessage(
        icon: Icons.hourglass_empty,
        text: 'الإحصائيات تظهر بعد بداية المباراة.',
      );
    }

    return FutureBuilder<MatchStatsResult>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final result = snapshot.data;
        if (result is MatchStatsSuccess) {
          return _buildStatsTable(context, result.stats);
        }
        if (result is MatchStatsUnavailable) {
          return _buildInfoMessage(
              icon: Icons.bar_chart, text: result.message);
        }
        if (result is MatchStatsError) {
          return _buildInfoMessage(
              icon: Icons.wifi_off, text: result.message);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildInfoMessage({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.white38),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildStatsTable(BuildContext context, MatchStats stats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('الإحصائيات',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        for (final entry in MatchStats.orderedTypes.entries)
          _statRow(entry.value, stats.home.display(entry.key),
              stats.away.display(entry.key)),
      ],
    );
  }

  Widget _statRow(String labelAr, String homeValue, String awayValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(homeValue,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(labelAr,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          SizedBox(
            width: 60,
            child: Text(awayValue,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
