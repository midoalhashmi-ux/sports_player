import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../channels/channels_home_tab.dart';
import '../favorites/favorites_screen.dart';
import '../matches/matches_screen.dart';
import '../media/media_home_tab.dart';
import '../../widgets/app_drawer.dart';

/// الشاشة الجذر للتطبيق. ترتيب التبويبات الفيزيائي ثابت صراحةً:
/// اليمين = القنوات، الوسط = النتائج، اليسار = أفلام ومسلسلات.
/// لا نعتمد على ترتيب Row تحت RTL لضمان النتيجة نفسها على Android.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _tabKey = 'home_last_tab';
  final _drawerController = GlobalKey<_LeftDrawerOverlayState>();
  int _tabIndex = 0;
  bool _drawerOpen = false;

  @override
  void initState() {
    super.initState();
    _restoreTab();
  }

  Future<void> _restoreTab() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_tabKey);
    if (!mounted || value == null || value < 0 || value > 2) return;
    setState(() => _tabIndex = value);
  }

  Future<void> _selectTab(int index) async {
    if (_tabIndex == index) return;
    setState(() => _tabIndex = index);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tabKey, index);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_drawerOpen && _tabIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_drawerOpen) {
          _drawerController.currentState?.close();
          return;
        }
        if (_tabIndex != 0) {
          _selectTab(0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('BinSheikh'),
          // actions تقع في الجهة الفيزيائية اليسرى في هذا الـ AppBar العربي،
          // ونفتح منها القائمة المخصصة المثبتة على left: 0.
          leading: IconButton(
            icon: const Icon(Icons.favorite),
            tooltip: 'المفضلة',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FavoritesScreen()),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'القائمة الجانبية',
              onPressed: () {
                setState(() => _drawerOpen = true);
                _drawerController.currentState?.open();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                _buildMainTabs(context),
                Expanded(
                  child: IndexedStack(
                    index: _tabIndex,
                    children: const [
                      ChannelsHomeTab(),
                      MatchesScreen(),
                      MediaHomeTab(),
                    ],
                  ),
                ),
              ],
            ),
            _LeftDrawerOverlay(
              key: _drawerController,
              onOpenChanged: (open) {
                if (mounted) setState(() => _drawerOpen = open);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainTabs(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final items = <_TabInfo>[
      const _TabInfo(title: 'أفلام ومسلسلات', icon: Icons.movie_outlined, activeIcon: Icons.movie),
      const _TabInfo(title: 'النتائج', icon: Icons.sports_score_outlined, activeIcon: Icons.sports_score),
      const _TabInfo(title: 'القنوات', icon: Icons.live_tv_outlined, activeIcon: Icons.live_tv),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      // LTR هنا متعمد فقط لتثبيت المواقع الفيزيائية: أول عنصر يساراً.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: [
            for (var physicalIndex = 0; physicalIndex < items.length; physicalIndex++)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: physicalIndex == 0 ? 0 : 4),
                  child: _MainTabButton(
                    info: items[physicalIndex],
                    selected: _tabIndex == (2 - physicalIndex),
                    primary: primary,
                    onTap: () => _selectTab(2 - physicalIndex),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MainTabButton extends StatelessWidget {
  final _TabInfo info;
  final bool selected;
  final Color primary;
  final VoidCallback onTap;

  const _MainTabButton({
    required this.info,
    required this.selected,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: info.title,
      child: Material(
        color: selected ? primary : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: selected ? primary : Theme.of(context).dividerColor,
              ),
              color: selected ? null : Theme.of(context).colorScheme.surface.withOpacity(.35),
            ),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? info.activeIcon : info.icon,
                      size: 20, color: selected ? Colors.white : null),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      info.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? Colors.white : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabInfo {
  final String title;
  final IconData icon;
  final IconData activeIcon;
  const _TabInfo({required this.title, required this.icon, required this.activeIcon});
}

class _LeftDrawerOverlay extends StatefulWidget {
  final ValueChanged<bool>? onOpenChanged;

  const _LeftDrawerOverlay({super.key, this.onOpenChanged});

  @override
  State<_LeftDrawerOverlay> createState() => _LeftDrawerOverlayState();
}

class _LeftDrawerOverlayState extends State<_LeftDrawerOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _open = false;
  double _width = 0;

  bool get isOpen => _open;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      reverseDuration: const Duration(milliseconds: 280),
    );
  }

  Future<void> open() async {
    if (_open) return;
    setState(() => _open = true);
    widget.onOpenChanged?.call(true);
    await _controller.forward();
  }

  Future<void> close() async {
    if (!_open) return;
    await _controller.reverse();
    if (mounted) {
      setState(() => _open = false);
      widget.onOpenChanged?.call(false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _width = (MediaQuery.sizeOf(context).width * .84).clamp(280.0, 360.0).toDouble();
    final slide = Tween<double>(begin: -_width, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    return IgnorePointer(
      ignoring: !_open,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: close,
                onHorizontalDragUpdate: (details) {
                  if (details.delta.dx < -8) close();
                },
                child: Container(color: Colors.black.withOpacity(.42 * _controller.value)),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: slide.value,
              width: _width,
              child: GestureDetector(
                onHorizontalDragUpdate: (details) {
                  if (details.delta.dx < -8) close();
                },
                child: Material(
                  elevation: 18,
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: AppDrawer(onClose: close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
