# خطة ما بعد V1 — نظام التراخيص وعمولة المنصة والتحكم المركزي

**المشروع:** NET / كروتك  
**المستودع:** KAYANSTOR/net-flutter  
**نوع الوثيقة:** خطة تصميم وتنفيذ مستقبلية — غير قابلة للتنفيذ حاليًا  
**الحالة:** SPECIFICATION ONLY / POST-V1  
**تاريخ الاعتماد الأولي:** 2026-09-21

---

## 0. بوابة التنفيذ الإلزامية — HARD GATE

> **ممنوع بدء أي كود أو Migration أو Firebase Integration أو شاشة أو Service أو Cloud Function أو Rule تخص هذه الخطة قبل الوصول إلى إصدار NET مستقر وجاهز للنشر.**

هذه الوثيقة لا تعني أن مرحلة التراخيص بدأت.

حتى يتحول هذا العمل إلى **AUTHORIZED** يجب أولًا اعتماد جميع شروط بوابة V1 أدناه من صاحب المشروع وتوثيقها في مستودع المشروع.

### شروط فتح الخطة

- [ ] اكتمال جميع الميزات الأساسية الحالية المتفق عليها.
- [ ] إغلاق الفجوات الحرجة في دورة البيع والرسائل والمخزون والمحاسبة.
- [ ] اكتمال Offline-first مع المزامنة دون فقد أو تكرار أو تعارض غير معالج.
- [ ] اكتمال Android Runtime على جهاز حقيقي، بما في ذلك SMS/SIM/background/runtime permissions حسب نطاق التطبيق.
- [ ] اكتمال النسخ الاحتياطي والاستعادة الآمنة.
- [ ] اكتمال جميع الشاشات والأزرار والمسارات الأساسية وعدم وجود شاشات Placeholder أو أخطاء عرض حرجة.
- [ ] اجتياز CI المطلوب للمشروع.
- [ ] إنتاج APK إصدار Release قابل للتوزيع.
- [ ] اختبار استخدام فعلي End-to-End على أجهزة Android حقيقية.
- [ ] اعتماد نسخة Release Candidate.
- [ ] اعتماد قرار V1 Stable / Ready for Release من صاحب المشروع.
- [ ] بعد ذلك فقط تصبح هذه الخطة AUTHORIZED FOR IMPLEMENTATION.

### قاعدة الوكلاء

أي وكيل يعمل على المستودع يجب أن يتعامل مع هذه الخطة على أنها:

~~~text
Current state  = BLOCKED
Implementation = FORBIDDEN
Reason         = V1 release gate not certified
~~~

ولا يجوز تفسير وجود أي LicenseRepository أو كود قديم أو إعدادات سابقة على أنها إذن للبدء.

> **الاستثناء الوحيد قبل فتح البوابة:** تعديل هذه الوثيقة أو وثائق القرارات/specification، بدون تعديل كود المنتج أو بنية قاعدة البيانات أو إعدادات Firebase الإنتاجية.

---

# 1. الهدف التجاري

إضافة منظومة مركزية تمكّن مالك منصة NET من:

1. إنشاء حساب صاحب الشبكة.
2. منح تجربة مجانية لمدة 30 يومًا.
3. اعتماد الحساب من لوحة الإدارة دون إدخال رمز تفعيل.
4. ربط الحساب بالجهاز.
5. تفعيل أو تعليق/إيقاف استخدام التطبيق عن بُعد.
6. معرفة المبيعات المعتمدة لكل شبكة.
7. حساب عمولة المنصة كنسبة من المبيعات.
8. إنشاء كشف عمولة شهري مستقل.
9. إظهار العمولة المستحقة داخل تطبيق صاحب الشبكة.
10. تسجيل التسوية الشهرية من لوحة الإدارة.
11. الاحتفاظ بسجل كامل للتسويات السابقة.
12. إرسال إشعارات Android من لوحة الإدارة إلى مستخدم واحد أو مجموعة أو الجميع.
13. جعل اسم الشبكة المدخل أثناء التسجيل هو الاسم التشغيلي المعتمد داخل التطبيق وقوالب الرسائل.
14. الحفاظ على Offline-first: غياب الإنترنت لا يؤدي إلى فقد بيانات التشغيل المحلية.

---

# 2. حدود المنظومة

## 2.1 ما هو Firebase في هذه الخطة؟

Firebase هو Control Plane / Remote Control Plane للترخيص والحسابات والإشعارات ومزامنة بيانات الاشتراك وكشوف العمولة وما يلزم للإدارة المركزية.

أما العمليات المحلية اليومية في التطبيق فتظل مبنية على الطبقات المحلية الحالية ومصدر الحقيقة التشغيلي المحلي.

التصور:

