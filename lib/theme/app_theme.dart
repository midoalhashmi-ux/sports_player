import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// نظام تصميم موحّد لتطبيق المشغل — هوية بصرية احترافية بدل الألوان
/// المبعثرة (Colors.redAccent, Colors.black87...) المكرّرة سابقاً بكل شاشة
/// على حدة. أي تغيير مستقبلي بالهوية (لون، خط) يصير من مكان واحد فقط.
class AppTheme {
  AppTheme._();

  // ---------------------- الألوان الأساسية ----------------------
  static const Color background = Color(0xFF0B0D12);
  static const Color surface = Color(0xFF15181F);
  static const Color surfaceVariant = Color(0xFF1E222B);
  static const Color accent = Color(0xFFE5303A);
  static const Color accentMuted = Color(0xFFB4232B);
  static const Color onSurfaceMuted = Color(0xFF9AA1AE);
  static const Color border = Color(0xFF262B35);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.tajawalTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    );

    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: accent,
      secondary: accent,
      error: const Color(0xFFFF5A5F),
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 19,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: onSurfaceMuted,
        indicatorColor: accent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: const DividerThemeData(color: border, thickness: 1, space: 1),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surfaceVariant,
          disabledForegroundColor: onSurfaceMuted,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: Colors.white),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.4),
        ),
        hintStyle: TextStyle(color: onSurfaceMuted),
        labelStyle: TextStyle(color: onSurfaceMuted),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: Colors.white,
        textColor: Colors.white,
        selectedColor: accent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? accent : onSurfaceMuted),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? accent.withValues(alpha: 0.4) : border),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: accent.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: accent),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceVariant,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: onSurfaceMuted),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      drawerTheme: const DrawerThemeData(backgroundColor: surface),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surfaceVariant,
        labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
        side: const BorderSide(color: border),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}
