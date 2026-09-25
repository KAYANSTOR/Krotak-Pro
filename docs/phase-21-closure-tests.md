# المرحلة 21 — اختبارات الإغلاق التجاري

**التاريخ:** 2026-09-25  
**الفرع:** `development/full-completion`  
**الأصل:** الخطة الشاملة §21  
**الحالة:** منفّذة في المستودع (تغطية موجودة + سد فجوات رفض الاستيراد)

## النطاق

- جرد اختبارات Unit / Domain / Integration / Performance مقابل قائمة §21.
- إضافة اختبارات رفض ملفات الاستيراد المحظورة: TXT، صور، ملفات مزوّرة بالامتداد أو بالتوقيع.
- توثيق أين يعيش كل بند في `test/`.

## خارج النطاق

- تشغيل قائمة الجهاز الحقيقي.
- GitHub Secrets وبناء التوقيع.
- فرع `licensing`.
- اختبارات Widget لورقة الاستيراد الثلاثية على جهاز.

## مصفوفة التغطية

| بند §21 | ملف الاختبار |
|------|--------|
| اقتراح أرقام العملاء | `test/domain/customer_phone_suggestion_test.dart`, `test/services/customer_phone_suggestion_test.dart`, `test/services/customer_phone_suggestion_drift_test.dart` |
| POS سطر / متعدد / فئات / تسليم عميل / 111 | `test/services/pos_inbound_three_template_test.dart`, `test/services/pos_multi_card_parse_test.dart`, `test/domain/pos_commercial_phase1_test.dart` |
| سقف الدين | `test/domain/pos_credit_limit_test.dart` |
| حد طلبات الرصيد | `test/domain/pos_commercial_phase1_test.dart` |
| سلفني للعملاء فقط | `test/services/salafni_foundation_test.dart` |
| Idempotency + تكرار SMS | `test/services/sale_idempotency_test.dart`, `test/services/core_business_flow_integration_test.dart` |
| تسليم عدة كروت | `test/services/pos_multi_card_parse_test.dart` |
| فلترة/حذف المباعة | `test/domain/sold_cards_phase4_test.dart` |
| استيراد Excel/PDF/CSV | `test/services/card_import_preview_test.dart`, `test/services/card_import_parser_test.dart` |
| رفض TXT / صور / ملفات مزوّرة | `test/services/card_import_preview_test.dart` (دفعة المرحلة 21) |
| تعديل رصيد العميل | `test/domain/customer_account_phase3_test.dart` |
| مسار وارد كامل + استرداد | `test/services/core_business_flow_integration_test.dart`, `test/services/core_business_flow_recovery_test.dart` |
| قياس زمن المسار | `test/domain/message_pipeline_latency_complete_test.dart` |
| تصدير كشف العميل | `test/widget/customer_statement_export_test.dart` |

## معيار الإغلاق لهذه المرحلة

الاختبارات أعلاه موجودة في الفرع وتغطي قائمة §21 على مستوى الكود. التحقق الميداني يبقى لدى المالك.