~~~text
Android App
  ├─ Local operational data / Drift
  ├─ Sales / inventory / messages / accounting
  └─ Licensing client + sync client
             │
             ▼
        Firebase
  ├─ Authentication / identity
  ├─ Firestore
  ├─ Cloud Functions / server-side calculations
  ├─ App Check
  └─ Firebase Cloud Messaging
             │
             ▼
      Admin Web Dashboard
~~~

لا يوضع أي Firebase Admin credential أو secret privileged داخل APK.

## 2.2 مصدر الحقيقة

- **العمليات التجارية المحلية:** المصدر المحلي الحالي للنظام حسب عقود Domain/Repository.
- **الحالة المركزية للحساب والترخيص:** الخادم/قاعدة البيانات المركزية.
- **العمولة النهائية:** تُنشأ وتُثبت مركزيًا ولا تعتمد على رقم يحسبه العميل محليًا فقط.
- **التسوية:** سجل مالي مستقل لا يُحذف عند بدء الشهر الجديد.

---

# 3. نموذج حالات المشترك

الحالات الأساسية:

~~~text
PENDING
TRIAL
ACTIVE
TRIAL_EXPIRED
PAST_DUE
SUSPENDED
BLOCKED
~~~

### المعنى

**PENDING**  
حساب أنشأ طلبًا وينتظر الاعتماد الإداري.

**TRIAL**  
التجربة المجانية فعالة، ومدتها 30 يومًا من تاريخ بدء التجربة.

**ACTIVE**  
حساب مفعل تجاريًا.

**TRIAL_EXPIRED**  
انتهت التجربة ولم يتم اعتماد الحساب بعد.

**PAST_DUE**  
هناك كشف عمولة مستحق بعد حلول موعد التسوية.

**SUSPENDED**  
أوقف الحساب مركزيًا بسبب سياسة الترخيص/التسوية أو قرار إداري.

**BLOCKED**  
حالة إدارية/أمنية أقوى من الإيقاف التشغيلي، ويجب عدم استخدامها كبديل عن حالة عدم السداد.

---

# 4. رحلة التسجيل والتجربة المجانية

## 4.1 شاشة البداية

التصميم يكون قريبًا من المرجع المرسل، مع إزالة مفهوم "رمز التفعيل".

الحقول:

- رقم الجوال.
- اسم الشبكة.
- خيار/بطاقة: **باقة النسخة التجريبية المجانية**.
- زر: **بدء النسخة التجريبية**.

### لا يوجد

- مفتاح تفعيل يكتبه المستخدم.
- كود تفعيل يرسل له من الإدارة.
- اعتماد يدوي لاسم الشبكة داخل التطبيق بعد نجاح التسجيل.

## 4.2 اعتماد الهوية

آلية التحقق من رقم الهاتف نفسها تُحسم في مرحلة التصميم الأمني قبل التنفيذ. يمكن استخدام Firebase Authentication، لكن لا يُفترض شكل شاشة التحقق النهائي قبل اعتماد تجربة المستخدم والقيود العملية الخاصة بالسوق.

> مهم: "لا يوجد رمز تفعيل" يعني عدم وجود Activation Key تجاري يدوي؛ وليس بالضرورة إلغاء كل وسائل التحقق من ملكية رقم الهاتف.

## 4.3 إنشاء الحساب

عند اكتمال التسجيل:

- إنشاء Subscriber ID ثابت.
- حفظ رقم الجوال بصيغة موحدة.
- حفظ اسم الشبكة.
- إنشاء سجل تجربة Trial.
- تحديد trialStartedAt.
- تحديد trialEndsAt = trialStartedAt + 30 days.
- تسجيل Install/Device identity.
- تسجيل إصدار التطبيق.
- إرسال أول حالة مزامنة.
- جعل اسم الشبكة مصدرًا لاسم الشبكة التشغيلي في التطبيق بعد اعتماد التسجيل.

## 4.4 الإدارة

تظهر الشبكة مباشرة في لوحة الإدارة ضمن:

**طلبات جديدة / تجريبي**

ومن هناك يمكن:

- اعتماد الحساب.
- رفضه.
- تمديد/إلغاء التجربة وفق سياسة الإدارة.
- تفعيله كحساب تجاري.
- إيقافه.
- فتح ملفه.

---

# 5. هوية المشترك وربط الجهاز

كل مشترك يجب أن يملك هوية مستقلة عن اسم الشبكة.

المعرف المقترح:

~~~text
subscriberId
~~~

وترتبط به:

~~~text
authIdentity
deviceRegistration
license
commissionPolicy
commissionStatements
settlements
notifications
auditEvents
~~~

### ربط الجهاز

