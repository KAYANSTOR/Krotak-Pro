# تقرير تحديث Dashboard والثيم

**الأساس:** `d23847a` — merge: synchronize local P0 and P1 implementation

## التحقق

```text
dart analyze lib test → No issues found!
flutter test          → All tests passed! (45)
```

## الملفات

- `pubspec.yaml` — flex_color_scheme
- `lib/ui/theme/net_semantic_colors.dart` — ThemeExtension
- `lib/ui/theme/net_theme.dart` — FlexColorScheme light/dark
- `lib/ui/theme/kayan_theme.dart` — تفويض إلى NET themes
- `lib/ui/screens/dashboard_screen.dart` — أقسام مُعاد هيكلتها
- `lib/ui/widgets/net/*` — مكوّنات مشتركة

## مصادر البيانات

licenseService, smsBridge, customers+balanceService, cards.listByStatus, sales.listCompletedBetween, transactions.listRecent — بدون Mock.

## حالات الواجهة

Loading / Error / Empty / Success + Alert شرطي + SafeArea + RefreshIndicator + RTL عبر HomeShell + Light/Dark عبر ThemeMode.system.

## مؤجّل

مطابقة بكسلية للمرجع البصري، تبديل تبويب HomeShell من داخل البطاقة، Post-v1.
