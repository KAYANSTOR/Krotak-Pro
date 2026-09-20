# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 28 — طلب رصيد نقطة البيع (2026-09-20)
- مسار مستقل لرمز طلب الرصيد من رقم المرسل مع حد يومي وقالب الرد.
- تقرير: [phase-28-pos-balance-request.md](phase-28-pos-balance-request.md)

### Phase 27 — مصدر واحد لملف نقطة البيع (2026-09-20) ✅ برمجيًا
- خدمة `LocalPosProfileService`: تحقق + إنشاء + تعديل + زرع القوالب من مسار واحد.
- ربط شاشتي المحافظ ودفتر نقاط البيع بالخدمة بدل تكرار المنطق في الواجهة.
- تقرير: [phase-27-pos-single-source.md](phase-27-pos-single-source.md)

### Phase 17 — Promotion Reward Reversal (2026-09-16) ✅ في المستودع
- عكس مكافأة العرض عند reverseSale.
- تقرير: [phase-17-promotion-reward-reversal.md](phase-17-promotion-reward-reversal.md)

### Phase 22 — فتح ملف العميل وتصدير الكشف (2026-09-19) ✅ برمجيًا
- فتح `CustomerDetailScreen` من شارة العميل الموجود في ورقة البيع المباشر.
- نسخ/حفظ كشف حساب نصي من شاشة تفاصيل العميل.
- تقرير: [phase-22-customer-file-and-statement-export.md](phase-22-customer-file-and-statement-export.md)

### Phase 23 — مؤشرات لوحة التحكم من مطابقة الفيديو (2026-09-19) ✅ برمجيًا
- حلقة تقدّم حول عدّاد الحسابات في الكرت الكبير.
- تمييز بصري لبطاقة مبيعات اليوم / الشهر المختارة.
- تقرير: [phase-23-dashboard-video-parity-visuals.md](phase-23-dashboard-video-parity-visuals.md)

### Phase 24 — طريقة التسوية وأرشيف الرسائل (2026-09-19) ✅ برمجيًا
- أيقونات وطريقة دفع مميّزة في كشف تسوية نقاط البيع، مع ترميز الطريقة في المرجع القائم.
- تاريخ عربي تفصيلي على بطاقات أرشيف الرسائل المحلولة.
- تقرير: [phase-24-settlement-method-and-archive-dates.md](phase-24-settlement-method-and-archive-dates.md)

### Phase 25 — تصدير كشف الحساب نصًا وصورة (2026-09-19) ✅ برمجيًا
- ورقة تصدير من تفاصيل العميل: نسخ، حفظ نص، حفظ صورة PNG.
- بلا حزمة PDF جديدة وبلا تغيير على Domain.
- تقرير: [phase-25-customer-statement-image-export.md](phase-25-customer-statement-image-export.md)

المراحل السابقة موثقة في المستودع. المتبقي الغير برمجي: تحقق جهاز حقيقي (مرحلة 12).