- إنشاء هوية تثبيت Installation Identity.
- ربط الحساب بجهاز واحد في الإصدار الأول ما لم تعتمد سياسة متعددة الأجهزة لاحقًا.
- لا يتم الاعتماد على رقم IMEI أو معرف عتادي غير متاح/غير مناسب كحل وحيد.
- يمكن استخدام هوية تثبيت + بصمات/إشارات تحقق مناسبة.
- استبدال الجهاز يكون من خلال إجراء إداري موثق.
- كل عملية تغيير جهاز تسجل في Audit Log.

---

# 6. اسم الشبكة Branding Source of Truth

الاسم الذي يدخله المستخدم عند التسجيل يصبح الاسم التشغيلي الأولي.

بعد الاعتماد:

~~~text
Subscriber.networkName
        ↓
App synchronized profile
        ↓
Settings.networkName
        ↓
Dashboard
Message Templates
Receipts / Reports / Prints
~~~

### القاعدة

- لا يبقى اسم تجريبي مختلف بعد الاعتماد.
- تغيير اسم الشبكة لاحقًا يكون عبر المسار المعتمد في الإعدادات/الإدارة.
- يجب تحديد سياسة تغيير الاسم في مرحلة التنفيذ: هل يسمح مباشرة؟ هل يحتاج موافقة؟ وهل يؤثر على القوالب الحالية؟
- لا تُكتب أسماء الشبكات داخل القوالب بشكل ثابت.

---

# 7. نموذج العمولة

## 7.1 النسبة العامة

الإدارة تملك إعدادًا مركزيًا مثل:

~~~text
platformCommissionRate = 2%
~~~

لكن لا يجب تثبيت الرقم داخل التطبيق.

## 7.2 نسبة خاصة لمشترك

يجب دعم Override:

~~~text
Global rate = 2.00%
Network X   = 1.50%
Network Y   = 3.00%
~~~

## 7.3 نطاق تأثير النسبة

كل كشف شهري يجب أن يحفظ النسبة التي طبق عليها.

مثال:

~~~text
September 2026
Gross sales = 200,000 YER
Rate        = 2%
Commission  = 4,000 YER
~~~

إذا تغيرت النسبة في أكتوبر إلى 2.5% فلا تتغير قيمة كشف سبتمبر.

---

# 8. تعريف "المبيعات" للعمولة

المصدر يجب أن يكون عمليات البيع المعتمدة في النظام، وليس قيمة يكتبها التطبيق في حقل ملخص.

النطاق المقترح:

- البيع المباشر المكتمل.
- مبيعات المسار الآلي المكتملة.
- المبيعات المتعلقة بنقاط البيع وفق القاعدة التجارية المعتمدة للمالك.
- أي قناة بيع جديدة مستقبلًا بعد إدراجها صراحة في تعريف العمولة.

### لا تدخل تلقائيًا

- عملية ملغاة.
- عملية فاشلة.
- عملية مرتجعة حسب سياسة الإرجاع.
- سجل تجريبي أو Mock.
- رقم إجمالي محلي يرسله العميل دون تفاصيل قابلة للمطابقة.

### قاعدة مكافحة التلاعب

لا يسمح للعميل بأن يرسل:

~~~text
"أنا بعت 200000"
~~~

وتصبح هذه القيمة عمولة رسمية.

بدل ذلك يرسل/يزامن أحداث أو عمليات قابلة للمطابقة، ثم تُحسب المؤشرات المركزية من بيانات معتمدة وقواعد server-side.

---

# 9. سجل المبيعات المركزي / المزامنة

نحتاج طبقة مزامنة مستقلة عن منطق البيع اليومي.

كل عملية قابلة للمزامنة يجب أن تملك معرفًا ثابتًا:

~~~text
saleId / operationId
~~~

مع:

- subscriberId
- occurredAt
- amount
- currency
- sale channel/source
- local reference
- synchronization state
- created/updated timestamps
- integrity/idempotency reference

### المطلوب

- idempotent upload.
- منع التكرار.
- ترتيب زمني قابل للمراجعة.
- معالجة Offline queue.
- عدم مضاعفة المبيعات بسبب انقطاع الإنترنت.
- reconciliation بين المحلي والمركزي.
- تسجيل تعارضات المزامنة بدلاً من إخفائها.

---

# 10. دفتر عمولة المنصة

لا نعتمد فقط على حقل:

~~~text
commissionDue = 4000
~~~

بل نبني سجلًا دوريًا.

## Commission Statement

الحقول المقترحة:

~~~text
statementId
subscriberId
periodStart
periodEnd
grossSales
commissionRate
commissionAmount
currency
status
generatedAt
dueDate
closedAt
~~~

حالات الكشف:

~~~text
OPEN
DUE
PARTIALLY_SETTLED (إن تم اعتماد التسوية الجزئية)
SETTLED
VOIDED
ADJUSTED
~~~

### قاعدة مالية

الكشف المغلق لا يُعاد احتسابه بصمت.

