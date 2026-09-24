# شهادة الجاهزية التجارية — Krotak Pro (QA / Release Certification)

**التاريخ:** 2026-09-24
**الفرع:** `development/full-completion`
**النطاق:** إثبات قابل للتكرار لسلوك التطبيق الحقيقي (SMS، الأتمتة، المخزون، البيع،
الاسترداد) + إغلاق بوابات الإصدار. لا تغيير في Architecture أو Navigation أو
Business Logic إلا لأخطاء مُثبتة باختبار يفشل قبل الإصلاح.

---

## 1) خط الأساس والفرع

| البند | القيمة |
|------|--------|
| فرع العمل | `development/full-completion` |
| commit خط الأساس | `bbf285b` — «Merge origin/main into development/full-completion» |
| علاقة `origin/main` بالفرع | مُحتوى بالكامل (0 behind / 17 ahead) — تغييرات Firebase App Distribution وTest Lab موجودة |
| `main` | لم يُعدَّل (لا التزامات ولا دمج) |

- لا حاجة لأي إعادة دمج إضافية: خط أساس واحد نظيف، ولا تعارضات.
- المخزونان المحفوظان (`git stash list`) أرشيفيان فقط وليسا مصدرًا للتطوير:
  - `stash@{0}` = النسخة الأصلية للملفات السبعة غير الملتزمة على `main`
    (محتوياتها الوظيفية مُدمجة كلها في الفرع، وواجهة «الرسائل الفاشلة» أُعيدت
    إلى مصدر الحقيقة `MessagesFacade` بدل دمج القائمتين يدويًا).
  - `stash@{1}` = `ci.yml`/README أقدم (checkout@v6 وflutter 3.47.4) — متجاوَز.

---

## 2) ما شُغّل فعليًا (أدلة تنفيذ، لا افتراضات)

البيئة: Flutter `3.47.5` • Dart `3.13.4` • Android SDK `36.0.0` • JDK `17`
(المطلوب في المشروع: `sdk: ^3.6.0` ✔).

| الأمر | النتيجة |
|------|--------|
| `flutter pub get` | ✅ `Got dependencies!` |
| `dart analyze` | ✅ **0 error • 0 warning** (294 `info` لينت قائمة مسبقًا) |
| `flutter analyze --no-fatal-infos` (بوابة CI) | ✅ نظيف |
| `flutter test` | ✅ **400/400 اختبارًا ناجحًا** |
| ترجمة طبقة SMS الأصلية (Kotlin) على JVM | ✅ `SmsInboxQueue/SmsInboxStore/SmsReceiver/NotificationListener` تُترجم بلا أخطاء |
| اختبارات Android JVM (`SmsInboxQueueTest`) | ✅ **8/8 ناجحة** (`OK (8 tests)`) |
| `flutter build apk --release` | ⛔ **لم يُنفَّذ محليًا** — قيود بيئة موثّقة في §3، والبناء يبقى على CI |

إزالة اختبارين وهميين: `test/widget_test.dart` (`expect(1 + 1, 2)`) و
`test/services/pd07_settings_gating_test.dart` (`expect(true, isTrue)`، ويُسمّى في
سجل Git نفسه «the unused pd07 stub»). العدد قبل الإزالة 401 → بعده 400، فلا يوجد
عدّ اختبارات مضلل.

---

## 3) قيود بيئة التنفيذ (لماذا لم يُبنَ APK محليًا)

هذه ليست أعذارًا عامة، بل أخطاء مُقاسة من تنفيذ حقيقي:

1. **الذاكرة:** حدّ الـ cgroup = `2147483648` بايت (2 GiB) بينما
   `android/gradle.properties` يطلب `-Xmx8G` → نفق الـ daemon
   (Gradle build daemon disappeared unexpectedly). العمل بعد
   `-Xmx1200m` يكمل الإعداد لكن…
2. **القرص:** الحجم الكلي 4.0 G. إعادة تحويلات AGP للاعتماديات تتجاوز المساحة:
   `java.io.IOException: No space left on device` عند إنشاء
   `android/.kotlin/errors/...`. بعد التنظيف: ~1.9 G متاحة، وهي لا تكفي
   (تحويلات Gradle وحدها كانت 1.8 G).
3. **NDK:** التثبيت المتوقف على `28.2.13676358` أعطى
   `[CXX1101] NDK ... did not have a source.properties file`. المشروع لا يملك أي
   كود أصلي (لا `CMakeLists.txt`، و`sqlite3_flutter_libs` يشحن مكتبات جاهزة،
   و`jni` ليس اعتمادية)، فالمُطلَب كان تحقّقًا DSL فقط.

