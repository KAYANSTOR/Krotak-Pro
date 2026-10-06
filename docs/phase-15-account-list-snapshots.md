# المرحلة 15 — قائمة الحسابات باستعلامات مجمّعة

**التاريخ:** 2026-09-24  
**الحالة:** منفّذة في الكود (عقد + مستودع Drift + شاشة الحسابات + اختبارات)  
**الأساس:** بند و9 في تدقيق 21 أيلول بعد إغلاق المراحل 9–14.

## المشكلة

شاشة الحسابات كانت تحمّل كل العملاء ثم تستدعي `getBalance` و`listIdentifiers` لكل صف (دفعات من 20). مع آلاف الحسابات يصبح المسار N+1 ويبطئ الفتح والترتيب والفلاتر.

## النطاق

- `CustomerRepository.listAccountSnapshots` يعيد الصفوف مع الرصيد والهاتف في ثلاثة استعلامات فقط.
- شاشة الحسابات تبني البطاقات من اللقطة مباشرة.

## التنفيذ

- الكيان: `CustomerAccountSnapshot` في `lib/domain/entities/customer.dart`.
- العقد: `CustomerRepository.listAccountSnapshots`.
- Drift: ثلاثة مسارات — `search` للعملاء، قراءة كل الهويات بـ `IN`، و`SUM` موجّه من `transactions`.
- الواجهة: `CustomersScreen._load` لم يعد يستدعي `getBalance`/`listIdentifiers` لكل صف.
