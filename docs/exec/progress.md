# متابعة التنفيذ — Krotak Pro

**الفرع:** `development/full-completion` · **المرجع:** `docs/خطة-تنفيذ-Krotak-Pro-النهائية-2026-10-10.md`

| الحزمة | الحالة | commit | اختبارات الإثبات | ملاحظات |
|---|---|---|---|---|
| المرحلة 0 — خط الأساس | منجز | `71555e0` | — | `docs/exec/baseline.md`؛ لا فرع جديد (سياسة AGENTS.md)؛ لا دمج `development/next` (غير موجود) |
| WP-1 حذف بطاقة «إدارة الكروت والفئات» | منجز | `e9a5fbe` | `test/widget/wp1_settings_no_cards_card_test.dart` | CI `38082636926`: analyze ✓ + كل الاختبارات ✓ + اختبارات Android ✓ |
| WP-2 حذف إشعار «حساب دائم» | منجز | `1e64a8e` | `test/widget/wp2_account_auth_no_trial_card_test.dart` | نفس التشغيل؛ `_trialCard` والاستدعاء والمتغير `net` أُزيلت، ولم يُمس `isTrial`/الجلسة |
| الجرد المبكر للأزرار (5.1 الطبقة 1) | منجز | — | `tools/audit_interactive.py` | `rows=851`, `callbacks=522`, `elements=374`, `files=79` — الشرح في `docs/audit/ui-audit-report.md` |
| WP-S1 `VisibleStorageService` | منجز | `ff30fe3`,`c7e4379`,`0273bd9` | `test/platform/visible_storage_bridge_test.dart` + `android/.../VisibleStorageTest.kt` | قناة `com.kayan.net/storage` + MediaStore + `WRITE_EXTERNAL_STORAGE maxSdkVersion=28` |
| WP-S3 `UserFacingErrorLocalizer` | منجز | `95ffd1f`,`c7e4379` | `test/ui/user_facing_error_localizer_test.dart` | حارس مصدري: كل `code:` في `lib/**` له نص عربي بلا لاتيني |
| WP-S2 `TemplateVariableRegistry` | قيد CI | `67de478` | `test/services/template_variable_registry_test.dart` | + `docs/exec/template-variables-inventory.md` (جرد من الكود) |
| WP-S4 ترحيل DB إلى 6 | قيد | | | |
| WP-3 بطاقة صيانة واحدة | قيد | | | يعتمد على WP-S1 |
| WP-4 نسخ احتياطي ظاهر | قيد | | | يعتمد على WP-S1 |
| WP-5 استيراد الكروت + إدارة الملفات | قيد | | | يعتمد على WP-S1/S4 |
| WP-6 المتغيرات بلا تكرار | قيد | | | يعتمد على WP-S2 |
| WP-7 المعلقة والمرفوضة بالعربية | قيد | | | يعتمد على WP-S3 |
| WP-8 حفظ/مشاركة صورة الإشعار | قيد | | | يعتمد على WP-S1 |
| WP-9 توقف التطبيق في الخلفية | قيد | | | الدليل أولاً |
| WP-10 اتساق المحافظ (P2) | قيد | | | |
| الجرد النهائي + مصفوفة الأزرار (5.4) | قيد | | | بعد استقرار الواجهات |
| CI كامل + APK + التقرير النهائي + PR | قيد | | | |
