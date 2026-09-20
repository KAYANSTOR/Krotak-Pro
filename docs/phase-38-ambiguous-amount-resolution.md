# مرحلة 38 — حل يدوي للمبلغ الغامض

**التاريخ:** 2026-09-20  
**الأصل:** البند 10 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

عندما تطابق أكثر من فئة كرت نشطة نفس مبلغ التحويل (نفس العملة ونفس القيمة الاسمية):

1. لا تُرفض الرسالة تلقائياً ولا تُختار فئة عشوائياً.
2. تُعلَّق الرسالة بحالة `parsed` مع تدقيق `transfer_ambiguous_category_pending`.
3. يظهر السبب في شاشة الرسائل المعلّقة: «أكثر من فئة تطابق المبلغ — اختر الفئة».
4. المشغّل يختار الفئة يدوياً ثم يُستأنف نفس مسار `LocalTransferProcessor` بـ `forcedCategoryId`.

## السلوك

- المطابقة تبقى دقيقة على `minorUnits` + `currencyCode` للفئات النشطة فقط.
- إن وُجدت فئة واحدة تستمر المعالجة كما كانت.
- إن وُجدت أكثر من فئة ولم يُحدَّد اختيار: تعليق + payload فيه `categoryIds` و`categoryNames`.
- `resolveAmbiguousCategory` يمرّر الفئة المختارة؛ إن لم تكن ضمن المطابقات يُرجع `ambiguous_category_invalid` دون صرف كرت.
- الاعتماد العادي في شاشة المعلّقة يبقى للإيداع اليدوي لغير حالة الغموض.

## ملاحظة استعادة

ملف `lib/domain/services/local_transfer_processor.dart` كان قد استُبدل بالخطأ بـ `PLACEHOLDER` في `6d63e40`. أُعيد بناؤه من آخر نسخة كاملة (`40695ec`) مع حقل `SaleRepository? sales` ومسار المرحلة 38.
