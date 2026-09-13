# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 1 — Identity Engine (2026-09-12) ✅ في المستودع
- `PhoneNormalizer`: توحيد 0777 / +967 / 00967 → canonical
- `LocalCustomerRepository.findByIdentifier`: بحث بكل مفاتيح lookup
- `LocalCustomerService`: حفظ الهاتف بصيغة canonical
- `LocalCustomerIdentityResolver`: تطبيع قبل الحل + deliveryPhone canonical
- Merge الموجود: ينقل المعرّفات + Audit؛ التحقق باختبار الصيغ المتعددة
- اختبارات: `test/domain/phone_normalizer_test.dart` · `test/services/identity_engine_test.dart`

### Phase 2 — Unified Payment Event Engine (2026-09-13) ✅ في المستودع
- `PaymentEvent` / `PaymentChannel` / `PaymentSource` / `PaymentFingerprint`
- `PaymentFingerprintService`: بصمة مستقلة عن القناة (SMS ≡ إشعار لنفس المرجع)
- `UnifiedPaymentEventEngine`: parse → fingerprint → persist → PD-07 → TransferProcessor
- `IncomingSmsHandler` أصبح محوّل قناة نحو المحرك الموحّد
- اختبارات: `test/services/unified_payment_event_engine_test.dart`
- تقرير: [phase-2-unified-payment-event-engine.md](phase-2-unified-payment-event-engine.md)

### Phase 3 — Wallet Notifications (2026-09-13) 🟡 منفذة في المستودع / بانتظار تحقق الجهاز
- `NotificationListenerService` Android مع allowlist لحزم المصادر.
- طابور نقل محلي مشفّر عبر Android Keystore مع `peek/ack` واستعادة بعد توقف التطبيق.
- `NotificationBridge` + `IncomingNotificationHandler` → `UnifiedPaymentEventEngine` نفسه، بدون دفتر أو مسار مالي ثانٍ.
- `LocalNotificationParser` مستقل ويخرج `PaymentEvent` موحدًا.
- سجل `PaymentSource` محفوظ في `AppSettings` مع شاشة إعداد للتفعيل/التعطيل/الحذف.
- لا يتم افتراض أسماء حزم المحافظ أو قوالبها؛ يلزم التحقق بعينات حقيقية على جهاز Android.
- التقرير: [phase-3-wallet-notifications.md](phase-3-wallet-notifications.md)

## الدفعة B — مغلقة (2026-09-12)
B1…B8 مكتملة (إعدادات · معلّقة · مرفوضة · دفتر · فئات/كروت · مساعدة)

## المتبقي Post-V1 (الترتيب الرسمي)
4. Pending / Retry / Recovery Hardening
5. Salafni
6. POS Ledger + Auto Settlement
7. Bulk Card Import Performance
8. Customer SMS Broadcast
9. Long Press Actions
10. UI/UX + Dark/Light Improvements

مرجع: NET-POST-V1-MASTER-PLAN — GitHub مصدر الحقيقة؛ لا Local Only.
