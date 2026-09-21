# Krotak Pro — تقرير مقارنة الخطة بالتنفيذ

**تاريخ المراجعة:** 2026-09-11

## 1. نطاق المراجعة

تمت مراجعة جميع Commitات الفرع `main`، وبنية `lib` و`android` و`test` و`docs`، والخطة الرئيسية، والمواصفات، وقواعد الأعمال، وخريطة نقل Kotlin، ووثيقة ميزات ما بعد الخطة الأولى.

هذه المراجعة تميز بين وجود كود أولي وبين اكتمال ميزة قابلة للإصدار. وجود Service أو شاشة أو Interface لا يعني أن دورة العمل كاملة أو أن معايير الإنتاج محققة.

## 2. الحالة الحالية باختصار

المشروع تجاوز مرحلة التهيئة الأولى فعليًا. تمت إضافة طبقة Domain أوسع، وقاعدة Drift، وسجل مالي وAudit وUnit of Work، وخدمات المخزون وتحليل الرسائل ومعالجة التحويل، ونسخ احتياطي محلي وترخيص محلي، وجسر SMS Native، وشاشات Flutter أساسية وثيم Kayan.

لكن الحالة الحالية **ليست جاهزة للإصدار**؛ فالفحص الحالي يكشف أن `flutter analyze` يفشل بـ147 مشكلة تقريبًا، و`flutter test` يفشل بسبب عدم توافق عقود Repositories والخدمات والاختبارات بعد التغييرات المتوازية. لذلك يجب اعتبار آخر Commit حالة تكامل غير مستقرة إلى أن يتم توحيد العقود وإعادة الفحص.

## 3. تاريخ التغييرات الفعلي

| Commit أو المجموعة | ما أُضيف |
|---|---|
| `6a20eea` | إنشاء مشروع Flutter Android. |
| `7c0040f` | الخطة والمواصفات وتحليل Kotlin المرجعي. |
| `a396e4f` | كيانات Domain وعقود Repository وService. |
| `99f18f0` | Drift وSQLite وSchema v1. |
| `8087baa` | Repositories محلية أولية. |
| `5503163` | ميزات ما بعد الخطة الأولى. |
| `c32086f` | إكمال أجزاء من Repositories والخدمات وLedger وUnit of Work وSale/Inventory واختباراتها. |
| `0960063` | قواعد الأعمال وتحديث مخطط Domain وخطة التنفيذ. |
| `27fec4f` | ID generator وClock وLedger وAudit وSettings وUnit of Work. |
| `74dc6a9` | تحديث Drift وعقود Repositories. |
| `7e58072` | عقود MessageParser وTransferProcessor. |
| `a629d8f` و`b8ba5fd` | تنفيذ واختبارات MessageParser وTransferProcessor. |
| `ec03f6e` و`5aafb93` و`9248c2f` | SMS Receiver وصلاحياته وMethodChannel/EventChannel وFlutter bridge وIncomingSmsHandler. |
| `c4f38b2` | License service محلي وSettings وBackup/Restore محلي. |
| `7a82d03` إلى `cfa995e` | Home shell وDashboard وCustomers وInventory وMessages وSettings. |
| `e78b4cf` | Inventory screen وفئات الكروت واستيرادها. |
| `282ab2c` و`07c2e54` | AppContainer وLocalCardInventoryService. |
| `512ffcb` إلى `1c8a4f4` | Kayan design tokens والثيم والوضع الليلي والتنقل السفلي ومكونات Dashboard. |
| `20ffcfb` | إصلاحات أسماء Drift/domain في الاختبارات، مع بقاء تعارضات أخرى لاحقًا. |
| `c17bdcf` | هذا التقرير بعد دمجه مع الفرع البعيد. |

المستودع المحلي متزامن مع `origin/main`، ولا توجد تغييرات غير مرفوعة.

## 4. مقارنة مراحل الخطة

