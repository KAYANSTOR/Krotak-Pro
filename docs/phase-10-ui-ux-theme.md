# Phase 10 — UI/UX + Dark/Light Improvements

**تاريخ:** 2026-09-13

## الهدف

تحسين التباين والمظهر في الوضعين الفاتح والداكن، ودعم اتباع إعداد الجهاز، وإزالة الخلفيات البيضاء الثابتة في الأوراق السفلية وبطاقات الإعدادات التي كانت تكسر الوضع الداكن.

## ما تم تنفيذه

- `ThemePreference`: قيم `light` / `dark` / `system` مع تحويل إلى `ThemeMode`.
- التحميل من `SettingKeys.themeMode` عند الإقلاع يدعم الثلاثة أوضاع.
- بطاقة إعداد `SettingsThemeModeCard` بـ SegmentedButton بدل مفتاح ثنائي فقط.
- بطاقات الإعدادات والمبيعات والأوراق السفلية تستخدم `ColorScheme.surface` و`outlineVariant`.
- حالة التعطيل للتحكم في المظهر عبر `Opacity` + `AbsorbPointer`.
- القيمة الافتراضية الجديدة: `system`.
- اختبارات: `test/domain/theme_preference_test.dart`.

## حدود المرحلة

- لم تُعد كتابة كل الشاشات بكسل مقابل مرجع Kotlin.
- قياس التباين على جهاز Android حقيقي ما زال مطلوبًا.

## بوابة التحقق

```text
dart analyze lib test
flutter test
```
