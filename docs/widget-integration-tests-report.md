# Widget Integration Tests — AppContainer Real-Data Coverage

**Base:** `main` at `793aea6630666ea4b7d61523f3c700af06a1dd48` (rebased from
`1ee12ae`, the post core-flow hardening merge, CI green; the two commits in
between — `6b6f6e3`, `793aea6` — only touch `docs/master-plan.md`, no code).
**Branch:** `test/appcontainer-widget-tests` (not merged to `main`).
**Scope:** Test-only. No production behavior changed.

## الفجوة المُغلقة

`test/widget_test.dart` كان حرفيًا placeholder يقول: *"full widget tests need
AppContainer bootstrap"*. `docs/p0-ui-implementation-report.md` و
`docs/p1-ui-implementation-report.md` يذكران نفس الفجوة كبند متبقٍ صريح. كل
اختبارات الـwidgets الموجودة سابقًا (`p1_navigation_smoke_test.dart`,
`net_components_test.dart`, `dashboard_navigation_test.dart`) تختبر مكوّنات
معزولة بـcallbacks وهمية — وليس شاشة كاملة تقرأ فعليًا من `AppContainer`
وقاعدة بيانات حقيقية.

## ما تم إضافته

1. **`AppContainer.forTesting(...)`** في `lib/application/app_container.dart`
   — نفس منطق `bootstrap()` بالضبط، لكن بدون `path_provider`: يأخذ
   `AppDatabase` مفتوحة مسبقًا (عادة `AppDatabase(NativeDatabase.memory())`)
   ويقبل `clock`/`ids`/`backupDirectory` اختياريًا للحصول على نتائج حتمية في
   الاختبارات. تم استخراج منطق التوصيل المشترك إلى دالة خاصة `_wire(...)`
   يستدعيها كل من `bootstrap()` و`forTesting()`، فلا يوجد أي تكرار أو احتمال
   لتباعد المسارين مستقبلًا.

2. **`test/widget/app_container_screens_test.dart`** — اختبارات تكاملية
   حقيقية عبر `AppScope` + `MaterialApp`، لكل من:
   - `DashboardScreen`: حالة فارغة صادقة (بدون بيانات)، ثم بيانات حقيقية
     (عميل + رصيد + فئة + بطاقة + عملية بيع) تنعكس على `NetBalanceCard` و
     `NetMetricCard` و`NetRecentTransactionCard`، بالإضافة إلى تحقق من أن
     نقرات "حسابات"/"كروت متاحة" تستدعي فعليًا `onNavigateToTab`.
   - `CustomersScreen`: من حالة فارغة إلى إنشاء عميل عبر الواجهة الفعلية
     (BottomSheet) والتحقق من أنه محفوظ فعليًا في قاعدة البيانات (وليس فقط
     في الحالة المحلية للواجهة).
   - `InventoryScreen`: من حالة فارغة إلى إنشاء فئة عبر Dialog حقيقي.
   - `ReportsScreen`: تحقق من أن كل البلاطات تعرض أصفارًا صادقة على قاعدة
     بيانات فارغة دون أي خطأ.
   - `TransactionsLogScreen`: من حالة فارغة إلى عرض حركة إيداع حقيقية.
   - `WalletsPosScreen`: من حالة فارغة إلى إضافة محفظة عبر الـFAB.

   قناة `com.kayan.net/sms` تُحاكى (`TestDefaultBinaryMessengerBinding`) لأن
   `DashboardScreen` يستدعي `smsBridge.hasPermissions()` فعليًا؛ بدون محاكاة
   يفشل الاستدعاء بـ`MissingPluginException` ويدخل الشاشة في حالة خطأ — هذا
   سلوك طبيعي لقناة منصّة حقيقية داخل اختبار، وليس خللًا في الشاشة.

3. تحديث تعليق `test/widget_test.dart` ليشير إلى الملف الجديد بدل ادّعاء
   وجود فجوة أُغلقت بالفعل.

## ملاحظات دقيقة رُصدت أثناء الكتابة (وليست تغييرًا مقصودًا)

- عرض الأرصدة والمبالغ في شاشة الـDashboard الحالية (`NetBalanceCard`,
  `NetMetricCard`) يمرّ دائمًا عبر `formatMoneyMinor` (متّسق)، بخلاف نسخة
  الواجهة القديمة (`CustomerBalanceCard`/`SalesCardsRow` قبل الدمج الأخير)
  التي كانت تعرض minor units خامًا في بعض البطاقات. هذا التصحيح جاء ضمن
  عمل فريق آخر (`feat(ui): restructure DashboardScreen with Net components`)
  وليس جزءًا من هذه المرحلة — الاختبارات الجديدة تُثبّت السلوك الصحيح الحالي
  فقط.

## التحقق

بيئة التنفيذ التي أنشأت هذا الملف **لا تملك Flutter/Dart SDK ولا وصولًا
شبكيًا لتحميلهما**، لذلك لم يكن ممكنًا تشغيل `dart analyze lib test` أو
`flutter test` محليًا للتأكد بشكل قاطع. تمت مطابقة كل توقيع دالة، وكل نص
حرفي، وكل نوع بيانات مستخدَم في الاختبارات الجديدة يدويًا وبدقة مقابل الكود
الفعلي الحالي (وليس افتراضًا أو نسخًا من ذاكرة التدريب). **يجب تشغيل الأوامر
الثلاثة التالية محليًا أو عبر CI قبل الاعتماد النهائي:**

```text
dart analyze lib test
flutter analyze --no-fatal-infos
flutter test
```

آخر تشغيل CI موثّق على `main` (commit `1ee12ae`) كان ناجحًا بالكامل على هذه
الأوامر الثلاثة تحديدًا (انظر `.github/workflows/ci.yml`)، وهذه الإضافة لا
تُعدّل أي كود إنتاجي — فقط تضيف اختبارات جديدة وتُعيد هيكلة `AppContainer`
بشكل ميكانيكي بحت (استخراج دالة مشتركة دون تغيير المنطق).
