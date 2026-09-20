# NET Flutter

تطبيق Android لإدارة بيع كروت الإنترنت والتحويلات عبر SMS وإشعارات المحافظ، مع تشغيل محلي Offline-first ومعالجة Domain حقيقية.

## وظيفة النظام

NET يعمل على هاتف صاحب الشبكة/المشغّل. يستقبل التحويلات، يحللها حسب القوالب ومصادر الدفع، يطابق العميل أو نقطة البيع، يطبق قواعد الرصيد والعمولة والمخزون، يحجز الكرت، يسجل العملية، ويرسل بيانات الكرت عبر SMS.

يشمل النظام أيضًا العملاء والحسابات، مخزون وفئات الكروت، البيع المباشر، نقاط البيع، التسويات، سلفني، العروض والمكافآت، الرسائل المعلّقة/المرفوضة والاستعادة، التقارير، النسخ الاحتياطي، التشخيص وإدارة الأذونات.

## الحالة الحالية

- الإصدار: `1.0.13+13`
- الفرع المرجعي: `main`
- التوزيع الحالي: APK مباشر؛ Google Play مؤجل.
- التوثيق الكامل للميزات: [دليل النظام](docs/system-guide.md)
- حماية توقيع APK والإصدار: [دليل أمان الإصدار](docs/apk-release-security.md)
- خطة التوزيع الحالية: [خطة التوزيع](docs/distribution-plan.md)
- تقدم التنفيذ: [docs/progress.md](docs/progress.md)

## المعمارية

`Flutter UI → AppContainer → Domain Services → Repositories → Drift/SQLite`

وعند وصول دفع من Android:

`SMS/Notification → Native Bridge → Payment Engine → Parser → Customer/POS → Inventory → Sale → SMS → Audit/Recovery`

## متطلبات التشغيل والتطوير

```bash
flutter pub get
flutter test
```

لبناء Release APK يجب تجهيز توقيع محمي عبر متغيرات البيئة/أسرار موثوقة. لا يوجد fallback إلى debug signing في Release.

## التوقيع والنشر

مفتاح Release الخاص لا يوجد داخل Git. CI يعتمد على:

- `APK_KEYSTORE_B64`
- `APK_KEYSTORE_PASSWORD`
- `APK_KEY_PASSWORD`

CI ينشئ APK ويولد SHA-256، ثم ينشرهما في GitHub Release. يمكن استخدام نفس ملف APK كنسخة التوزيع على MediaFire.

## ملاحظات الأمان

التطبيق يتعامل وظيفيًا مع SMS وإشعارات وبيانات معاملات؛ لذلك يجب أن تكون سياسة الخصوصية والأذونات متوافقة مع الوظائف الفعلية، ولا يحاول الإصدار تجاوز Google Play Protect.

## التحقق الميداني

الاختبارات الآلية تمر عبر CI، لكن بعض وظائف Android — خصوصًا SMS والخلفية وSIM — تحتاج تحققًا على جهاز Android حقيقي. راجع [مرحلة تحقق الجهاز](docs/phase-12-device-verification.md).