أي تصحيح بعد الإغلاق يكون بواسطة Adjustment موثق مع سبب ومستخدم وتاريخ.

---

# 11. البطاقة داخل Dashboard

يُضاف إلى الشاشة الرئيسية عنصر مستقل:

## عمولة المنصة

يعرض حسب حالة الحساب:

### غير مسدد

~~~text
عمولة المنصة
4,000 ر.ي
عن سبتمبر 2026
غير مسدد
~~~

### مسدد

~~~text
عمولة المنصة
0 ر.ي مستحق
كشف سبتمبر تمت تسويته ✓
~~~

### متأخر

~~~text
عمولة المنصة
4,000 ر.ي
متأخر عن التسوية
~~~

### الضغط

يفتح شاشة:

**حساب المنصة**

وتعرض:

- إجمالي المبيعات.
- نسبة العمولة.
- قيمة العمولة.
- المسدد.
- المتبقي.
- فترة الكشف.
- حالة الكشف.
- تاريخ الاستحقاق.
- سجل الأشهر السابقة.

> لا يُضاف وضع الترخيص إلى Dashboard Header؛ قرار Header الحالي مستقل.

---

# 12. شاشة "حساب المنصة"

الأقسام:

### الكشف الحالي

- الشهر.
- المبيعات.
- النسبة.
- العمولة.
- المدفوع.
- المتبقي.
- الحالة.

### سجل الكشوف

مثال:

~~~text
سبتمبر 2026  —  4,000  —  مستحق
أغسطس 2026   —  3,200  —  مسدد
يوليو 2026   —  2,900  —  مسدد
~~~

### التفاصيل

يجب إتاحة الانتقال إلى تفاصيل المبيعات المستخدمة في حساب الكشف ضمن الصلاحيات التي يوافق عليها نموذج البيانات.

---

# 13. إغلاق الشهر والتسوية

## العملية الأساسية

~~~text
Month ends
    ↓
Generate statement
    ↓
Calculate from approved sales
    ↓
Freeze statement snapshot
    ↓
User pays platform commission
    ↓
Admin records settlement
    ↓
Statement = SETTLED
    ↓
Remaining due = 0
    ↓
Next month starts separately
~~~

## التسوية

عند الضغط على:

**تسوية كشف سبتمبر**

يُسجل:

- statementId.
- subscriberId.
- amount.
- settlement date/time.
- admin identity.
- payment reference.
- method/notes إذا تم اعتمادها.
- snapshot of relevant totals.
- audit event.

### قاعدة "التصفير"

التصفير يعني:

~~~text
currentBalance = 0
~~~

ولا يعني:

~~~text
DELETE September statement
~~~

التاريخ يبقى كاملًا.

---

# 14. التسوية اليدوية من لوحة الإدارة

ملف الشبكة في لوحة الإدارة يجب أن يحتوي على:

**الكشف الحالي**

**زر: تسوية**

**زر: فتح التفاصيل**

**سجل التسويات**

بعد نجاح التسوية:

- يتغير وضع الكشف إلى SETTLED.
- يظهر داخل تطبيق الشبكة.
- ترسل إشعارات نجاح التسوية.
- لا يمكن الضغط على "تسوية" مرة ثانية لنفس الكشف بطريقة تؤدي لتسجيل دفع مزدوج.
- العملية تكون idempotent.

---

# 15. سياسة المتأخرات والإيقاف

لا ينبغي أن يتحول غياب الإنترنت تلقائيًا إلى "مستخدم غير مسدد".

التسلسل المقترح:

~~~text
DUE
 ↓
GRACE PERIOD
 ↓
PAST_DUE
 ↓
SUSPENSION
~~~

مدة السماح تكون **إعدادًا إداريًا قابلًا للتغيير** ويجب تثبيت القيمة قبل التنفيذ.

### عند الإيقاف

الخادم يعلن:

~~~text
licenseState = SUSPENDED
reason = UNSETTLED_COMMISSION
~~~

والتطبيق:

- يقرأ الحالة عند الاتصال.
- يعرض سببًا واضحًا.
- يمنع العمليات التي قرر التصميم أنها محمية.
- لا يحذف البيانات المحلية.
- لا يمسح المخزون.
- لا يمسح السجل.
- لا يمنع الوصول إلى شاشة الدعم/الحالة/المزامنة ما لم تعتمد سياسة أقوى.

### Offline Grace

يجب أن تكون هناك سياسة تحفظ تشغيل التطبيق لفترة محدودة في حال انقطاع الإنترنت، مع عدم السماح بتحايل بسيط عن طريق تغيير ساعة الجهاز.

التفاصيل الدقيقة للمدة وسياسة الوقت الموثوق تُحسم في مرحلة الأمان.

---

# 16. التفعيل عن بُعد

بدل Activation Key:

