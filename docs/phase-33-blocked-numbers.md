# مرحلة 33 — الأرقام المحظورة

**التاريخ:** 2026-09-20  
**الأصل:** البند 6 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

شاشة مستقلة للأرقام المحظورة + منع معالجة أي رسالة أو إيداع من رقم محظور قبل التحليل.

## القواعد

| الحالة | السلوك |
|---|---|
| المُرسِل محظور | رفض قبل `parse` — لا إيداع |
| رقم محظور في جسم الرسالة | نفس الرفض قبل التحليل |
| بعد التحليل المعرّف محظور | دفاع ثانٍ: رفض `blacklisted` |
| نفس الرقم بصيغ مختلفة | تطبيع `PhoneNormalizer` |

## الملفات

- `lib/domain/services/local_blocked_number_service.dart`
- `lib/ui/screens/settings/blocked_numbers_screen.dart`
- `lib/domain/entities/setting.dart` — `SettingKeys.blockedPhones`
- `lib/domain/services/unified_payment_event_engine.dart`
- `test/services/blocked_number_service_test.dart`
