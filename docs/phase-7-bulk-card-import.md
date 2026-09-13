# Phase 7 — Bulk Card Import Performance

## الحالة

🟡 منفّذة في المستودع — بانتظار إغلاق بوابة CI والتحقق على جهاز Android حقيقي.

## المشكلة السابقة

`importCards` كان يفحص كل سطر على حدة ويكتب كل كرت بمنفصل. الاستيراد الكبير كان يحجز الواجهة ويفشل الدفعة كاملة عند أول تكرار.

## التصميم

```text
نص خام
  -> CardImportParser (أخطاء السطر + منع تكرار التسلسل/الرمز داخل الملف)
  -> LocalCardCatalogService.importCards
       -> findExistingSerials / findExistingSecrets (دفعات IN مجزأة)
       -> saveAll بدفعات 200
       -> Audit cards_imported {count, skipped}
```

## القواعد

- لا تغيير على Schema v1.
- الرقم التسلسلي والرمز السري فريدان عالميًا (الفهارس الموجودة).
- الدفعة المختلطة: استيراد الجديد وتجاهل المكرر.
- إذا كانت كل المسودات مكررة يُرجَع `duplicate_serial` للتوافق مع العقد السابق.
- الاستيراد داخل Unit of Work واحد.
- `onProgress` اختياري ولا يغيّر عقد `Result<int>`.

## التحقق

1. `flutter test test/services/bulk_card_import_test.dart`
2. `flutter test`
3. جهاز: لصق ملف كبير (مئات الأسطر) والتأكد من عدم تجميد الواجهة ومن عدم إضافة المكرر.