~~~text
User submits phone + network name
          ↓
Admin sees subscriber
          ↓
Admin presses Activate
          ↓
Server updates license
          ↓
App syncs
          ↓
ACTIVE
~~~

### لا يوجد

- إدخال رمز تفعيل يدوي.
- حفظ مفتاح تفعيل داخل APK.
- مفتاح واحد مشترك لجميع المستخدمين.

---

# 17. الإشعارات الحية

الاستخدام الأساسي سيكون Firebase Cloud Messaging.

السيناريو:

~~~text
Admin Web
   ↓
Create notification
   ↓
Authorized backend
   ↓
FCM
   ↓
Android App
~~~

الأهداف:

- مشترك واحد.
- مجموعة مشتركين.
- جميع المشتركين.

أنواع الرسائل:

- إشعار عام.
- إشعار تسوية.
- تنبيه عمولة مستحقة.
- تنبيه قرب الاستحقاق.
- إشعار تعليق الحساب.
- إشعار إعادة التفعيل.
- تحديث/صيانة.
- رسالة إدارية.

### لا تكون الإشعارات هي مصدر الحقيقة

إذا وصل إشعار ولم يفتح التطبيق، تبقى الحالة الحقيقية محفوظة في الحساب والكشف.

الإشعار مجرد قناة إعلام.

---

# 18. لوحة التحكم Web Admin

## الصفحة الرئيسية

مؤشرات:

- إجمالي المشتركين.
- التجريبيون.
- المفعلون.
- المنتهية تجاربهم.
- المتأخرون.
- الموقوفون.
- مبيعات الفترة.
- عمولة المنصة المستحقة.
- عمولة تم تسويتها.
- عدد الكشوف المفتوحة.

## المشتركين

فلاتر:

- الحالة.
- الفترة.
- اسم الشبكة.
- رقم الهاتف.
- إصدار التطبيق.
- آخر اتصال.

## ملف المشترك

يعرض:

- الهوية.
- اسم الشبكة.
- الهاتف.
- الحالة.
- التجربة.
- الترخيص.
- الجهاز.
- آخر اتصال.
- الإصدار.
- المبيعات.
- العمولة.
- الكشوف.
- التسويات.
- الإشعارات.
- سجل الأحداث.

## التحكم

- Activate.
- Suspend.
- Reactivate.
- Extend Trial.
- Change Commission Policy.
- Record Settlement.
- Send Notification.
- Reset/Replace Device وفق سياسة موثقة.

---

# 19. إعدادات العمولة في الإدارة

قسم:

**إعدادات منصة NET**

يتضمن:

- النسبة العامة.
- سياسة التقريب.
- العملة.
- بداية/نهاية الدورة الشهرية.
- تاريخ الاستحقاق.
- مدة السماح.
- سياسة التعليق.
- هل التسوية الجزئية مسموحة.
- هل يوجد حد أدنى للعمولة.
- سياسة التعديلات بعد إغلاق الكشف.

كل تغيير حساس يجب تسجيله في Audit Log.

---

# 20. النموذج المقترح في Firestore

الأسماء قابلة للتعديل قبل التنفيذ، لكن الحدود المنطقية يجب الحفاظ عليها.

~~~text
/subscribers/{subscriberId}
/subscriber_devices/{deviceId}
/licenses/{licenseId}
/commission_policies/{policyId}
/commission_statements/{statementId}
/settlements/{settlementId}
/sales_sync_events/{eventId}
/admin_notifications/{notificationId}
/admin_notification_deliveries/{deliveryId}
/audit_events/{eventId}
/app_config/{configId}
~~~

لا تضع البيانات الحساسة في Collection يمكن لأي عميل تعديلها.

---

# 21. صلاحيات Firestore

المبدأ:

- العميل يقرأ/يكتب فقط ما يخص هويته والحقول المسموح بها.
- لا يسمح للعميل بتعديل:
  - commissionAmount
  - commissionRate التاريخية داخل كشف مغلق
  - settlement status
  - license state
  - admin fields
  - audit records
- العمليات الإدارية الحساسة تمر عبر backend موثوق.
- قواعد Firestore تُختبر قبل الإنتاج.
- يجب استخدام App Check ضمن التصميم الأمني بحسب الخدمات والمسار النهائي.

---

# 22. Cloud Functions / Server-side Logic

الأعمال الحساسة التي تحتاج سلطة مركزية توضع في backend، مثل:

- اعتماد المشترك.
- تفعيل/تعليق الترخيص.
- إنشاء كشف عمولة.
- احتساب العمولة.
- تسجيل التسوية.
- تطبيق التعديلات.
- إرسال إشعارات إدارية.
- مهام الدورات الشهرية.
- reconciliation.
- التحقق من idempotency.
- تسجيل العمليات الإدارية.

