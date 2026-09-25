# المرحلة 17 — ربط شاشة الحسابات بلقطة Drift

**التاريخ:** 2026-09-25  
**الحالة:** منفّذة في الكود  
**الأساس:** المرحلة 16 نفّذت `listAccountSnapshots` في Drift والاختبار، وفيما `CustomersScreen` بقيت تستدعي `getBalance` و`listIdentifiers` لكل صف.

## النطاق

- `_load` في `CustomersScreen` يقرأ `CustomerRepository.listAccountSnapshots`.
- بناء `_AccountRow` من اللقطة دون حلقة N+1.
- إكمال عقد `listAccountSnapshots` في `InMemoryCustomerRepository` وfake محرك الرسائل حتى لا ينكسر التحليل.

## خارج النطاق

- ترقيم صفحات على مستوى SQL.
- تغيير فلاتر/ترتيب الواجهة.
- بوابات الجهاز الحقيقية.
