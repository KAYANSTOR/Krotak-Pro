# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 43-4 — استيراد الكروت الصارم PDF/XLSX/CSV (2026-09-21) ✅ برمجيًا جزئيًا

- الاستيراد من ملف محصور بـ PDF و Excel و CSV مع فحص التوقيع وليس الامتداد وحده.
- رفض TXT والصور والملفات المزيفة النوع قبل التحليل.
- ورقة اختيار بثلاث بطاقات في شاشة الاستيراد.
- المتبقي من المرحلة 4: فلترة/تصدير الكروت المباعة وتدقيق قائمة المخزون الكبير.
- تقرير: [phase-43-4-strict-card-import.md](phase-43-4-strict-card-import.md)

### Phase 43-3 — العملاء والحسابات (2026-09-21) ✅ برمجيًا

- ملف عميل متكامل: بيانات + دفتر + علاقة POS + سلف مفتوحة.
- تعديل رصيد بمسار Ledger الحقيقي مع سبب إلزامي.
- تقرير: [phase-43-3-customer-accounts.md](phase-43-3-customer-accounts.md)
