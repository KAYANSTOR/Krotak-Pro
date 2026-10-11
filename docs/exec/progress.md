# متابعة التنفيذ — Krotak Pro

**الفرع:** `development/full-completion` · **المرجع:** `docs/خطة-تنفيذ-Krotak-Pro-النهائية-2026-10-10.md`

> **دليل CI الأحدث:** تشغيل `38104471175` — `Flutter analyze` ✓ و«Test (full suite)» ✓ (كل اختبارات Dart، بما فيها اختبار WP-4 بعد إصلاحه).

| الحزمة | الحالة | commit | اختبارات الإثبات | ملاحظات |
|---|---|---|---|---|
| المرحلة 0 — خط الأساس | منجز | `71555e0` | — | `docs/exec/baseline.md`؛ لا فرع جديد (سياسة AGENTS.md) |
| WP-1 حذف بطاقة «إدارة الكروت والفئات» | منجز | `e9a5fbe` | `test/widget/wp1_settings_no_cards_card_test.dart` | CI `38082636926` ✓ |
| WP-2 حذف إشعار «حساب دائم» | منجز | `1e64a8e` | `test/widget/wp2_account_auth_no_trial_card_test.dart` | لم يُمس `isTrial`/الجلسة |
| الجرد المبكر للأزرار (5.1) | منجز | — | `tools/audit_interactive.py` | الشرح في `docs/audit/ui-audit-report.md` |
| WP-S1 `VisibleStorageService` | منجز | `ff30fe3`,`c7e4379`,`0273bd9` | `test/platform/visible_storage_bridge_test.dart` + `VisibleStorageTest.kt` | قناة `com.kayan.net/storage` + MediaStore |
| WP-S3 `UserFacingErrorLocalizer` | منجز | `95ffd1f`,`c7e4379` | `test/ui/user_facing_error_localizer_test.dart` | حارس مصدري: كل `code:` له نص عربي بلا لاتيني |
| WP-S2 `TemplateVariableRegistry` | منجز | `67de478` | `test/services/template_variable_registry_test.dart` | + `docs/exec/template-variables-inventory.md` |
| WP-S4 ترحيل DB إلى 6 + سجل الاستيراد | منجز | (كود في `app_database.dart`+`local_card_import_log_repository.dart`) | `test/data_migration_test.dart` + `test/services/card_import_log_repository_test.dart` | ترقية إضافية فقط (لا تمس بيانات) |
| WP-3 بطاقة صيانة واحدة + تصدير/تنظيف | منجز | `254a5a8`,`40c9b1f` | `test/services/ledger_csv_export_service_test.dart` + `test/widget/maintenance_hub_screen_test.dart` | REINDEX فعلي + قياس الحجم + تصدير CSV فعلي (BOM) |
| WP-4 نسخ احتياطي ظاهر | **منجز** | `b5edca6`,`ef40986` | `test/widget/backup_visible_copy_test.dart` | **أُصلح سبب فشل CI الجذري**: الحلقة كانت `pump()` بلا مدة (لا تُقدّم الساعة الوهمية) — التفصيل في `decisions-log.md` |
| WP-5 استيراد الكروت + إدارة الملفات | منجز | (كود) | `test/widget/inventory_import_logs_screen_test.dart` + `card_import_*_test.dart` | يعتمد على WP-S1/S4 |
| WP-6 المتغيرات بلا تكرار | منجز | (كود) | `test/services/template_variable_registry_test.dart` + `outbound_template_contract_gate_test.dart` | سجل واحد + محقّق |
| WP-7 المعلقة والمرفوضة بالعربية | منجز | `51358e1`+ | `test/ui/ui_no_raw_errors_test.dart` | حارس مصدري لـ`error.message/code` |
| WP-8 حفظ/مشاركة صورة الإشعار | منجز | `51358e1` | `test/widget/transaction_receipt_image_test.dart` | `TransactionReceiptCard` + `ReceiptImageService` (PNG) |
| WP-9 توقف التطبيق في الخلفية | منجز (الكود+الأدلة) | `38094241525` | `test/domain/background_diagnostics_test.dart` + `ProcessExitReasonCodesTest.kt` | `specialUse`+`onTimeout`+إعادة تشغيل؛ معيار 12 ساعة **ينتظر تحقق جهاز** |
| WP-10 اتساق المحافظ (P2) | منجز | `6518474` | `test/services/wallet_catalog_strict_test.dart` + `wallet_toggle_test.dart` | إصلاح القوالب النظامية + منع التفعيل الجماعي للمسودات |
| الجرد النهائي + مصفوفة الأزرار (5.4) | منجز | (هذا الدفعة) | `tools/audit_buttons_matrix.py` + `test/audit/buttons_matrix_coverage_test.dart` | `docs/audit/buttons-matrix-2026-10-10.csv` (865 صفًا، بلا حالة مجهولة) |
| CI كامل + APK + التقرير النهائي | قيد | | | يُغلق بعد آخر تشغيل CI |
