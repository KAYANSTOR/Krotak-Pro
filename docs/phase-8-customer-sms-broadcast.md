# Phase 8 — Customer SMS Broadcast

**تاريخ:** 2026-09-13

## الهدف

تمكين صاحب الشبكة من إرسال رسالة إدارية جماعية للعملاء المسجلين، مع استبعاد المحظورين والأرقام التالفة، وتأكيد صريح قبل الإرسال، وتسجيل نتيجة كل مستلم.

## ما تم تنفيذه

- كيانات `BroadcastJob` و`BroadcastRecipient` مع الحالات: draft / confirmed / running / paused / completed / partiallyFailed / failed / cancelled.
- `LocalBroadcastRepository` يخزن المهام في إعداد `broadcast_jobs` دون جدول Drift جديد.
- `LocalBroadcastService`: معاينة المستلمين، تأكيد بكلمة `إرسال`، إرسال عبر `MessageSender` الحالي، منع تكرار المهمة بنفس النص والمستلمين، إيقاف وإلغاء.
- المستلم المؤهل: عميل `active` يملك رقم هاتف قابل للتطبيع. يُستبعد `blacklisted` و`merged` و`archived` ومن بلا رقم صالح.
- رسائل البث الإداري لا تستهلك رصيد ترخيص الكروت.
- واجهة `BroadcastScreen` من الإعدادات: نص، ملخص المستلمين، تأكيد، شريط تقدم، نتيجة نهائية.
- اختبارات: `test/services/broadcast_service_test.dart`.

## بوابة التحقق المتبقية

- قياس معدل الإرسال على جهاز Android حقيقي مع سياسة المشغّل.
- مراجعة صلاحيات SMS ومتطلبات Google Play قبل الإصدار.
