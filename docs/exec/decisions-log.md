# سجل القرارات — Krotak Pro

| التاريخ | القرار | الخيارات | ما اختير | السبب | الأثر |
|---|---|---|---|---|---|
| 2026-10-10 | فرع التنفيذ | (أ) `integration/baseline-20261010` + `exec/krotak-hardening` كما في الخطة 1.5 (ب) `development/full-completion` | **(ب)** | `AGENTS.md` يحظر إنشاء أي فرع آخر (بند 1.2.4 في الخطة: تعارض مباشر) | لا فرع تكامل؛ PR مباشر من `development/full-completion` إلى `main` عند الإغلاق (D12) |
| 2026-10-10 | «لا نص لاتيني» وأسماء الملفات التقنية | (أ) منع كل لاتيني (ب) قائمة استثناءات موثّقة | **(ب)** | أسماء أنواع الملفات أعلام لا تُترجم (PDF/Excel/CSV/xlsx/PNG) ومثال رقم الجوال `77xxxxxxx` واسم العلامة `Krotak Pro` | قائمة الاستثناءات مثبّتة في `test/ui/user_facing_error_localizer_test.dart` وتُستعمل في حارس WP-7 |
| 2026-10-10 | عدد صفوف الجرد (الطبقة 1) | (أ) ≥405 + 78 كما توقعت الخطة (ب) العدد الفعلي مع الشرح | **(ب)** | السكربت يشمِل كل المعالجات (`onChanged/onSubmitted/onRefresh/onSelected/onDismissed…`) وكل العناصر التفاعلية لا `onPressed/onTap` فقط | `rows=851` · `callbacks=522` · `elements=374` · `files=79` — الفرق مشروح في `docs/audit/ui-audit-report.md` |

| 2026-10-10 | دمج `development/next` | (أ) الدمج كما في القسم 3 (ب) تخطيه | **(ب)** | الفرع غير موجود على `origin` (فحص `git ls-remote`) | لا حاجة لفرع تكامل |
| 2026-10-10 | API اختبارات الواجهة | (أ) `AppContainer.forTesting()` كما في الخطة 5.2 (ب) `AppContainer.bootstrap(databaseOverride: …)` | **(ب)** | `forTesting` غير موجود في الكود الفعلي | اختبارات WP-1/WP-2 تُبنى بـ`bootstrap` |
| 2026-10-10 | فروع `feature/salafni-settlement-notice*` | (أ) دمجها (ب) تركها للمالك | **(ب)** | مخالفة لسياسة `AGENTS.md` وخارج نطاق الخطة | تُرفع للمالك في التقرير النهائي |