**الخلاصة:** CI هو بيئة تنفيذ بناء الـ APK — كما اتُّفق — مع إبقاء كل ما يمكن
تشغيله محليًا مُشغَّلًا بالفعل (تحليل + 408 اختبارًا).

---

## 4) أخطاء إنتاجية مُثبتة ومُصلحة (Release Blockers مُغلقة)

| # | الخلل | السبب الجذري | الإصلاح | اختبار الانحدار |
|---|------|--------------|---------|------------------|
| B1 | **تكرار رسائل SMS على العميل** | فشل غير قابل لإعادة المحاولة كان يعيد نفس `MessageRetryState` ويترك الحالة `failed`، فأي دورة تسليم (كل 3 ثوان) تعيد إرسال نفس الرسالة | عند فشل غير قابل للمحاولة: قيد تدقيقي `message_retry_exhausted` + حالة نهائية `failedMaxAttempts` | `message_delivery_worker_test.dart` → «non-retryable send failure stops the every-tick resend loop» (يحصر `sender.attempts == 1` بعد دورتين) |
| B2 | **طلب POS متعدد الكروت يعلق في `failed`** بعد بيع فعلي وإرسال رسالتين | قيد البيع لكل كرت بمفتاح مركّب `sale-op:<id>:<index>` والبحث يتم بمفتاح `sale-op:<operationId>` → `sale_ledger_missing` دائمًا | البحث بمرجع أول عنصر مُلتزم فعليًا | `pos_order_execution_test.dart` (مجموعة multi-card) |
| B3 | **وحدة `app` لا تُترجم أصلًا** (حاجز بناء) | `internal data class PendingSms` مُعرَّف مرتين في `SmsInboxStore.kt` و`SmsInboxQueue.kt` بنفس الحزمة | `SmsInboxStore` أصبح طبقة Android/SharedPreferences فقط ويفوّض كل المنطق إلى `SmsInboxQueue` (مصدر واحد قابل للاختبار على JVM) | `SmsInboxQueueTest` (8 اختبارات) + ترجمة Kotlin مستقلة |
| B4 | `pubspec.lock` غير متزامن | `cupertino_icons` لا يزال مثبتًا في القفل بعد إزالته من `pubspec.yaml` | `pub get` نظّف القفل | — |
| B5 | عدّ اختبارات مضلل | اختباران وهميان | حُذفا | — |

---

## 5) مصفوفة الاختبار — ما أصبح مُثبتًا آليًا

### A. البناء والجودة الساكنة
`pub get` ✔ • `dart analyze` (0/0) ✔ • `flutter test` 400/400 ✔ • اختبارات
Android JVM 8/8 ✔ • ترجمة كود الإنتاج لطبقة SMS ✔.
بناء APK الموقّع + التحقق من التوقيع: عبر CI (`apksigner verify --print-certs`).

### B. الإقلاع وقاعدة البيانات
- إقلاع فعلي في الاختبارات: `AppContainer.bootstrap` (runtime smoke،
  `direct_sale_path_integration_test`، اختبار الإقلاع بعد الترقية).
- **ترقية قاعدة البيانات حقيقية** (`test/data_migration_test.dart`): بناء نسخة
  قديمة (v1) الفعلية → فتحها بالمخطط الحالي → تُرقّى → كل صف محفوظ → التطبيق
  يُقلع عليها؛ ويشمل حالة فهرس `secret_code` القديم الفريد وكتابة كروت
  بالرقم التسلسلي وحده بعده.

### C. وظائف الأتمتة الواردة (Ingress)
`test/application/incoming_sms_handler_test.dart`:
`peek`/فك ترميز حمولة المنصّة • ردّ null ← دفعة فارغة • `ack` فارغ لا يفعل شيئًا •
`ack` يُرسل نفس المعرّفات بالضبط • استنزاف دفعة وصلت والتطبيق مغلق **مرة واحدة
وتأكيدها** • حدث بلا معرّف pending يُعالَج دون تأكيد • نفس SMS مرتين = حدث تجاري
واحد • إعادة تشغيل نفس الدفعة بعد restart تبقى idempotent • الفشل يترك الدفعة
بدون تأكيد فلا يضيع شيء • SMS حيّ يُعالج أثناء الاستماع ويُهمل بعد الإيقاف • إدخال
يدوي مكرّر يُنزَّل إلى حدث واحد.

