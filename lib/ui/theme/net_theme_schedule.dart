import 'dart:async';

import 'package:flutter/material.dart';

/// نظام مظهر NET: نهار / ليل / تلقائي (7م → داكن، 7ص → فاتح).
///
/// القيم تُخزن في إعداد `theme_mode` الموجود: `light` / `dark` / `auto`.
/// قيمة `system` القديمة تُقرأ كـ`light` للتوافق مع الإصدارات السابقة.
abstract final class NetThemeSchedule {
  /// ساعة بدء الوضع الداكن التلقائي (7 مساءً).
  static const int darkStartHour = 19;

  /// ساعة بدء الوضع الفاتح التلقائي (7 صباحًا).
  static const int lightStartHour = 7;

  /// هل الوقت الحالي داخل نطاق الداكن التلقائي (7م → 7ص).
  static bool isDarkTimeNow(DateTime now) => now.hour >= darkStartHour || now.hour < lightStartHour;

  /// يحوّل القيمة المخزنة إلى [NetThemeMode] مع توافق `system`.
  static NetThemeMode parse(String? raw) {
    switch ((raw ?? NetThemeMode.light.name).trim().toLowerCase()) {
      case 'dark':
        return NetThemeMode.dark;
      case 'auto':
        return NetThemeMode.auto;
      case 'system':
      case 'light':
      default:
        return NetThemeMode.light;
    }
  }

  /// القيمة المخزنة للوضع.
  static String encode(NetThemeMode mode) => mode.name;

  /// يحسم [ThemeMode] الفعلي وفق الوقت عند الوضع التلقائي.
  static ThemeMode resolve(NetThemeMode mode, DateTime now) => switch (mode) {
        NetThemeMode.light => ThemeMode.light,
        NetThemeMode.dark => ThemeMode.dark,
        NetThemeMode.auto =>
          isDarkTimeNow(now) ? ThemeMode.dark : ThemeMode.light,
      };

  /// وصف عربي مختصر لكل وضع.
  static String label(NetThemeMode mode) => switch (mode) {
        NetThemeMode.light => 'نهاري',
        NetThemeMode.dark => 'ليلي',
        NetThemeMode.auto => 'تلقائي',
      };

  /// تلميح عربي لكل وضع.
  static String hint(NetThemeMode mode) => switch (mode) {
        NetThemeMode.light => 'فاتح دائمًا — مناسب للنهار',
        NetThemeMode.dark => 'داكن دائمًا — مريح للعين ليلًا',
        NetThemeMode.auto =>
          'داكن تلقائيًا من 7 مساءً إلى 7 صباحًا، وفاتح بقية اليوم',
      };
}

/// أوضاع المظهر الثلاثة المعتمدة في NET.
enum NetThemeMode { light, dark, auto }

/// حامل القيمة الخام لوضع المظهر المحفوظ — طبقة عرض فقط.
///
/// تحدّثه شاشة الإعدادات بعد الحفظ، فيستدعي [onRawChanged] ليُعيد الحسم
/// الفوري في الوضع التلقائي دون الحاجة لتمرير مراجع بين الشاشات وmain.dart.
abstract final class NetThemeRawCache {
  static String _raw = NetThemeMode.light.name;

  static String get raw => _raw;

  static set raw(String value) {
    _raw = value;
    onRawChanged?.call(value);
  }

  /// يضبطه NetApp عند الإقلاع: الحسم الفوري لأي تغيير لاحق.
  static void Function(String raw)? onRawChanged;
}

/// مؤقّت خفيف يوقظ الوضع التلقائي عند تغيّر النهار/الليل أثناء التشغيل.
final class NetThemeAutoTicker {
  NetThemeAutoTicker(this._onTick);

  final void Function(DateTime now) _onTick;
  Timer? _timer;

  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      _onTick(DateTime.now());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
