# Post-V1 Phase 3 — Wallet Notifications

**الحالة:** تنفيذ المستودع مكتمل مبدئيًا؛ لا تُعلن Production Ready قبل اختبار جهاز Android فعلي بعينات محافظ حقيقية.

## Architecture

```text
Android NotificationListenerService
  -> encrypted native pending queue
  -> Flutter NotificationBridge
  -> LocalNotificationParser
  -> UnifiedPaymentEventEngine
  -> MessageParser / PD-07 / TransferProcessor
```

## Implemented

- Android `NotificationListenerService` مسجل بالصلاحية النظامية المطلوبة.
- allowlist للحزم؛ لا تتم قراءة/معالجة تطبيقات غير مهيأة.
- طابور نقل محلي مشفر بـ Android Keystore، مع حد أقصى 200 إشعار.
- `peek` ثم `ack`؛ لا حذف للنقل قبل قبول محرك الأحداث الموحد أو اكتشاف التكرار.
- EventChannel للأحداث الحية عندما تكون واجهة Flutter نشطة.
- استعادة الأحداث المتراكمة عند تشغيل التطبيق.
- `PaymentSource` registry محفوظ ضمن `AppSettings` مع تفعيل/تعطيل/حذف المصدر.
- شاشة إعداد «إشعارات المحافظ» وفتح إعدادات Notification Access.
- `LocalNotificationParser` مستقل عن `LocalMessageParser` لكنه ينتج `PaymentEvent` موحدًا.
- لا توجد جداول Drift جديدة؛ لا يوجد دفتر مالي موازٍ.
- CI أصبح يشمل `flutter build apk --debug` بالإضافة إلى التحليل والاختبارات.

## Intentional constraints

أسماء حزم المحافظ وصيغ الإشعارات لا تُخمن. يجب إدخال الحزمة الفعلية والتحقق منها على الجهاز، ثم إضافة عينات منزوعة البيانات إلى اختبارات parser قبل اعتماد قوالب إنتاج لمحفظة بعينها.

## Verification gate

1. `dart analyze lib test`
2. `flutter analyze --no-fatal-infos`
3. `flutter test`
4. `flutter build apk --debug`
5. جهاز Android فعلي: منح Notification Access.
6. إشعار دفع حقيقي من مصدر مهيأ → يظهر كـ `PaymentEvent(channel=notification)`.
7. إعادة نفس الإشعار → لا تتكرر الحركة المالية.
8. قتل التطبيق قبل المعالجة ثم تشغيله → تتم استعادة الإشعار من الطابور.
9. فشل المعالجة التجارية → يبقى `IncomingMessage` متاحًا للمراجعة/الاستعادة.
