# تقدم تنفيذ خطة NET

## التحقق (2026-09-12)

```text
CI على main — analyze + test
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

## الدفعة B — مغلقة (2026-09-12)
B1…B8 مكتملة (إعدادات · معلّقة · مرفوضة · دفتر · فئات/كروت · مساعدة)

## متبقٍ Post-V1 (الترتيب الرسمي)
2. Unified Payment Event Engine
3. Wallet Notifications
4. Pending / Retry / Recovery Hardening
5. Salafni
6. POS Ledger + Auto Settlement
7. Bulk Card Import Performance
8. Customer SMS Broadcast
9. Long Press Actions
10. UI/UX + Dark/Light Improvements

مرجع: NET-POST-V1-MASTER-PLAN — GitHub مصدر الحقيقة؛ لا Local Only.
