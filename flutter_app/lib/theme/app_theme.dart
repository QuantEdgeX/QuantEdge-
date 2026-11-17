import 'package:flutter/material.dart';

// Icon constants mapping Lucide icons to Material icons
class AppIcons {
  // Navigation
  static const IconData layoutDashboard = Icons.dashboard_rounded;
  static const IconData chartNoAxesColumn = Icons.bar_chart_rounded;
  static const IconData briefcase = Icons.business_center_rounded;
  static const IconData messageSquare = Icons.message_rounded;

  // General
  static const IconData info = Icons.info_rounded;
  static const IconData target = Icons.adjust_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData checkCircle2 = Icons.check_circle_rounded;
  static const IconData sparkles = Icons.stars_rounded;
  static const IconData award = Icons.emoji_events_rounded;
  static const IconData zap = Icons.flash_on_rounded;
  static const IconData bot = Icons.smart_toy_rounded;
  static const IconData plus = Icons.add_rounded;
  static const IconData send = Icons.send_rounded;
  static const IconData lock = Icons.lock_rounded;
  static const IconData sun = Icons.wb_sunny_rounded;
  static const IconData moon = Icons.nights_stay_rounded;
}

class AppColors {
  // Brand Emerald Colors
  static const emerald = Color(0xFF10B981);
  static const emeraldDark = Color(0xFF059669);
  static const emeraldLight = Color(0xFF34D399);

  // Status Colors
  static const amber = Color(0xFFF59E0B);
  static const rose = Color(0xFFF43F5E);
  static const blue = Color(0xFF3B82F6);

  // Surface & Background Colors
  static const darkBg = Color(0xFF080B14);
  static const darkSurface = Color(0xFF0F172A);
  static const darkCard = Color(0xFF1E293B);

  static const lightBg = Color(0xFFEAE8E0);
  static const lightSurface = Color(0xFFF9F8F3);
  static const lightCard = Colors.white;

  // Typography Colors
  static const lightTextPrimary = Color(0xFF1E293B);
  static const lightTextSecondary = Color(0xFF475569);
  static const lightTextMuted = Color(0xFF94A3B8);
  static const lightBorder = Color(0xFFE2E8F0);
}

class AppTheme {
  static ThemeData dark() {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: AppColors.darkBg,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.emerald,
        surface: AppColors.darkCard,
      ),
    );
  }

  static ThemeData light() {
    return ThemeData.light().copyWith(
      scaffoldBackgroundColor: AppColors.lightBg,
      colorScheme: const ColorScheme.light(
        primary: AppColors.emerald,
        surface: AppColors.lightCard,
      ),
    );
  }
}