**ممنوع نقل مفاتيح الإدارة أو أسرار الخدمة إلى APK.**

---

# 23. الأمان ومكافحة العبث

هذه المنظومة تحتوي على قيمة مالية، لذلك لا يكفي إخفاء واجهة العمولة.

يجب تصميم:

- App Check.
- Authentication.
- Firestore Security Rules.
- Server-side authorization.
- Audit Log.
- Idempotency.
- Device binding.
- توقيع/سلامة الطلبات حيث يلزم.
- حماية من إعادة إرسال الطلبات.
- منع تعديل كشف مغلق.
- منع تكرار Settlement.
- سياسة موثوقة للوقت.
- حماية بيانات الاعتماد السرية.
- عدم تخزين أسرار الإدارة داخل APK.
- التعامل مع إعادة تثبيت التطبيق واستبدال الجهاز.
- مراقبة حالات App Check/Authentication الفاشلة.

Firebase توثق أن App Check يساعد في تقييد الوصول إلى موارد Firebase للتطبيقات/الأجهزة المصرح بها، كما أن Firestore Security Rules تضبط الوصول والتحقق من البيانات للعملاء، وFCM يوفر قناة الإشعارات لأجهزة Android. 

---

# 24. الاختبارات المطلوبة

## Domain

- حساب نسبة العمولة.
- تقريب الكسور.
- تجميد كشف.
- التسوية.
- التصفير دون حذف التاريخ.
- تغيير النسبة بين الشهور.
- Override لمشترك.
- إلغاء/تعديل الكشف.
- idempotency.

## Sync

- Offline → Online.
- إعادة إرسال نفس البيع.
- انقطاع أثناء الرفع.
- انقطاع بعد نجاح الخادم وقبل تأكيد العميل.
- تعارض.
- إعادة تثبيت التطبيق.
- تبديل جهاز.

## License

- Trial 30 days.
- Trial expiry.
- Activation.
- Suspension.
- Reactivation.
- Offline grace.
- تغيير وقت الجهاز.
- عدم وجود إنترنت.
- فقد FCM token.

## Admin

- صلاحيات المدير.
- تعديل النسبة.
- إنشاء كشف.
- تسوية.
- تعليق/إعادة تفعيل.
- إشعار فردي/جماعي.

## Android

- foreground notification.
- background notification.
- permission notification Android 13+.
- tap notification → correct screen.
- reconnect sync.
- startup state.
- blocked/suspended state.

---

# 25. سيناريو End-to-End نهائي

### المشترك الجديد

~~~text
Install
 ↓
Registration
 ↓
Phone + Network Name
 ↓
TRIAL 30 days
 ↓
Admin sees subscriber
 ↓
Admin Activate
 ↓
ACTIVE
~~~

### البيع

~~~text
Sale completed locally
 ↓
Local audit / ledger
 ↓
Sync queue
 ↓
Server reconciliation
 ↓
Included in statement period
~~~

### إغلاق الشهر

~~~text
End of month
 ↓
Statement generated
 ↓
Gross sales = 200,000
 ↓
Rate = 2%
 ↓
Commission = 4,000
~~~

### التطبيق

~~~text
عمولة المنصة
4,000 ر.ي
غير مسدد
~~~

### السداد

~~~text
User pays
 ↓
Admin records settlement
 ↓
Statement SETTLED
 ↓
Current due = 0
 ↓
History preserved
~~~

### عدم السداد

~~~text
DUE
 ↓
Grace
 ↓
PAST_DUE
 ↓
SUSPENDED
~~~

### بعد التسوية

~~~text
Admin Reactivate
 ↓
App sync
 ↓
ACTIVE
~~~

---

# 26. المراحل التنفيذية

## L0 — Specification Freeze
**الحالة الحالية: مسموح**

لا يوجد كود.

المهام:
- تثبيت هذه الوثيقة.
- تثبيت المصطلحات.
- حسم الأسئلة المفتوحة.
- عدم تعديل المنتج.

**Exit:** موافقة صاحب المشروع على specification.

---

## L1 — V1 Release Gate
**الحالة: BLOCKED حتى اكتمال المنتج**

لا يبدأ عمل الترخيص.

المهام:
- إغلاق جميع فجوات V1.
- CI.
- Android real-device.
- Offline-first.
- backup/restore.
- release candidate.
- جاهزية النشر.

**Exit:** V1 Stable / Ready for Release.

---

## L2 — Central Platform Foundation

بعد فتح البوابة:

- إنشاء Firebase production project.
- تنظيم Auth.
- Firestore.
- Security Rules.
- App Check.
- Cloud Functions.
- بيئات dev/staging/prod.
- Admin identity model.
- Audit foundation.

**Exit:**  
اتصال آمن + rules tested + admin role model + no privileged secret in client.

---

