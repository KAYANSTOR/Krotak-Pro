# مرحلة 35 — استيراد الكروت من CSV/Excel/PDF مع معاينة

**التاريخ:** 2026-09-20  
**الأصل:** البند 8 من المتبقي في [phase-26-audiences-branding-pos-validation.md](phase-26-audiences-branding-pos-validation.md)

## الهدف

استيراد دفعة كروت من ملف مع **معاينة قبل التأكيد** وكشف المكرر داخل الملف وفي المخزون، بدل اللصق المباشر ثم الحفظ.

## المصادر المدعومة

| النوع | السلوك |
|---|---|
| TXT / CSV / LOG | UTF-8 مع حذف BOM |
| XLSX | أول ورقة عمل → أسطر `عمود1,عمود2` (فك ZIP+DEFLATE محلياً) |
| PDF | استخراج النص الظاهر (`Tj` / `TJ`) فقط — بلا OCR للصفحات المصوّرة |

## القواعد

- التحليل يبقى عبر `CardImportParser` (رقم+رمز أو رقم فقط).
- `previewImport` يسأل المخزون بـ `existingSerialsAmong` ولا يكتب شيئاً.
- التأكيد يستورد `acceptedDrafts` فقط (يستبعد أرقام المخزون القائمة).
- أخطاء الأسطر والمكرر داخل الملف تظهر في المعاينة ولا توقف الكروت الصالحة.

## الملفات

- `lib/domain/services/card_import_file_reader.dart`
- `lib/domain/services/local_catalog_services.dart` (`previewImport`)
- `lib/domain/services/services.dart` (`CardImportPreview`)
- `lib/ui/screens/inventory_sheets.dart`
- `test/services/card_import_preview_test.dart`
