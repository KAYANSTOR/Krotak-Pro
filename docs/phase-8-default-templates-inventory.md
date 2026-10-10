# جرد القوالب المزروعة

> **ملاحظة تصحيح (2026-10-09):** هذا الملف كان يصف حالة مرحلة 8 ويحتوي وصفًا غير مطابق للواقع الحالي
> (خصوصًا صيغ جوالي: نمط واحد `استلمت مبلغ … رصيدك هو {ref}` لا «تحويل مشترك/رقم فقط/English»).
> الجرد المرجعي الحالي هو جدول القوالب الـ23 في `docs/phase-0-contracts-audit-2026-10-09.md` §2،
> وبوابة عقده في `test/services/outbound_template_contract_gate_test.dart`.

## 1) المحافظ المزروعة عند أول تشغيل

المصدر: `lib/domain/services/default_wallet_specs.dart` (الأسماء الرسمية) و
`lib/domain/services/default_wallet_templates_seeder.dart` (`default_wallet_templates_seeded_v4`).

| المحفظة | `Sender ID` الرسمي | عدد قوالب الاستقبال المزروعة |
|---|---|---|
| Jaib | `Jaib` | 4 (مشترك، رقم بديل، حساب، إنجليزي) |
| Jawali | `Jawali` | 1 |
| MFloos | `MFloos` | 1 |
| Floosak | `Floosak` | 3 |
| KuraimiLMB | `KuraimiLMB` | 1 |
| ONE Cash | `ONE Cash` | 4 |

قوالب الاستقبال تُعدَّل من معالج القالب/إدارة القوالب لكل محفظة، والزرع لا يكتب فوق تعديل المشغّل.
مطابقة `Sender ID` في `PaymentSourceGuard` مطابقة تامة (حالة الأحرف والمسافات) بحسب
`docs/wallet-deposit-definitions-2026-10-09.md`.

## 2) القوالب الصادرة

المصدر المركزي: `lib/domain/services/outbound_template_catalog.dart` (23 قالبًا)، والزرع في
`DefaultOutboundTemplatesSeeder` (`default_outbound_templates_seeded_v7`).

- قوالب سلفني: قبول / رفض / سداد، وكرت سلفني.
- قوالب إرسال الكروت: نقدي / آجل / هدية، مع الرجوع إلى `voucher_delivery_sms_template` إن غاب قالب النوع.
- قوالب الإيداع: `deposit_no_stock_template`، وقوالب POS وتقاريرها، وتنبيه نفاد المخزون.
- القالب الذي يعدّله المشغّل من الإعدادات هو المصدر الفعّال في الإرسال، والزرع قيمة بداية فقط.

## 3) واجهة المحافظ

شاشة `WalletsPosScreen` (بطاقات، مفتاح تفعيل، قائمة ⋮، ورقة تعديل، تبويب نقاط البيع).
