# مرحلة 32 — التسوية التلقائية لنقاط البيع

**التاريخ:** 2026-09-20  
**الأصل:** البند 5 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

عندما يصل إيداع محفظة لعميل مربوط بنقطة بيع نشطة، وكان مفتاح `autoPosSettlementEnabled` مفعّلاً، يُقيَّد المبلغ كتسوية دفتر (إيداع) **دون** حجز كرت أو بيع، ويُرسل SMS بنتيجة التسوية.

## القواعد

| الشرط | النتيجة |
|---|---|
| المفتاح OFF أو العميل ليس نقطة بيع | المسار التجاري السابق (بيع كرت) |
| نقطة بيع نشطة + المفتاح ON | إيداع بالمبلغ الوارد + رسالة معالجة |
| المرجع مكرر لنفس العميل والمبلغ | إعادة نفس الحركة (idempotent عبر `credit`) |
| فشل الإيداع | SMS فشل + حالة الرسالة `failed` |

قوالب الرد تدعم `{pos}` و`{amount}` و`{SETTLEMENT_AMOUNT}` و`{REMAINING_BALANCE}` و`{debt}` و`{reason}`.

الرصيد المتبقي يُحسب من دفتر الحركات المكتمل بعد الإيداع (دين سالب = مبيعات غير مسدّدة).

## الملفات

- `lib/domain/services/local_pos_auto_settlement.dart`
- `lib/domain/services/local_transfer_processor.dart`
- `lib/application/app_container_impl.dart`
- `lib/domain/entities/setting.dart`
- `test/services/pos_auto_settlement_test.dart`
