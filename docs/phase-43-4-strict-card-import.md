# Phase 43-4 — استيراد الكروت الصارم (PDF / Excel / CSV)

**الفرع:** `development/full-completion`  
**التاريخ:** 2026-09-21  
**المرجع:** [krotak-pro-full-completion-plan.md](krotak-pro-full-completion-plan.md) §9 و§25 المرحلة 4

## المنفَّذ

- قصر اختيار الملف على ثلاثة أنواع فقط: `pdf` و `xlsx` و `csv`.
- رفض `txt` / `text` / `log` والصور (`png` `jpg` `jpeg` `webp` `gif`).
- التحقق لا يعتمد على الامتداد وحده: فحص Magic Bytes.
- ملف بامتداد PDF ومحتوى صورة يُرفض.
- واجهة الاستيراد تعرض Bottom Sheet بثلاث بطاقات.
- المتبقي: فلترة/تصدير الكروت المباعة وتدقيق المخزون الكبير.
