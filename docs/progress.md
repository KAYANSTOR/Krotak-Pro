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
- `PaymentFingerprintService`: بصمة مستقلة عن القناة
- `UnifiedPaymentEventEngine`: parse → fingerprint → persist → PD-07 → TransferProcessor
- `IncomingSmsHandler` أصبح محوّل قناة نحو المحرك الموحّد
- اختبارات: `test/services/unified_payment_event_engine_test.dart`

### Phase 3 — Wallet Notifications (2026-09-13) 🟡 منفذة في المستودع / بانتظار تحقق الجهاز
- Android `NotificationListenerService` مع allowlist لحزم المصادر.
- طابور نقل محلي مشفّع عبر Android Keystore مع `peek/ack` واستعادة بعد التوقف.
- `NotificationBridge` + `IncomingNotificationHandler` → `UnifiedPaymentEventEngine` نفسه.
- `LocalNotificationParser` مستقل ويخرج `PaymentEvent` موحدًا.
- `PaymentSource` محفوظ في `AppSettings` مع شاشة إعداد.
- يلزم التحقق بعينات حقيقية على جهاز Android.

### Phase 4 — Pending / Retry / Recovery Hardening (2026-09-13) 🟡 منفذة في المستودع / بانتظار إغلاق بوابة التحقق
- `failed` أصبح جزءًا من مسار recovery.
- retry policy ثابتة بحد 5 محاولات تلقائية وexponential backoff بحد أعلى 30 دقيقة.
- حالة retry وموعد المحاولة محفوظان في Audit Log الحالي.
- تشغيل recovery دوري كل دقيقة مع single-flight guard.
- إعادة المحاولة اليدوية متاحة حتى بعد الاستنفاد.
- فشل حفظ الإشعار محليًا يمنع ACK لتجنب فقدان حدث الدفع.
- شاشة للمشغّل لإعادة محاولة الرسائل الفاشلة + إعداد تشغيل/إيقاف auto retry.
- تقرير: [phase-4-pending-retry-recovery.md](phase-4-pending-retry-recovery.md)

### Phase 5 — Salafni (2026-09-13) 🟡 منفذة في المستودع / بانتظار إغلاق بوابة التحقق
- كيان `Advance` و`AdvanceRepository` كإسقاط من دفتر الحركات + سجل المبيعات، دون دفتر مالي ثانٍ أو جدول Drift جديد.
- خدمة `LocalAdvanceService`: التفعيل، طلب سلفني، اختيار أقل فئة نشطة ذات مخزون، الحجز، تسجيل الدين، إرسال الكرت، والتدقيق.
- Idempotency لطلب السلفة ولتسديد التحويلات.
- التسديد التلقائي موصول بمحرك `LocalTransferProcessor`؛ يسدد الدين أولًا ثم يعالج فقط المبلغ المتبقي في مسار الكرت المعتاد.
- رسائل القبول والرفض والسداد قابلة للتخصيص من الإعدادات.
- إعدادات: بطاقة تفعيل سلفني + شاشة قوالب رسائل سلفني.
- توثيق: [phase-5-salafni.md](phase-5-salafni.md)
- يلزم CI ناجح + اختبار جهاز Android حقيقي قبل Production Ready.

### Phase 6 — POS Ledger + Auto Settlement (2026-09-13) 🟡 منفذة في المستودع / بانتظار إغلاق بوابة التحقق
- ربط `PointOfSale` بحساب دفتر عبر `LocalPosAccountRegistry` (`pos_accounts`) دون جدول Drift جديد.
- `LocalPosSettlementService`: تعرف المعرف، تسوية ذرية (`deposit` + مرجع `pos-settle:`)، حساب المديونية المتبقية، Audit، وSMS تأكيدي.
- `LocalTransferProcessor` يحوّل الحوالة المطابقة لنقطة بيع إلى مسار التسوية بدل بيع الكرت عندما يكون الإعداد مفعّلًا.
- إعدادات: تفعيل التسوية التلقائية + قوالب النجاح/الفشل/غير المعروف.
- واجهة: معرف دفع عند إنشاء نقطة البيع + بطاقة إعداد وشاشة قوالب.
- اختبارات: `test/services/pos_auto_settlement_test.dart`
- توثيق: [phase-6-pos-ledger-auto-settlement.md](phase-6-pos-ledger-auto-settlement.md)

### Phase 7 — Bulk Card Import Performance (2026-09-13) 🟡 منفذة في المستودع / بانتظار قياس جهاز
- تحقق مسبق من الملف ثم إدخال مجمّع بدل حفظ صف-بصف.
- منع تكرار serial/secret داخل الملف وداخل المخزون قبل الاعتماد.
- تقدم حقيقي في شاشة الاستيراد + تقرير صفوف مرفوضة.
- توثيق: [phase-7-bulk-card-import.md](phase-7-bulk-card-import.md)

## المتبقي Post-V1 (الترتيب الرسمي)
8. Customer SMS Broadcast
9. Long Press Actions
10. UI/UX + Dark/Light Improvements

مرجع: NET-POST-V1-MASTER-PLAN — GitHub مصدر الحقيقة؛ لا Local Only.
