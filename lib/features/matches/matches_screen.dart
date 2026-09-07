import 'package:flutter/material.dart';
import '../../core/data/football_ar_translations.dart';
import '../../core/models/match_model.dart';
import '../../core/services/matches_service.dart';
import 'match_details_screen.dart';

/// شاشة "النتائج": جدول مباريات كرة القدم (العربية والعالمية) ليوم واحد،
/// مع إمكانية التنقل بين الأيام عبر سهمين، ضمن نافذة 7 أيام (من 3 أيام
/// ماضية إلى 3 أيام قادمة) — نفس النافذة التي يزامنها الووركر بـ
/// Firestore، فلا داعي للسماح بالتنقل خارجها لأن البيانات لن تكون
/// موجودة أصلاً. لا حاجة لأي إعداد إضافي — المصدر مجاني بالكامل.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

enum _StatusFilter { all, live, upcoming, finished }

class _MatchesScreenState extends State<MatchesScreen> {
  // إزاحة الأيام عن اليوم الحالي: 0 = اليوم، 1 = غداً، -1 = أمس ...
  int _dayOffset = 0;
  late Future<List<MatchModel>> _future;

  _StatusFilter _statusFilter = _StatusFilter.all;
  bool _searchActive = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  static const int _minDayOffset = -3;
  static const int _maxDayOffset = 3;

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
    _future = MatchesService.fetchMatches(_selectedDate);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateTime get _selectedDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: _dayOffset));
  }

  void _changeDay(int delta) {
    final next = _dayOffset + delta;
    if (next < _minDayOffset || next > _maxDayOffset) return;
    setState(() {
      _dayOffset = next;
      _future = MatchesService.fetchMatches(_selectedDate);
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: today.subtract(const Duration(days: -_minDayOffset)),
      lastDate: today.add(const Duration(days: _maxDayOffset)),
      locale: const Locale('ar'),
    );
    if (picked == null) return;
    setState(() {
      _dayOffset = DateTime(picked.year, picked.month, picked.day).difference(today).inDays;
      _future = MatchesService.fetchMatches(_selectedDate);
    });
  }

  Future<void> _refresh() async {
    setState(() => _future = MatchesService.fetchMatches(_selectedDate));
    await _future;
  }

  String get _dayLabel {
    if (_dayOffset == 0) return 'اليوم';
    if (_dayOffset == 1) return 'غداً';
    if (_dayOffset == -1) return 'أمس';
    final date = _selectedDate;
    return '${_weekdaysAr[date.weekday - 1]} ${date.day}/${date.month}';
  }

  List<MatchModel> _applyFilters(List<MatchModel> matches) {
    var result = matches;
    switch (_statusFilter) {
      case _StatusFilter.live:
        result = result.where((m) => m.status == MatchStatus.live).toList();
        break;
      case _StatusFilter.upcoming:
        result = result.where((m) => m.status == MatchStatus.upcoming).toList();
        break;
      case _StatusFilter.finished:
        result = result.where((m) => m.status == MatchStatus.finished).toList();
        break;
      case _StatusFilter.all:
        break;
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim();
      result = result.where((m) {
        final home = FootballTranslations.team(m.homeTeamEn);
        final away = FootballTranslations.team(m.awayTeamEn);
        return home.contains(q) ||
            away.contains(q) ||
            m.homeTeamEn.toLowerCase().contains(q.toLowerCase()) ||
            m.awayTeamEn.toLowerCase().contains(q.toLowerCase());
      }).toList();
    }
    return result;
  }

  Future<void> _openFilterSheet() async {
    final chosen = await showModalBottomSheet<_StatusFilter>(
      context: context,
      backgroundColor: const Color(0xFF10182B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        Widget option(_StatusFilter value, String label, IconData icon) {
          final selected = _statusFilter == value;
          return ListTile(
            leading: Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : Colors.white54),
            title: Text(label,
                style: TextStyle(
                  color: selected ? Theme.of(context).colorScheme.primary : Colors.white,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                )),
            trailing: selected ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary) : null,
            onTap: () => Navigator.of(context).pop(value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('عرض المباريات',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                ),
              ),
              option(_StatusFilter.all, 'الكل', Icons.list_alt),
              option(_StatusFilter.live, 'المباشرة فقط', Icons.podcasts),
              option(_StatusFilter.upcoming, 'لم تبدأ بعد', Icons.schedule),
              option(_StatusFilter.finished, 'انتهت', Icons.check_circle_outline),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (chosen != null) setState(() => _statusFilter = chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTopBar(context),
        if (!_searchActive) _buildDaySwitcher(context),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: FutureBuilder<List<MatchModel>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildMessage(
                    context,
                    icon: Icons.wifi_off,
                    text: 'تعذر جلب المباريات. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
                  );
                }
                // نستبعد أي دوري غير مدعوم (درجة ثانية/ثالثة أو دولة غير
                // مطلوبة) قبل أي فلتر آخر، حتى تعكس رسالة "لا توجد
                // مباريات" ونتائج البحث/الفلترة القائمة المعروضة فعلاً
                // للمستخدم لا القائمة الخام القادمة من المصدر.
                final allMatches = (snapshot.data ?? [])
                    .where((m) => FootballTranslations.isSupportedLeague(
                        m.leagueNameEn, m.leagueCountryEn))
                    .toList();
                final matches = _applyFilters(allMatches);
                if (matches.isEmpty) {
                  return _buildMessage(
                    context,
                    icon: Icons.sports_soccer,
                    text: allMatches.isEmpty
                        ? 'لا توجد مباريات مسجّلة في هذا اليوم.'
                        : 'لا توجد نتائج مطابقة لهذا الفلتر/البحث.',
                  );
                }
                return _buildMatchesList(context, matches);
              },
            ),
          ),
        ),
      ],
    );
  }

  /// شريط علوي بستايل شبيه بتطبيقات النتائج المعروفة: شعار، عدّاد "مباشر"،
  /// زر فلترة (حالة المباراة)، وزر بحث عن فريق — بدل شريط بسيط بدون أي
  /// أدوات تحكم.
  Widget _buildTopBar(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: _searchActive
          ? Row(
              children: [
                IconButton(
                  tooltip: 'إغلاق البحث',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _searchActive = false;
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      hintText: 'ابحث عن فريق...',
                      border: InputBorder.none,
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                // شعار مصغّر — نفس فكرة الشعار أعلى يمين الشاشة في التطبيقات
                // المرجعية.
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.sports_soccer, size: 18, color: primary),
                ),
                const SizedBox(width: 8),
                _buildLiveBadge(context),
                const Spacer(),
                IconButton(
                  tooltip: 'بحث عن فريق',
                  icon: const Icon(Icons.search),
                  onPressed: () => setState(() => _searchActive = true),
                ),
                IconButton(
                  tooltip: 'فلترة',
                  icon: Icon(Icons.filter_list,
                      color: _statusFilter == _StatusFilter.all ? null : primary),
                  onPressed: _openFilterSheet,
                ),
              ],
            ),
    );
  }

  /// شارة "مباشر" — عند الضغط عليها تُفعّل/تُلغى فلترة "المباشرة فقط" مباشرة،
  /// كاختصار سريع لأكثر فلتر يُستخدم.
  Widget _buildLiveBadge(BuildContext context) {
    return FutureBuilder<List<MatchModel>>(
      future: _future,
      builder: (context, snapshot) {
        final liveCount = (snapshot.data ?? [])
            .where((m) => FootballTranslations.isSupportedLeague(m.leagueNameEn))
            .where((m) => m.status == MatchStatus.live)
            .length;
        final active = _statusFilter == _StatusFilter.live;
        return GestureDetector(
          onTap: () => setState(() {
            _statusFilter = active ? _StatusFilter.all : _StatusFilter.live;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: active ? Colors.redAccent : Colors.redAccent.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'مباشر $liveCount',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: active ? Colors.white : Colors.redAccent,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDaySwitcher(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ملاحظة: مكان السهمين لا يتغير (يبقى اليمين/اليسار كما هو
          // بصرياً)، لكن الوظيفة كانت معكوسة — هذا السهم (يمين الشاشة في
          // RTL) يرجع لليوم السابق الآن، بدل ما كان يتقدّم لليوم التالي.
          IconButton(
            tooltip: 'اليوم السابق',
            icon: const Icon(Icons.chevron_left),
            onPressed: _dayOffset <= _minDayOffset ? null : () => _changeDay(-1),
          ),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today, size: 15, color: Colors.white54),
                  const SizedBox(width: 6),
                  Text(
                    _dayLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'اليوم التالي',
            icon: const Icon(Icons.chevron_right),
            onPressed: _dayOffset >= _maxDayOffset ? null : () => _changeDay(1),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(BuildContext context,
      {required IconData icon, required String text}) {
    return ListView(
      // ListView حتى يبقى RefreshIndicator (سحب للتحديث) شغّالاً حتى في
      // حالة الخطأ أو القائمة الفارغة.
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
        Icon(icon, size: 48, color: Colors.white38),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildMatchesList(BuildContext context, List<MatchModel> matches) {
    // التصفية حسب الدرجة (isSupportedLeague) طُبّقت مسبقاً في build() قبل
    // الوصول لهذه الدالة — راجع الشرح هناك.
    // المفتاح (اسم الدوري + الدولة) لا الاسم وحده — بعض الأسماء تتكرر
    // بنفس الشكل بالضبط لأكثر من دولة (راجع الشرح في isSupportedLeague).
    final grouped = <String, List<MatchModel>>{};
    for (final match in matches) {
      final key = '${match.leagueNameEn}|${match.leagueCountryEn}';
      grouped.putIfAbsent(key, () => []).add(match);
    }

    // ترتيب الدوريات حسب الأولوية (الأكثر شعبية أولاً: الإنجليزي، السعودي،
    // الإسباني...) بدل ترتيب ورودها العشوائي من المصدر.
    final leagueKeys = grouped.keys.toList()
      ..sort((a, b) {
        final matchA = grouped[a]!.first;
        final matchB = grouped[b]!.first;
        return FootballTranslations
            .leaguePriority(matchA.leagueNameEn, matchA.leagueCountryEn)
            .compareTo(FootballTranslations.leaguePriority(
                matchB.leagueNameEn, matchB.leagueCountryEn));
      });

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: leagueKeys.length,
      itemBuilder: (context, index) {
        final leagueKey = leagueKeys[index];
        final leagueMatches = grouped[leagueKey]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
              child: Row(
                children: [
                  if (leagueMatches.first.leagueLogo != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Image.network(
                        leagueMatches.first.leagueLogo!,
                        width: 22,
                        height: 22,
                        errorBuilder: (_, __, ___) => const SizedBox(width: 22),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      FootballTranslations.leagueWithCountry(
                          leagueMatches.first.leagueNameEn,
                          leagueMatches.first.leagueCountryEn),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
            ...leagueMatches.map((match) => _MatchTile(match: match)),
          ],
        );
      },
    );
  }
}

class _MatchTile extends StatelessWidget {
  final MatchModel match;
  const _MatchTile({required this.match});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MatchDetailsScreen(match: match),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Expanded(child: _teamColumn(match.homeTeamEn, match.homeLogo)),
              SizedBox(width: 76, child: _centerInfo(context, primary)),
              Expanded(child: _teamColumn(match.awayTeamEn, match.awayLogo)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _teamColumn(String nameEn, String? logo) {
    return Column(
      children: [
        if (logo != null)
          Image.network(logo, width: 28, height: 28,
              errorBuilder: (_, __, ___) => const Icon(Icons.shield_outlined, size: 28))
        else
          const Icon(Icons.shield_outlined, size: 28),
        const SizedBox(height: 4),
        Text(
          FootballTranslations.team(nameEn),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );
  }

  Widget _centerInfo(BuildContext context, Color primary) {
    switch (match.status) {
      case MatchStatus.live:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${match.homeScore ?? 0} - ${match.awayScore ?? 0}',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primary)),
            const SizedBox(height: 3),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: Colors.redAccent, borderRadius: BorderRadius.circular(4)),
              child: const Text('مباشر', style: TextStyle(color: Colors.white, fontSize: 9)),
            ),
          ],
        );
      case MatchStatus.finished:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${match.homeScore ?? 0} - ${match.awayScore ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 3),
            const Text('انتهت', style: TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        );
      case MatchStatus.postponed:
        return const Text('مؤجلة',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent, fontSize: 10.5));
      case MatchStatus.upcoming:
        return Text(FootballTranslations.formatTime12(match.kickoff),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12));
    }
  }
}
