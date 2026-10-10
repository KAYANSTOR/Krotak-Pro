# خط الأساس — Krotak Pro (المرحلة 0)

**التاريخ:** 2026-10-10
**الوثيقة الحاكمة:** `docs/خطة-تنفيذ-Krotak-Pro-النهائية-2026-10-10.md`
**الفرع الفعلي للتنفيذ:** `development/full-completion` (سياسة `AGENTS.md`)
**مرجع الالتزام عند بدء التنفيذ:** `d21fe05` — «docs: add final Krotak Pro execution plan»

---

## 1. حالة الفروع (فحص مباشر من GitHub)

| الفرع | الحالة | ملاحظة |
|---|---|---|
| `main` | `dd7c5fd` | لم يُلمس، ولا يُلمس (قاعدة الخطة 1.3) |
| `development/full-completion` | `d21fe05` | **فرع التنفيذ المعتمد** |
| `development/next` | **غير موجود على `origin`** | الخطة (القسم 3) تفترض وجوده ودمج 4 commits منه — غير قابل للتنفيذ كما هو |
| `feature/salafni-settlement-notice`, `feature/salafni-settlement-notice-real` | موجودان | PR #38 مفتوح؛ **مخالفة لسياسة `AGENTS.md`** ومحتاج قرار المالك |
| `integration/baseline-20261010`, `exec/krotak-hardening` (الخطة 1.5) | **لم تُنشأ** | إنشاؤها **محظور** بـ`AGENTS.md` («لا تنشئ فرعًا آخر بأي اسم») |

### قرار المرحلة 0 (بند 1.2.4 — تعارض مباشر وموثّق)
الخطة تطلب فرعين جديدين (`integration/baseline-20261010` + `exec/krotak-hardening`)، وسياسة المستودع `AGENTS.md`
تسمح بثلاثة refs فقط. **المرجَّح: سياسة المستودع.** لذلك:

- فرع التنفيذ = `development/full-completion` مباشرة (لا فرع تكامل ولا فرع تنفيذ جديد).
- لا دمج لـ`development/next` (غير موجود أصلًا)، فلا حاجة لفرع تكامل.
- الناتج النهائي = Pull Request من `development/full-completion` إلى `main` بعد مراجعة المستخدم (D12).

---

## 2. حالة CI عند خط الأساس

| البند | النتيجة |
|---|---|
| مشغّلات `ci.yml` الحالية | `push`/`pull_request` على `main`, `development/next`, `development/full-completion` ✅ **يخالف ما ذكره القسم 0 من الخطة (كان `main`+`development/next` فقط)** |
| CI على `development/full-completion` | آخر run **مكتمل ناجح**: `38079900832` (fix: make balance-only deposit reprocessing idempotent) — 14m35s |
| run الخطة (`d21fe05`) | `38082206767` — قيد التنفيذ عند كتابة السطر |
| Flutter في بيئة الوكيل | **غير متوفر** (`flutter: command not found`, `dart: command not found`) → كل `analyze`/`test` عبر CI كما تنص الخطة 1.4 |
| الأدوات المتاحة | `gh` (مصادَق تلقائيًا)، `git` |

---

## 3. حقائق الكود المؤكدة في خط الأساس (مقابل ما في القسم 0 من الخطة)

| البند | الحالة الفعلية |
|---|---|
| `settings_hub_screen.dart` بطاقة «إدارة الكروت والفئات» | موجودة — **السطر 332** (والخطة قالت ~331) |
| استيراد `inventory_screen.dart` في شاشة الإعدادات | السطر 25 — سيصبح غير مستخدم بعد WP-1 |
| إشعار «حساب دائم — بدون فترة تجريبية» | `account_auth_screen.dart:521` داخل `_trialCard` (تعريف `:502`)، ويُستدعى في وضع الإنشاء فقط `:459` |
| تكرار النص في شاشات أخرى | لا يوجد — `grep` على `lib/` أعاد فقط `:18` (تعليق) و`:521` |
| `schemaVersion` | `5` (`lib/data/database/app_database.dart:215`) — WP-S4 يرفعه إلى 6 |
| إصدار التطبيق | `1.0.15+15` (`pubspec.yaml:4`) |
| `targetSdk` | يُقرأ من Flutter (`flutter.targetSdkVersion`) — يُثبَّت فعليًا من APK المبني في CI (بند WP-9) |
| `AppContainer.forTesting()` (الخطة 5.2 طبقة 4) | **غير موجود** — الـAPI الفعلي: `AppContainer.bootstrap(databaseOverride:, backupDirectoryOverride:, templates:)` |
| مجلدات `docs/exec` و`docs/audit` | **غير موجودة** — أُنشئت الآن |

---

## 4. قرارات خط الأساس المسجّلة

| # | القرار | السبب |
|---|---|---|
| B1 | التنفيذ على `development/full-completion` بلا فرع جديد | `AGENTS.md` |
| B2 | تجاهل خطوة دمج `development/next` | الفرع غير موجود على `origin` |
| B3 | التحقق عبر CI فقط (gh run watch / annotations) | لا Flutter SDK محليًا |
| B4 | استخدام `AppContainer.bootstrap(...)` في اختبارات الواجهة بدل `forTesting()` | الـAPI الفعلي |
| B5 | `feature/salafni-*` خارج نطاق هذه الدفعة، ويُرفع للمالك | سياسة الفروع + نطاق الخطة |
