# مرحلة 98 — رسالة سداد السلفني الكاملة

**التاريخ:** 2026-10-10  
**الأصل:** قرارات المالك في `docs/owner-decisions-2026-10-09.md` §1، والمتبقي من `docs/ci-verification-and-branch-unification-2026-10-09.md`.

## المطلوب

بعد سداد السلفة من الإيداع (كامل أو جزئي)، تُرسل رسالة للعميل تعرض:

- مبلغ الإيداع
- المبلغ المخصوم للسلفة
- الفائض المضاف للرصيد
- الرصيد الجديد

القيم من نتيجة المعاملة الفعلية، والعملية idempotent.

## التنفيذ

- `LocalTransferProcessor._notifySalafniSettlement` يُستدعى بعد النجاح في حالتي السداد الكامل والجزئي.
- يستخدم قالب `SettingKeys.salafniSettledTemplate` مع المتغيرات `{amount}` `{paid}` `{surplus}` `{balance}` `{CURRENCY}`.
- النص الافتراضي مطابق للقرار في `SettingDefaults.salafniSettlementNoticeTemplate`.
- يسجل Audit `salafni_settlement_notified` أو فشل الإرسال، ولا يعيد الإرسال إذا سبق النجاح.
- لا يفشل المسار المالي إذا تعذر الإرسال.

## الاختبارات

يُغطى المسار المالي في `test/services/deposit_debt_surplus_test.dart` و`salafni_settlement_test.dart`. يُوصى بإضافة تأكيد على وجود التدقيق `salafni_settlement_notified` في اختبار تكامل لاحق.

## خارج النطاق

- تحسين الأداء الملموس (يتطلب هدف جهاز من المالك).
- فصل تنبيه المخزون الداخلي عن رسالة العميل.
- تدقيق كامل لجميع القوالب وربط قالب سداد الدين العام.