## L3 — Subscriber / Trial / Device Binding

- التسجيل.
- 30-day Trial.
- subscriber profile.
- network name.
- device binding.
- Activate/Reject.
- Reinstall/replace-device policy.
- sync license state.

**Exit:**  
مشترك يمكن أن ينتقل من التسجيل إلى TRIAL ثم ACTIVE من الإدارة دون Activation Key.

---

## L4 — Sales Sync & Commission Foundation

- تحديد البيع المحتسب.
- مزامنة sales events.
- idempotency.
- reconciliation.
- commission policies.
- global rate.
- per-subscriber override.
- rounding rules.

**Exit:**  
يمكن استخراج إجمالي مبيعات فترة بشكل قابل للمطابقة.

---

## L5 — Monthly Commission Statements

- إنشاء الكشف.
- snapshot.
- freeze.
- historical periods.
- due date.
- past due.
- adjustment model.

**Exit:**  
كشف شهر كامل لا يتغير بصمت بعد إغلاقه.

---

## L6 — Settlements

- Admin settlement.
- payment reference.
- audit.
- idempotency.
- settled state.
- zero current due.
- historical preservation.

**Exit:**  
يمكن تسوية كشف كامل بأمان دون تكرار أو فقد تاريخ.

---

## L7 — Admin Web Dashboard

- subscribers.
- subscriber profile.
- commissions.
- statements.
- settlements.
- policy settings.
- remote actions.
- audit.
- filters/search.

**Exit:**  
الإدارة تستطيع إدارة دورة المشترك والعمولة من مكان واحد.

---

## L8 — FCM & Remote Control

- FCM registration.
- token lifecycle.
- targeted notifications.
- broadcast notifications.
- settlement notifications.
- due/suspension notices.
- Remote license state sync.
- event acknowledgments.

**Exit:**  
إشعار وحالة مركزية تصل إلى التطبيق بشكل موثوق نسبيًا مع معالجة فقد/تأخر الإشعار.

---

## L9 — Android UX Integration

- شاشة التسجيل.
- Trial state.
- Activated state.
- Expired state.
- Commission card.
- Account/Commission screen.
- Due/Past-due UI.
- Suspended UI.
- Reactivation state.
- notification handling.

**Exit:**  
كل حالة مركزية لها واجهة واضحة ولا تكسر مسارات التطبيق الأساسية.

---

## L10 — Security Hardening

- Rules review.
- App Check enforcement strategy.
- backend authorization review.
- replay/idempotency.
- device abuse.
- clock tampering.
- offline grace.
- secret scanning.
- audit completeness.
- data access review.

**Exit:**  
مراجعة أمنية نهائية قبل إدخال مشتركين حقيقيين.

---

## L11 — Staging / Pilot

- Firebase staging.
- مجموعة اختبار محدودة.
- مبيعات حقيقية تجريبية.
- كشف شهري تجريبي.
- Settlement حقيقي محدود.
- notifications.
- suspend/reactivate.
- recovery tests.

**Exit:**  
لا توجد خسارة أو مضاعفة أو عدم تطابق في الدورة المالية التجريبية.

---

## L12 — Production Rollout

الترتيب:

~~~text
Internal
  ↓
Pilot
  ↓
Small controlled rollout
  ↓
Production
~~~

مع مراقبة:

- sync errors.
- auth failures.
- notification failures.
- duplicate events.
- commission mismatches.
- suspended accounts.
- device binding anomalies.

**Exit:**  
اعتماد Production Launch.

---

# 27. معايير القبول النهائية

لا تعتبر الخطة مكتملة حتى تتحقق جميع النقاط:

- [ ] التسجيل يعمل.
- [ ] Trial 30 days يعمل.
- [ ] لا يوجد Activation Key.
- [ ] الإدارة ترى المشترك.
- [ ] الإدارة تفعل المشترك.
- [ ] اسم الشبكة ينتقل إلى التطبيق وقوالبه.
- [ ] الجهاز يرتبط بسياسة واضحة.
- [ ] المبيعات تُزامن بدون تكرار.
- [ ] إجمالي المبيعات قابل للمطابقة.
- [ ] النسبة العامة تعمل.
- [ ] النسبة الخاصة تعمل.
- [ ] النسبة التاريخية محفوظة لكل كشف.
- [ ] كشف الشهر لا يُعاد حسابه بصمت بعد الإغلاق.
- [ ] عمولة المنصة تظهر في التطبيق.
- [ ] سجل الأشهر محفوظ.
- [ ] التسوية تسجل كعملية مستقلة.
- [ ] بعد التسوية يصبح المستحق الحالي صفرًا.
- [ ] لا يتم حذف التاريخ.
- [ ] التعليق عن عدم السداد يعمل وفق سياسة معتمدة.
- [ ] Offline grace مصمم ومختبر.
- [ ] إعادة التفعيل تعمل.
- [ ] FCM يعمل في foreground/background ضمن حدود Android.
- [ ] إشعارات فردية وجماعية تعمل.
- [ ] Security Rules مقيدة.
- [ ] App Check ضمن التصميم النهائي.
- [ ] لا توجد أسرار إدارية في APK.
- [ ] كل العمليات الحساسة Audit logged.
- [ ] اختبارات E2E ناجحة في staging.
- [ ] Pilot ناجح.
- [ ] اعتماد Production.

