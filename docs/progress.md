# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 28 — طلبات رصيد نقاط البيع (2026-09-20) ✅ برمجيًا
- مسار خاص لرمز طلب الرصيد (العينة `111`) يحل نقطة البيع من رقم المُرسل.
- حد يومي لكل نقطة + قالب رد الرصيد/الدين + شاشة إعداد.
- تقرير: [phase-28-pos-balance-requests.md](phase-28-pos-balance-requests.md)

### Phase 27 — مصدر واحد لملف نقطة البيع (2026-09-20) ✅ برمجيًا
- خدمة `LocalPosProfileService`: تحقق + إنشاء + تعديل + زرع القوالب من مسار واحد.
- ربط شاشتي المحافظ ودفتر نقاط البيع بالخدمة بدل تكرار المنطق في الواجهة.
- تقرير: [phase-27-pos-single-source.md](phase-27-pos-single-source.md)
