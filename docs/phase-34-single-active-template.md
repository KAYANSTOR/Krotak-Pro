# مرحلة 34 — قالب افتراضي واحد فعّال لكل مجموعة

**التاريخ:** 2026-09-20  
**الأصل:** البند 7 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

تعيين قالب تحويل واحد نشط/افتراضي داخل كل مجموعة (محفظة أو نقطة بيع أو مرسل)، بدل تفعيل عدة قوالب معاً في نفس النطاق.

## القواعد

| الحدث | السلوك |
|---|---|
| تفعيل قالب | يُحفظ نشطاً وتُوقف كل القوالب الأخرى في نفس المجموعة |
| إيقاف قالب | يُحفظ متوقفاً دون فرض بديل تلقائي |
| مجموعة نقطة بيع | `pos:{posId}` تتقدّم على المحفظة |
| مجموعة محفظة | `wallet:{walletId}` |
| مجموعة مرسل | `sender:{senderCode}` بعد التطبيع لحروف صغيرة |
| بلا نطاق | `unscoped` |

## الملفات

- `lib/domain/services/local_transfer_template_activation_service.dart`
- `lib/ui/screens/settings/templates_screen.dart`
- `lib/ui/screens/settings/template_wizard_screen.dart`
- `test/services/transfer_template_activation_test.dart`
