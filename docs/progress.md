# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 31 — تسعير الجملة بعد نسبة العمولة (2026-09-20) ✅ برمجيًا
- `PosPercentageMode` يسعّر كرت نقطة البيع: خصم عمولة الفئة أو الوجه الكامل عند 0%.
- طلب POS يُقيَّد بالصافي كمديونية دون إيداع مقابل.
- تقرير: [phase-31-pos-wholesale-pricing.md](phase-31-pos-wholesale-pricing.md)

### Phase 30 — الشحن الفوري لرقم ثالث (2026-09-20) ✅ برمجيًا
- كلمة «شحن / أرسل كرت» تقيّد العملية على رقم المُرسل وتسلّم الكرت لرقم الجسم.
- تأكيد SMS لنقطة البيع بعد نجاح التسليم + قالب POS سادس.
- تقرير: [phase-30-pos-instant-charge.md](phase-30-pos-instant-charge.md)
