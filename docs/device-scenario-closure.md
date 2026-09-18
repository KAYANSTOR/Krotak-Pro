# إغلاق سيناريوهات الجهاز (تكرار / صلاحيات / استرداد / Boot)

**تاريخ:** 2026-09-18

## 1) تكرار SMS / Idempotency

| السيناريو | المتوقع | أين يُغلق |
|-----------|---------|-----------|
| نفس الرسالة مرتين | لا بيع مزدوج | `PaymentFingerprintService` + unique `external_reference` |
| نفس المرجع من SMS وإشعار | حدث واحد | fingerprint بدون قناة |
| نفس `operationId` بعد فشل SMS | لا كرت ثانٍ | `LocalTransferProcessor` + `voucher_committed` |
| إعادة فتح التطبيق أثناء SENDING | إكمال إرسال فقط | `MessageDeliveryWorker` |

## 2) صلاحيات Android

| صلاحية | الاستخدام | ملف |
|--------|-----------|-----|
| SMS | استقبال/إرسال | Manifest + SmsBridge |
| READ_CONTACTS | جهات الاتصال | Phase 8 |
| POST_NOTIFICATIONS / Notification Listener | محافظ | NotificationListener |
| WAKE_LOCK | خلفية | Manifest |
| BOOT_COMPLETED | استئناف | BootReceiver |
| تجاهل تحسين البطارية | onboarding | PermissionsOnboarding |

## 3) استرداد

| السيناريو | السلوك |
|-----------|--------|
| فشل SMS بعد `voucher_committed` | status=failed → worker يعيد الإرسال بنفس cardId |
| timeout 15 دقيقة على sending/pending | worker يعيد المحاولة |
| max attempts | failedMaxAttempts + لا كرت جديد |

## 4) Boot

| الخطوة | التنفيذ |
|--------|---------|
| استقبال BOOT_COMPLETED | BootReceiver |
| تشغيل MainActivity | NEW_TASK |
| runRecoveryPass | AppContainer بعد الإقلاع |

## 5) قائمة تحقق تشغيل (مشغّل)

انظر `docs/launch-readiness-checklist.md`.

لا يُعتبر الإصدار جاهزًا إلا بعد تصدير حزمة الأدلة من شاشة تحقق الجهاز على Android حقيقي.