### D. البيع عبر POS (تنفيذي كامل على Drift حقيقي)
`test/services/pos_order_execution_test.dart` — المسار الكامل
SMS → تحليل → هوية النقطة → الفئة → حجز المخزون → بيع الكرت → القيد المالي →
رسالة العميل + رسالة تأكيد النقطة → التدقيق:
- كرت واحد: بيع + خصم مخزون + دين على النقطة + تسليم مرتين (عميل/نقطة).
- كمية > 1: **كرت وحجز وقيد مستقل لكل كرت**.
- «غير متوفر» تُرفض بلا أي تغيّر مالي.
- مخزون غير كافٍ: تُحرَّر كل الحجوزات ولا يُباع شيء.
- إعادة معالجة نفس الطلب لا تخصّص أي كرت إضافي (منع تكرار).
- فشل SMS: الطلب المُلتزم يبقى والعامل يعيد المحاولة.
- فشل تأكيد النقطة لا يعيد إرسال قسيمة العميل.
- العامل يُصلح ذاتيًا طلبًا بقي `failed` بعد تسليم كامل.
- نقطة غير نشطة تُرفض بلا أي تغيّر.

### E. الاسترداد والفشل
`core_business_flow_recovery_test` • `sale_idempotency_test` •
`core_flow_hardening_test` • `settlement_audit_recovery_test` • اختبارات فشل
التسليم و`retry` أعلاه. الهدف المحقّق: لا صرف مزدوج + لا خصم مزدوج + لا حركة مزدوجة.

### F. الطبقة الأصلية (Kotlin) — اختبار JVM حقيقي
`android/app/src/test/kotlin/com/kayan/net_app/SmsInboxQueueTest.kt`:
الترتيب • `peek(limit)` بلا حذف • `ack` يُزيل المعرّفات المطلوبة فقط ويتجاهل
المجهولة/الفارغة • بقاء الرسائل بعد إعادة تشغيل العملية • سقف الحجم (الأقدم
يُسقط) • حمولة تالفة لا تُفقد الرسائل التالية • حمولة ناقصة الحقول تُتخطّى ككل بلا
استثناء.

> هذا اختبار لمنطق الإنتاج نفسه (`SmsReceiver` و`MainActivity` يستخدمان
> `SmsInboxStore` الذي يفوّض إلى `SmsInboxQueue`)، وليس اختبار MethodChannel.
> حدود المجال: `SharedPreferences` وعنوان Broadcast والأذونات تبقى جهاز فقط.

---

## 6) ما لا يمكن إثباته إلا على جهاز/شريحة (يُدار يدويًا)

| الفئة | ما يحتاجه | الحالة |
|------|-----------|--------|
| SMS حقيقي | شريحة + بثّ `SMS_RECEIVED` من مشغّل | **جهاز فقط** |
| صيغة الرسائل | مطابقة قوالب المشروع الفعلية | مُغطّى منطقيًا؛ الإثبات الميداني جهاز فقط |
| الأذونات | Allow/Deny/Deny permanently/منح لاحقًا/سحب الإذن/إعادة تشغيل بعد التغيير | **جهاز فقط** (لا يوجد إلا اختبار جسر واحد لاختيار جهة الاتصال) |
| إعادة التشغيل | `BOOT_COMPLETED`/`QUICKBOOT`/`MY_PACKAGE_REPLACED` وقيود OEM | **جهاز فقط** |
| مقيّد البطارية/Autostart | Samsung/Xiaomi/Huawei/OPPO | **يدوي** |
| مستمع الإشعارات | `NotificationListenerService` + إذن من النظام | **جهاز فقط** |
| Firebase Test Lab (Robo) | مشروع Firebase + صلاحيات | **CI/سحابي** |

---

## 7) نتائج تدقيق جديدة — مخاطر مفتوحة (ليست مُغلقة)

