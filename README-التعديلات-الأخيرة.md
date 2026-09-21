# التعديلان الأخيران فقط (فوق main الحالي)

هذا الأرشيف **ليس** المشروع كاملاً. يضم فقط ملفات التعديلين اللذين لم يُدفعا مع المراحل السابقة.

افك الضغط **فوق جذر** مستودع `net-flutter` (نفس مستوى `pubspec.yaml`).

```bash
cd /مسار/net-flutter
git checkout main   # أو الفرع الذي دفعت عليه سابقاً
unzip -o krotak-last-two-fixes-only.zip
flutter pub get
flutter analyze
flutter test test/domain/outbound_template_gate_test.dart
git add -A
git status
git commit -m "fix(ui+outbound): wallet notifications, import, templates activate, outbound gate"
git push
```

---

## التعديل 1 — واجهة وقوالب

| الملف | ماذا تغيّر |
|--------|------------|
| `lib/ui/screens/settings/wallet_notification_settings_screen.dart` | شاشة إشعارات المحافظ كاملة (إذن، مصادر، مزامنة، إضافة/إيقاف) بدل هيكل فارغ |
| `lib/ui/screens/inventory_screen.dart` | زر «استيراد من ملف» → مسار ملف فقط؛ زر `+` للإضافة اليدوية |
| `lib/ui/screens/inventory_sheets.dart` | وضع `fileOnly` + تنبيه صيغ PDF/XLSX/CSV |
| `lib/ui/screens/settings/outbound_message_templates_screen.dart` | أزرار المتغيرات بالعربية + تفعيل/إيقاف كل قالب صادر |
| `lib/ui/screens/settings/templates_screen.dart` | إصلاح «مسودة» الخاطئ لقوالب POS حتى يعمل مفتاح التفعيل |
| `lib/domain/services/default_pos_templates_seeder.dart` | إعادة تفعيل القوالب المعيارية لنقطة البيع إن وُجدت متوقفة |
| `lib/domain/entities/setting.dart` | مفتاح `outbound_templates_disabled` |
| `docs/phase-ui-fixes-wallet-import-templates.md` | توثيق |

---

## التعديل 2 — بوابة القوالب الصادرة

| الملف | ماذا تغيّر |
|--------|------------|
| `lib/domain/services/outbound_template_gate.dart` | **جديد** — يمنع إرسال أي قالب موقوف |
| `lib/domain/services/pos_order_message_renderer.dart` | يمر عبر البوابة |
| `lib/domain/services/local_advance_service.dart` | سلفني عبر البوابة |
| `lib/domain/services/local_pos_balance_request_service.dart` | رد رصيد عبر البوابة |
| `lib/domain/services/local_promotion_fulfillment_service.dart` | مكافأة عرض عبر البوابة |
| `lib/domain/services/local_pos_daily_summary_service.dart` | ملخص يومي عبر البوابة |
| `lib/domain/services/local_pos_auto_settlement_service.dart` | تسوية عبر البوابة |
| `lib/domain/services/local_low_stock_alert_service.dart` | تنبيه مخزون عبر البوابة |
| `lib/domain/services/message_delivery_worker.dart` | إعادة إرسال الكرت عبر البوابة |
| `lib/domain/services/manual_sale_runner.dart` | بيع يدوي عبر البوابة |
| `lib/domain/services/local_sale_service.dart` | حقن `settings` للبيع اليدوي |
| `lib/domain/services/local_transfer_processor.dart` | تسليم كرت التحويل عبر البوابة |
| `lib/application/app_container_impl.dart` | ربط `settings` بالعامل وخدمة البيع |
| `test/domain/outbound_template_gate_test.dart` | اختبارات البوابة |
| `docs/outbound-template-gate-wiring.md` | توثيق |

**السلوك:** إيقاف قالب من شاشة «قوالب الرسائل» → لا SMS من ذلك القالب. البيع/الكرت الملتزم لا يُلغى.

---

## ملاحظة

لا حاجة لتعديل `pubspec.yaml` في هذا الأرشيف (لا حزم جديدة).