| المرحلة | الحالة الحالية | المنجز | المتبقي لمعيار القبول |
|---|---|---|---|
| 0. النطاق والقرارات | جزئي | الخطة والمواصفات وقواعد أعمال مؤقتة ووثائق الميزات اللاحقة. | اعتماد القرارات النهائية للعملة، الترخيص، النسخ الاحتياطي، SMS، المديونية، السلفة، POS، والبث. |
| 1. Kotlin وUX | جزئي إلى جيد | تحليل Kotlin، Design Tokens من `Color.kt` و`Theme.kt`، ثيم Kayan وتنقل سفلي ومكونات Dashboard. | توثيق وتنفيذ جميع الشاشات الـ25 والحالات والحوارات والأصول والـUX بالتفصيل وربطها بالمنطق الحقيقي. |
| 2. Domain وBusiness Rules | جزئي متقدم | كيانات، Money، Ledger، Audit، ID/Clock، Unit of Work، خدمات مخزون ورسائل وتحويل وترخيص. | توحيد العقود، إضافة Use Cases كاملة للأرصدة والبيع والتحويل والعكس والتسويات والتقارير والعروض وسلفني، وإغلاق التعارضات الحالية. |
| 3. قاعدة البيانات | جزئي متقدم | Drift وSchema أولي وتحديثات للمخطط وBackup/Restore محلي. | Foreign Keys، الفهارس، uniqueness، migrations مختبرة، التشفير، سياسة soft delete، اختبارات الترقية والاستعادة، وضمان تطابق كل Repository مع المخطط. |
| 4. التطبيق والحالة | جزئي | AppContainer وAppScope وHomeShell وثيم وشاشات أساسية. | State management صريح، Routing كامل، حالات loading/empty/error/success، localization/RTL مكتمل، وفصل كل عملية عن Widget. |
| 5. محرك الأعمال | جزئي | Inventory، بعض البيع/الرصيد/الـLedger، MessageParser، TransferProcessor، خدمات محلية. | إكمال التدفقات الذرية، إعادة المحاولة والتعويض، POS وSettlement وOffers وRewards وAdvance وReports، وإصلاح الاختبارات والعقود. |
| 6. SMS والخلفية | جزئي متقدم | `SmsReceiver.kt`، صلاحيات، MethodChannel/EventChannel، Flutter bridge، IncomingSmsHandler، وربط AppContainer. | اختبار Android فعلي، Worker/queue قابلة للاستعادة، منع التكرار على مستوى قاعدة البيانات، إرسال SMS فعلي مضبوط، SIM والبطارية واستعادة الفائت. |
| 7. الترخيص | جزئي محلي | LocalLicenseService وSettings ونسخ احتياطي محلي. | Backend/مفتاح حقيقي، ربط الجهاز، تحقق دوري، offline grace، تخزين آمن، وحالات الفشل والإصدار. |
| 8. Feature-by-Feature | جزئي | بدأ بناء Dashboard وCustomers وInventory وMessages وSettings. | ربط كل شاشة Use Case حقيقي، استكمال الشاشات P0/P1، ثم اختبارات تكامل وإصدار. |

## 5. ما تم إنجازه فعليًا

### الأساس المعماري

المشروع الآن يستخدم Flutter مع Domain وData وApplication وUI وPlatform. يوجد `AppContainer` للتركيب، و`AppScope` لحقن الحاوية، وطبقة Native منفصلة لمعالجة SMS بدل وضعها داخل Widgets.

### Domain والبيانات

توجد كيانات العملاء، المعرفات، المحافظ، نقاط البيع، الكروت، الحركات، المبيعات، الرسائل، الترخيص، الإعدادات، التدقيق، وMoney. أضيف Ledger وAudit وUnit of Work وClock وID generator. توجد قواعد أعمال مؤقتة موثقة للرصيد والحجز والرسائل والعكس.

### قاعدة البيانات والخدمات المحلية

توجد Drift/SQLite مع Schema أولي ومولد كود، ومزوّد فتح قاعدة، وتخزين للعملاء والكروت والرسائل والإعدادات والتدقيق والحركات. توجد خدمات محلية للمخزون، تحليل الرسائل، معالجة التحويل، الترخيص، والنسخ الاحتياطي/الاستعادة.

### التحويل والرسائل

تم تنفيذ `LocalMessageParser` و`LocalTransferProcessor` واختبارات مخصصة لهما. التدفق أصبح أقرب إلى حفظ الرسالة ثم تحليلها ثم تمريرها للمعالجة، لكنه لا يحقق بعد كل ضمانات idempotency والتعويض والإرسال المطلوبة للإنتاج.

### Android وSMS

تمت إضافة `SmsReceiver.kt` وربطه بصلاحيات Android، وMethodChannel/EventChannel، وBridge في Flutter، وIncomingSmsHandler داخل AppContainer. هذا إنجاز حقيقي في طبقة التكامل، لكنه يحتاج اختبارات جهاز/محاكي وسياسة Worker واستعادة أكثر صرامة.

