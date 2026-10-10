# سجل القرارات — Krotak Pro

| التاريخ | القرار | الخيارات | ما اختير | السبب | الأثر |
|---|---|---|---|---|---|
| 2026-10-10 | فرع التنفيذ | (أ) `integration/baseline-20261010` + `exec/krotak-hardening` كما في الخطة 1.5 (ب) `development/full-completion` | **(ب)** | `AGENTS.md` يحظر إنشاء أي فرع آخر (بند 1.2.4 في الخطة: تعارض مباشر) | لا فرع تكامل؛ PR مباشر من `development/full-completion` إلى `main` عند الإغلاق (D12) |
| 2026-10-10 | دمج `development/next` | (أ) الدمج كما في القسم 3 (ب) تخطيه | **(ب)** | الفرع غير موجود على `origin` (فحص `git ls-remote`) | لا حاجة لفرع تكامل |
| 2026-10-10 | API اختبارات الواجهة | (أ) `AppContainer.forTesting()` كما في الخطة 5.2 (ب) `AppContainer.bootstrap(databaseOverride: …)` | **(ب)** | `forTesting` غير موجود في الكود الفعلي | اختبارات WP-1/WP-2 تُبنى بـ`bootstrap` |
| 2026-10-10 | فروع `feature/salafni-settlement-notice*` | (أ) دمجها (ب) تركها للمالك | **(ب)** | مخالفة لسياسة `AGENTS.md` وخارج نطاق الخطة | تُرفع للمالك في التقرير النهائي |
