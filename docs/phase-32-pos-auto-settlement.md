# مرحلة 32 — التسوية التلقائية لنقاط البيع

**التاريخ:** 2026-09-20  
**الأصل:** البند 5 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md) وخطة Phase 6.

## الهدف

عند ورود حوالة محفظة يطابق معرف المستفيد نقطة بيع نشطة، وكانت التسوية التلقائية مفعّلة:

1. لا يُباع كرت.
2. يُقيَّد `TransactionType.deposit` بمرجع `pos-settle:{posId}:{paymentRef}`.
3. المديونية المتبقية = `max(0, −رصيد الدفتر المكتمل)`.
4. يُكتب Audit `pos_auto_settled`.
5. تُرسل رسالة تأكيد إلى `notifyPhone` بالقوالب `{SETTLEMENT_AMOUNT}` و`{REMAINING_BALANCE}` (مع `{pos}` و`{amount}` و`{remaining}`).

## القواعد

| الحالة | السلوك |
|---|---|
| المفتاح `auto_pos_settlement_enabled` = false | يُترك المسار لمحرّك بيع الكرت |
| القالب المرتبط بـ `posId` (طلب نقطة بيع) | يُتخطى — ليس حوالة محفظة |
| لا تطابق لمعرف نقطة بيع | يُتخطى |
| تطابق + تفعيل | إيداع + تدقيق + SMS |
| نفس المرجع | Idempotent عبر `balances.credit` |
| مبلغ أكبر من الدين | الرصيد يصبح موجباً (دفع مقدّم) والمبلغ المتبقي في الرسالة = 0 |

## الملفات

- `lib/domain/services/local_pos_auto_settlement_service.dart`
- `lib/domain/services/local_transfer_processor.dart` (حقن مبكر قبل التعرف على العميل)
- `lib/application/app_container_impl.dart`
- `test/services/pos_auto_settlement_test.dart`
