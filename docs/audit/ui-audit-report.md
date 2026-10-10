# تقرير فحص الأزرار والواجهات — Krotak Pro

**المرجع:** القسم 5 من `docs/خطة-تنفيذ-Krotak-Pro-النهائية-2026-10-10.md`
**التاريخ:** 2026-10-10 · **الفرع:** `development/full-completion`

## 1. الطبقة 1 — الجرد الآلي (منجز)

الأداة: `tools/audit_interactive.py` · المخرج: `docs/audit/interactive-inventory.csv`

| المقياس | العدد |
|---|---|
| صفوف الجرد | **851** |
| صفوف بمعالج (callback) | **522** |
| صفوف بعنصر تفاعلي معروف | **374** |
| ملفات واجهة فيها عناصر تفاعلية | **79** |

### فرق الأرقام عن توقّع الخطة (405 + 78)
الخطة اعتمدت مسحًا ساكنًا ضيقًا (`onPressed/onTap` + 78 أيقونة إجراء) على 104 ملف واجهة.
السكربت هنا يشمَل **كل** المعالجات (`onChanged`, `onSubmitted`, `onRefresh`, `onSelected`,
`onDismissed`, `onLongPress`, `onDoubleTap`, `onFieldSubmitted`) و**كل** العناصر التفاعلية
(`IconButton`, `NetHeaderAction`, `FloatingActionButton`, `ListTile`, `Switch/Checkbox/Radio`,
`PopupMenuItem`, `SettingsGroupNavRow`, `TextButton/FilledButton/ElevatedButton/OutlinedButton`,
`InkWell/GestureDetector`, `Dismissible`, `Tab`, حقول الإدخال). لذلك العدد أعلى، وهذا مقصود:
الهدف حصر **كل** عنصر تفاعلي حتى لا يبقى عنصر بحالة «مجهول» في المصفوفة (القسم 5.4).

## 2. الطبقة 2 — التصنيف (A..G)

قيد التنفيذ — تُبنى على الجرد أعلاه، والمشتبهات المعروفة مسبقًا (القسم 5.3) هي نقطة البداية:

| الملف:السطر | العنصر | الفئة | الحالة |
|---|---|---|---|
| `export_ledger_screen.dart:75` | أيقونة النسخ (تصدير = نسخ نص + حد 500) | D/F | ينتظر WP-3 |
| `sold_cards_sheet.dart:227` | تصدير الكروت المباعة إلى الحافظة | D | ينتظر WP-3/WP-8 |
| `customer_statement_export.dart:80` | تصدير كشف العميل كنص | D | ينتظر WP-3/WP-8 |
| `net_transaction_detail_sheet.dart:138,155` | مشاركة/حفظ العملية كنص | F | ينتظر WP-8 |
| `deep_clean_screen.dart` | «تصفير السجلات» لا يحدث | F | ينتظر WP-3 |
| `inventory_screen.dart:343,376` | زر `+` و«استيراد من ملف» | F | ينتظر WP-5 |
| `settings_hub_screen.dart:331` | «إدارة الكروت والفئات» مكرّرة | G | **مُصلَح (WP-1)** |
| `local_maintenance_service.dart`, `local_backup_service.dart` | رسائل إنجليزية | E | ينتظر WP-3/WP-S3 |
| `outbound_message_templates_screen.dart` | أزرار المتغيرات مكررة وبأكواد | E/F | ينتظر WP-6 |
| `device_verification_screen.dart:77` | نسخ حزمة التشخيص | يتحقق في الطبقة 3 | — |

## 3. الطبقة 3 — تتبّع المسار وفحوص الربط

مطلوب آليًا:
1. **تطابق قنوات Dart/Kotlin**: استخراج كل `invokeMethod('x')` ومقارنتها بمعالجات `MainActivity.kt`
   على القنوات (`com.kayan.net/sms`, `alerts`, `notifications`, `diagnostics`, `keepalive`, **`storage`**).
2. **مفاتيح الإعدادات**: كل `SettingKeys.x` له قارئ فعلي.
3. **التنقل**: كل `Navigator.push(…Screen())` يشير لشاشة موجودة + كشف الشاشات اليتيمة.
4. **متغيرات القوالب**: كل متغير له حلّ فعلي (WP-6).

## 4. الطبقة 4 — اختبارات تفاعلية

نمط البناء المعتمد فعليًا: `AppContainer.bootstrap(databaseOverride: AppDatabase(NativeDatabase.memory()), backupDirectoryOverride: Directory('test-backups'))`
مغلّفًا بـ`AppScope(container: …)` (لا وجود لـ`AppContainer.forTesting()`).

## 5. الطبقة 5 — قائمة فحص الجهاز (D11)

تُسلَّم في التقرير النهائي: SMS، الإشعارات، المشاركة كصورة، الحفظ في المعرض،
ظهور النسخة في `Download/Krotak Pro/`، الاستعادة، الخلفية 12 ساعة.