1. **لا توجد Foreground Service فعليًا.** الإذنان
   `android.permission.FOREGROUND_SERVICE` و`WAKE_LOCK` مُعلنان في
   `AndroidManifest.xml`، لكن لا يوجد `<service>` لخدمة أمامية ولا أي
   `startForeground` في الكود، ولا `WorkManager`/`AlarmManager`.
   - **الوارد آمن:** `SmsReceiver` يحفظ في `SmsInboxStore` بمعزل عن عملية الـ UI،
     فالرسالة لا تُفقد عند قتل التطبيق.
   - **الخطر:** تسليم الرسائل الصادرة (قسيمة/تأكيد POS) يتقدّم فقط أثناء حياة
     العملية أو بعد إعادة فتح التطبيق؛ على أندرويد 14+ أي خدمة أمامية ستتطلب
     `foregroundServiceType`.
   - القرار (إضافة خدمة أمامية، أو الاعتماد على البريد الوارد + الإقلاع التلقائي)
     قرار منتج يحتاج تحقق أجهزة أولًا، ولم أغيّر البنية بلا دليل اختبار.
2. **إعلانات أذونات غير مستخدمة:** `FOREGROUND_SERVICE` و`WAKE_LOCK` بلا مستهلك —
   تُراجع قبل النشر التجاري.
3. **Offline/Online:** التطبيق محلي أولًا بالكامل؛ لا يوجد عميل HTTP في
   `pubspec.yaml` (لا `http`/`dio`/Firebase) ولا طبقة مزامنة، أي لا يوجد
   «تعارض مزامنة» يمكن اختباره. المتبقي هو إثبات ميداني لسلوك بلا اتصال (جهاز).
4. **بوابة Firebase عند غياب الأسرار:** الخطوات صارت بوابة صلبة عند وجود
   `FIREBASE_SERVICE_CREDENTIALS`/`FIREBASE_APP_ID`/`FIREBASE_PROJECT_ID`
   (فشل Test Lab يُفشل المهمة، والإصدار لا يُنشر قبل نتيجته). لكن إن كانت الأسرار
   غير مضبوطة تُتخطّى الخطوة (`skipped`) فيُسمح بالنشر — وهذا سلوك مقصود
   («غير مهيّأ ≠ ناجح») ويظهر صراحةً في ملاحظة CI وفي نص الإصدار
   (`Firebase Test Lab <outcome>`). لتحويله إلى بوابة صلبة دائمًا يلزم ضبط
   الأسرار من مالك المستودع.

---

## 8) بوابة CI الحالية (`.github/workflows/ci.yml`)

- `continue-on-error` مُزال من خطوات Firebase.
- الترتيب مصحّح: App Distribution + Test Lab **قبل** نشر GitHub Release،
  والنشر مشروط بـ `testlab.outcome == success || skipped`.
- صلاحيات: `contents: write` و`id-token: write`، ومصادقة
  `google-github-actions/auth@v2` عبر
  `FIREBASE_SERVICE_CREDENTIALS` (Service Account JSON).
- تهيئة موارد Test Lab: تفعيل `testing|toolresults|firebaseappdistribution`
  APIs، إنشاء/استخدام دلو النتائج، ومنح
  `service-<project>@gcp-sa-firebase.iam.gserviceaccount.com`
  دور `roles/storage.objectAdmin` على الدلو.
- **جديد:** خطوة تشغيل اختبارات Android JVM (`:app:testDebugUnitTest` بعد
  `flutter build apk --config-only`) + رفع تقاريرها كأثر — لأن `flutter test`
  لا ينفّذ أي كود Kotlin.

---

## 9) الخلاصة

| المجال | الحكم |
|------|------|
| الجودة الساكنة (analyze) | ✅ جاهز |
| اختبارات المجال/البنية (Dart) | ✅ 400/400 جاهز |
| منطق الطبقة الأصلية (JVM) | ✅ 8/8 جاهز |
| POS الكامل + منع التكرار | ✅ مُثبت تنفيذيًا |
| Ingress SMS + idempotency | ✅ مُثبت تنفيذيًا |
| ترقية قاعدة البيانات | ✅ مُثبتة على نسخة قديمة فعلية |
| بناء APK الموقّع | 🟡 CI (تعذّر محليًا لقيود موثّقة §3) |
| Firebase Test Lab | 🟡 البوابة مصلَّحة؛ تعتمد على ضبط أسرار المالك |
| جهاز/شريحة/OEM/مستمع الإشعارات | 🔴 يلزم تحقق ميداني (خارج نطاق CI) |

**لا يُعتبر الإصدار التجاري مكتملًا** قبل: نجاح CI على `development/full-completion`
(بناء APK موقّع + التحقق من التوقيع + Test Lab)، ثم تحقق جهاز واحد على الأقل
للأذونات/الإقلاع/SIM/الإشعارات، ثم قرار مالك المشروع في مخاطر §7-1 و§7-2.