### الواجهة

تمت إضافة Home shell، Dashboard، Customers، Inventory، Messages، Settings، وثيم Kayan الفاتح والداكن، Design Tokens، Bottom Navigation، وWidgets للرصيد والمبيعات والإجراءات السريعة. هذه واجهات أولية مرتبطة جزئيًا وليست كل شاشات Kotlin الـ25.

### CI والاختبارات

يوجد ملف CI في `.github/workflows/ci.yml`. توجد اختبارات Domain وقاعدة بيانات وRepositories وInventory/Sale وMessageParser/Transfer. لكن الفحص الحالي لا يمر بسبب عدم توافق العقود، لذلك لا يمكن اعتبار CI أو الاختبارات خضراء حاليًا حتى يتم الإصلاح.

## 6. الحالة الفعلية للفحوص

آخر تشغيل مباشر بعد دمج كل التغييرات:

```text
flutter analyze — فشل، حوالي 147 مشكلة
flutter test — فشل، عدة ملفات اختبار لا تُترجم
Git working tree — نظيف ومتزامن مع origin/main
```

أبرز أسباب الفشل الظاهرة:

- اختبارات قديمة تتوقع `CustomerRepository` و`MessageRepository` بعقود مختلفة عن الحالية.
- مراجع إلى `local_sale_service.dart` غير موجود.
- أنواع أو عقود غير متطابقة مثل `Message` و`AuditLogRepository`.
- Methods مطلوبة في الاختبارات مثل `findByPhone` و`getById` و`list` و`findByDedupeKey` غير متطابقة مع العقود الحالية.
- بعض Fake repositories تعيد `Result<void>` بينما العقد الحالي يتوقع `Result<Customer>`.

هذه ليست مشاكل نظرية؛ يجب إصلاحها قبل اعتبار أي مرحلة مكتملة أو متابعة إضافة ميزات جديدة.

## 7. ما يزال متبقيًا من الخطة الأساسية

1. توحيد عقود Repositories وServices بين الإنتاج والاختبارات.
2. إعادة `flutter analyze` و`flutter test` إلى حالة خضراء.
3. إكمال قيود قاعدة البيانات والفهارس وmigrations والتشفير.
4. إكمال Customer Balance وSale وTransfer كـUse Cases ذرية مع Audit وidempotency.
5. إكمال POS وSettlement والعكس والتقارير.
6. إكمال SMS Worker والـqueue والاستعادة والإرسال الفعلي واختبارات Android.
7. استكمال التفعيل الحقيقي والترخيص والـoffline grace.
8. إكمال UI/UX لكل شاشات P0 ثم P1 وربط الحالات الفعلية.
9. إضافة اختبارات تكاملية وmigrations وقطع الاتصال وإعادة التشغيل.
10. تجهيز إصدار تجريبي فقط بعد عودة الفحوص خضراء ومراجعة أمنية.

## 8. ميزات ما بعد الخطة الأولى

لا تزال ميزات `docs/post-v1-features.md` غير منفذة كميزات مكتملة: سلفني، إشعارات المحافظ، التسوية التلقائية الكاملة، بث SMS الجماعي، Customer Identity Resolver وMerge، Pending Jobs العامة، وتحسينات الأداء والوصول. بعض بنيتها ستستفيد من SMS/Parser/Unit of Work الحالية، لكنها لا تُعتبر منجزة حتى تُضاف Domain وDatabase وService وUI وTests كاملة.

## 9. الحكم النهائي

المستودع أحرز تقدمًا كبيرًا مقارنة بالحالة التي بدأ منها: لم يعد مجرد Flutter shell أو Domain skeleton، بل يحتوي على أساس مالي محلي، خدمات تحويل ورسائل، تكامل SMS، وثيم وشاشات أساسية.

في المقابل، آخر حالة منشورة غير مستقرة تقنيًا بسبب تعارضات العقود التي ظهرت بعد تنفيذات متوازية. لذلك التصنيف الدقيق هو: **Feature Foundation متقدم، MVP قيد البناء، غير صالح للإصدار التجاري حاليًا**.

الأولوية الصحيحة الآن ليست إضافة ميزة جديدة، بل تنفيذ مرحلة تثبيت: توحيد العقود، إصلاح compile/test، ثم إضافة اختبارات المعاملات وidempotency، وبعدها استكمال الشاشات وربطها بالعمليات الحقيقية.
