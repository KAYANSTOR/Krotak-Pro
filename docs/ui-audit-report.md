# تقرير مراجعة واجهات Flutter مقابل Kotlin

**Commit المراجع:** `82ed9f028ca47a915d75f0849b0b77cc873b6df4` (main)
**مرجع Kotlin:** `kayan-android-kotlan` @ `1e26933`
**تاريخ المراجعة:** 2026-09-11

## التحقق

```text
dart analyze lib test  → No issues found!
flutter test           → All tests passed! (41)
```

## نسبة الإنجاز الفعلية للواجهات

| التصنيف | تقدير |
|---|---|
| منفذة ومربوطة بالكامل | **0%** |
| منفذة جزئيًا + ربط محدود | ~23% من الشاشات الرئيسية |
| غير منفذة | ~77% |
| **إنجاز سلوكي إجمالي** | **≈ 12–18%** |

## شاشات Flutter الحالية

| Kotlin | Flutter | بصري | Domain | حالات L/E/E/S | ملاحظات |
|---|---|---|---|---|---|
| MainDashboard | DashboardScreen | جزئي | ترخيص+SMS فقط؛ أرقام 0 | جزئي | لا BottomSheets |
| Accounts | CustomersScreen | نموذج إنشاء | create فقط | busy+نص | لا قائمة |
| Cards/Categories | InventoryScreen | نماذج | فئة+استيراد | busy+نص | لا جدول |
| Reports* | ReportsScreen | placeholder | لا | لا | كان يفتح Messages خطأ |
| Offers | OffersScreen | placeholder | لا | لا | كان يفتح Settings خطأ |
| Settings+فرعية | SettingsScreen | زرّان | license+backup | busy+نص | ناقص |
| Activation/Help/Wallets/Templates/Reports فرعية | — | — | — | — | غير منفذة |
| SMS محاكاة | MessagesScreen | أداة dev | smsHandler | busy+نص | ليست شاشة إنتاج |

## إصلاح بعد المراجعة

- HomeShell: reports→ReportsScreen، offers→OffersScreen (صادقة).
- Settings عبر أيقونة من Dashboard.
- LocalAccountMergeService + اختبارات.