---

# 28. أسئلة يجب حسمها قبل فتح L2

هذه ليست فراغات تسمح للوكيل بالاختراع، بل قرارات يجب اعتمادها من صاحب المشروع:

1. ما النسبة العامة الافتراضية؟
2. هل يسمح بنسبة خاصة لكل شبكة؟
3. هل عمولة الشبكة على إجمالي مبيعاتها فقط أم توجد استثناءات؟
4. هل مبيعات نقاط البيع تدخل كاملة في عمولة المنصة؟ وإذا كانت هناك عمولة POS منفصلة، كيف تمنع ازدواجية الحساب؟
5. هل توجد تسوية جزئية أم فقط تسوية كاملة؟
6. ما يوم إغلاق الشهر؟
7. ما تاريخ الاستحقاق؟
8. كم مدة السماح قبل الإيقاف؟
9. ما الذي يبقى متاحًا أثناء الإيقاف؟
10. هل الحساب يرتبط بجهاز واحد أم يسمح بعدة أجهزة مستقبلًا؟
11. ما سياسة تغيير الجهاز؟
12. هل تغيير اسم الشبكة يحتاج اعتماد إدارة؟
13. ما آلية التحقق من رقم الهاتف النهائية؟
14. ما سياسة التعامل مع إعادة تثبيت التطبيق؟
15. هل توجد فترة سماح إضافية بعد انتهاء Trial؟
16. ما العملة الرسمية للعمولة؟
17. ما سياسة التقريب؟
18. ما سياسة الإرجاع/الاسترداد وتأثيرها على عمولة شهر مغلق؟
19. ما سياسة التعديلات المحاسبية؟
20. ما الحد الأدنى من بيانات المبيعات التي تحفظ مركزيًا؟

**حتى تتم الإجابة على هذه الأسئلة، لا يجوز للوكيل افتراض قيم تجارية من عنده.**

---

# 29. قواعد التنفيذ للوكيل عند فتح الخطة

عند فتح بوابة V1 مستقبلًا:

1. اقرأ هذه الوثيقة كاملة قبل أي تعديل.
2. اقرأ docs/product-decisions.md وdocs/contracts.md وdocs/خطة-تحويل-منطق-NET-إلى-نظام-حقيقي.md.
3. لا تنشئ Architecture موازية أو نظام Ledger منفصل عن Domain الحالي.
4. لا تستخدم Mock/Fake كمنطق إنتاجي.
5. لا تنشئ scripts لتنفيذ مهام/عمليات المنتج.
6. لا تضع أسرار Firebase/Admin داخل التطبيق.
7. لا تعيد تعريف "المبيعات" دون قرار منتج.
8. كل تعديل مالي يجب أن يكون idempotent وقابلًا للمراجعة.
9. أي قرار تجاري جديد يُسجل أولًا في docs/product-decisions.md.
10. نفذ مرحلة واحدة فقط في كل مرة، ولا تتجاوز Exit Criteria للمرحلة.
11. لا تبدأ L3 قبل نجاح L2.
12. لا تبدأ L4 قبل نجاح L3.
13. لا تبدأ L5 قبل نجاح L4.
14. وهكذا حتى L12.
15. أي فشل في Gate يعيد الحالة إلى BLOCKED.

---

# 30. مراجع تقنية رسمية

هذه المراجع استُخدمت فقط لتثبيت الاتجاه التقني العام، وليس لتجاوز قرارات المنتج.

- Firebase Cloud Messaging — Android
- Firebase App Check
- Firebase Authentication for Flutter / Phone Authentication
- Cloud Firestore Security Rules

يجب إعادة التحقق من الإصدارات والقيود الفعلية عند فتح L2 لأن هذه الوثيقة خطة مستقبلية وليست تثبيتًا لأرقام حزم أو API versions.

---

## الحالة النهائية لهذه الوثيقة

~~~text
SPECIFICATION = APPROVED FOR DOCUMENTATION
IMPLEMENTATION  = BLOCKED
PRIORITY        = AFTER V1
TRIGGER         = V1 Stable + Ready for Release
NEXT AUTHORIZED = L2 only after Gate
~~~

**لا يوجد في هذه الوثيقة أي إذن لبدء تنفيذ الخطة الآن.**
