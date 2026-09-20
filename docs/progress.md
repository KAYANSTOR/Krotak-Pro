# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 33 — الأرقام المحظورة (2026-09-20) ✅ برمجيًا
- قائمة مستقلة عن حالة العميل `blacklisted`، مخزّنة في `SettingKeys.blockedPhones`.
- رفض المرسِل أو أي رقم في جسم الرسالة قبل `parse` ودون إيداع.
- شاشة «الأرقام المحظورة» من الإعدادات.
- تقرير: [phase-33-blocked-numbers.md](phase-33-blocked-numbers.md)

### Phase 32 — التسوية التلقائية لنقاط البيع (2026-09-20) ✅ برمجيًا
- حوالة محفظة يطابق معرفها نقطة بيع نشطة تُقي’د إيداعاً `pos-settle:{posId}:{ref}` دون بيع كرت.
- Audit `pos_auto_settled` + SMS بـ `{SETTLEMENT_AMOUNT}` / `{REMAINING_BALANCE}`.
- تقرير: [phase-32-pos-auto-settlement.md](phase-32-pos-auto-settlement.md)

### Phase 31 — تسعير الجملة بعد نسبة العمولة (2026-09-20) ✅ برمجيًا
- `PosPercentageMode` يسعّر كرت نقطة البيع: خصم عمولة الفئة أو الوجه الكامل عند 0%.
- طلب POS يُقي’د بالصافي كمديونية دون إيداع مقابل.
- تقرير: [phase-31-pos-wholesale-pricing.md](phase-31-pos-wholesale-pricing.md)

### Phase 30 — الشحن الفوري لرقم ثالث (2026-09-20) ✅ برمجيًا
- كلمة «شحن / أرسل كرت» تقيّد العملية على رقم المُرسل وتسلّم الكرت لرقم الجسم.
- تأكيد SMS لنقطة البيع بعد نجاح التسليم + قالب POS سادس.
- تقرير: [phase-30-pos-instant-charge.md](phase-30-pos-instant-charge.md)

### Phase 29 — طلب أكثر من كرت لنقطة البيع (2026-09-20) ✅ برمجيًا
- العدد الاختياري في رسالة نقطة البيع (`779776919 100 3`) يصدر عدة كروت في عملية واحدة.
- الحجز دفعة واحدة؛ نفاد المخزون يلغي الدفعة. SMS مستقل لكل كرت.
- تقرير: [phase-29-pos-multi-card.md](phase-29-pos-multi-card.md)

### Phase 28 — طلبات رصيد نقاط البيع (2026-09-20) ✅ برمجيًا
- مسار خاص لرمز طلب الرصيد (العينة `111`) يحل نقطة البيع من رقم المُرسل.
- حد يومي لكل نقطة + قالب رد الرصيد/الدين + شاشة إعداد.
- تقرير: [phase-28-pos-balance-requests.md](phase-28-pos-balance-requests.md)

### Phase 27 — مصدر واحد لملف نقطة البيع (2026-09-20) ✅ برمجيًا
- خدمة `LocalPosProfileService`: تحقق + إنشاء + تعديل + زرع القوالب من مسار واحد.
- ربط شاشتي المحافظ ودفتر نقاط البيع بالخدمة بدل تكرار المنطق في الواجهة.
- تقرير: [phase-27-pos-single-source.md](phase-27-pos-single-source.md)

المراحل السابقة موثقة في المستودع. المتبقي الغير برمجي: تحقق جهاز حقيقي (مرحلة 12).
