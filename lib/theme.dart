import 'package:flutter/material.dart';

class AppTheme {
  // --- لوحة الألوان الاحترافية (High Level Palette) ---

  // اللون الأساسي: بنفسجي متوهج (Vibrant Violet) - مميز وعصري لبرامج المحادثة
  static const Color _primary = Color(0xFF7C4DFF);
  static const Color _primaryContainer = Color(0xFF512DA8);

  // اللون الثانوي: تركواز مشع (Cyan Accent) - لإبراز التفاصيل والأزرار
  static const Color _secondary = Color(0xFF64FFDA);

  // ألوان الخلفية: داكنة مع لمسة كحلية (Midnight Blue)
  static const Color _background = Color(0xFF0F111A);
  static const Color _surface = Color(0xFF1A1D26);
  static const Color _surfaceVariant = Color(0xFF282C38); // لحقول الإدخال وفقاعات المحادثة

  static const Color _error = Color(0xFFFF5252);
  static const Color _onSurface = Color(0xFFE6E8EB);
  static const Color _onBackground = Color(0xFFCDD1D6);

  // تدرج لوني جاهز للاستخدام في الأزرار أو الخلفيات المميزة
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [_primary, Color(0xFF536DFE)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // تعريف مخطط الألوان (Color Scheme)
  static const ColorScheme _colorScheme = ColorScheme(
    brightness: Brightness.dark,

    primary: _primary,
    onPrimary: Colors.white,
    primaryContainer: _primaryContainer,
    onPrimaryContainer: Colors.white,

    secondary: _secondary,
    onSecondary: Colors.black,
    secondaryContainer: Color(0xFF00BFA5),
    onSecondaryContainer: Colors.black,

    surface: _surface,
    onSurface: _onSurface,
    surfaceContainerHighest: _surfaceVariant,
    onSurfaceVariant: Color(0xFF9DA3AE),

    // background: _background, // Deprecated, mapped to surface
    // onBackground: _onBackground, // Deprecated, mapped to onSurface

    error: _error,
    onError: Colors.white,
  );

  // --- نظام الخطوط (Typography) ---
  static const TextTheme _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: -0.5),
    displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
    displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),

    headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: _onSurface),
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _onSurface),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _onSurface),

    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: _onBackground),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: _onBackground),

    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5, color: Colors.grey),
  );

  // --- الثيم الرئيسي (ThemeData) ---
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _colorScheme,
    scaffoldBackgroundColor: _background,
    textTheme: _textTheme,

    // 1. شريط التطبيق (AppBar)
    appBarTheme: AppBarTheme(
      backgroundColor: _surface,
      elevation: 0,
      scrolledUnderElevation: 4, // تأثير عند التمرير
      centerTitle: true,
      titleTextStyle: _textTheme.titleLarge,
      iconTheme: const IconThemeData(color: _onSurface),
    ),

    // 2. البطاقات (Cards)
    cardTheme: CardThemeData(
      color: _surface,
      elevation: 4,
      shadowColor: Colors.black45,
      surfaceTintColor: _primary.withValues(alpha: 0.05),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.05), width: 1),
      ),
    ),

    // 3. حقول الإدخال (Input/TextFields)
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.0),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.0),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.0),
        borderSide: const BorderSide(color: _primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.0),
        borderSide: const BorderSide(color: _error, width: 1.5),
      ),
      labelStyle: TextStyle(color: _onSurface.withValues(alpha: 0.7)),
      hintStyle: TextStyle(color: _onSurface.withValues(alpha: 0.4)),
      prefixIconColor: _onSurface.withValues(alpha: 0.6),
      suffixIconColor: _onSurface.withValues(alpha: 0.6),
    ),

    // 4. الأزرار الرئيسية (ElevatedButton)
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: _primary.withValues(alpha: 0.4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.0),
        ),
        textStyle: _textTheme.labelLarge,
      ),
    ),

    // 5. الأزرار الفرعية (OutlinedButton)
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _primary,
        side: const BorderSide(color: _primary, width: 1.5),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.0),
        ),
        textStyle: _textTheme.labelLarge,
      ),
    ),

    // 6. أزرار النصوص (TextButton)
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: _secondary,
        textStyle: _textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
    ),

    // 7. الزر العائم (FAB)
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: _primary,
      foregroundColor: Colors.white,
      elevation: 8,
      focusElevation: 10,
      splashColor: _primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      largeSizeConstraints: const BoxConstraints.tightFor(width: 65, height: 65),
    ),

    // 8. شريط التنقل السفلي (NavigationBar - Material 3)
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: _surface,
      height: 70,
      elevation: 2,
      indicatorColor: _primary.withValues(alpha: 0.2), // لون خلفية الأيقونة المحددة
      labelTextStyle: WidgetStateProperty.all(
         const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _onSurface),
      ),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: _primary, size: 26);
        }
        return const IconThemeData(color: Colors.grey, size: 24);
      }),
    ),

    // 9. النوافذ المنبثقة (Dialogs)
    dialogTheme: DialogThemeData(
      backgroundColor: _surface,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
      titleTextStyle: _textTheme.titleLarge,
      contentTextStyle: _textTheme.bodyMedium,
    ),

    // 10. القوائم السفلية (Bottom Sheets)
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surface,
      modalBackgroundColor: _surface,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.0)),
      ),
    ),

    // 11. عناصر القائمة (ListTiles)
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      iconColor: _onSurface.withValues(alpha: 0.8),
      textColor: _onSurface,
      tileColor: Colors.transparent,
      selectedColor: _primary,
      selectedTileColor: _primary.withValues(alpha: 0.1),
    ),

    // 12. الفواصل (Dividers)
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      thickness: 1,
      space: 1,
    ),

    // 13. رسائل التنبيه (SnackBar)
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _surfaceVariant,
      contentTextStyle: const TextStyle(color: _onSurface, fontWeight: FontWeight.w500),
      actionTextColor: _secondary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 6,
    ),
  );
}
