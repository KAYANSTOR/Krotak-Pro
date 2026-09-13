# Phase 6 — POS Ledger + Auto Settlement

## الحالة

🟡 منفذة في المستودع — بانتظار إغلاق بوابة CI والتحقق على جهاز Android حقيقي.

## الأساس التجاري

- نقطة البيع تُربط بحساب عميل في الدفتر المالي المشترك (لا دفتر ثانٍ).
- معرفات الدفع (هاتف / حساب / اسم) تُحفظ في سجل الربط `pos_accounts`.
- عند ورود حوالة يُطابق معرفها نقطة بيع نشطة، وكانت التسوية التلقائية مفعّلة:
  1. لا يُباع كرت.
  2. يُسجَّل `TransactionType.deposit` بمرجع `pos-settle:{posId}:{paymentRef}`.
  3. المديونية = `max(0, -رصيد الدفتر المكتمل)`.
  4. يُكتب Audit `pos_auto_settled`.
  5. تُرسل رسالة تأكيد بالمبلغ والمتبقي إن وُجد رقم إشعار.
- التسوية الجزئية مسموحة؛ المبلغ الزائد يحوّل الرصيد إلى موجب (رصيد مدفوع مقدماً).
- إعادة نفس المرجع Idempotent ولا تُنشئ حركة ثانية.
- نقطة بيع غير معروفة تترك المسار لمحرّك التحويل/الكرت المعتاد.

## الإعدادات

- `auto_pos_settlement_enabled` (افتراضي: true)
- `pos_accounts`
- `pos_settlement_template_success`
- `pos_settlement_template_failed`
- `pos_settlement_template_unknown`

## المتغيرات في القوالب

`{pos}` `{amount}` `{remaining}` `{reason}` `{identifier}`

## التحقق المطلوب قبل Production Ready

1. `dart analyze lib test`
2. `flutter analyze --no-fatal-infos`
3. `flutter test`
4. `flutter build apk --debug`
5. جهاز Android: إنشاء نقطة بيع بمعرف دفع، بيع على الحساب لإنشاء دين، حوالة جزئية ثم كاملة، ثم إعادة نفس الحوالة.
6. التأكد من عدم بيع كرت عند مطابقة POS ومن عدم تكرار الحركة.
