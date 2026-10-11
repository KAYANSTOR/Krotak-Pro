# البنود المحجوبة — Krotak Pro

لا يوجد بند محجوب بالكامل (كل حزمة نُفّذت). البنود التالية **ينتظر تحقق جهاز**
لأن أثرها النهائي لا يُثبت آليًا في CI؛ الكود والاختبارات الآلية لكل منها موجودة.

| الحزمة | ما تعذّر آليًا | الدليل المنفّذ | ما يلزم من المستخدم |
|---|---|---|---|
| WP-4 | ظهور النسخة في `Download/Krotak Pro/` في مدير الملفات | `test/widget/backup_visible_copy_test.dart` يثبت استدعاء `saveToDownloads` بالمسار والبصمة | فتح مدير الملفات على جهاز Android 10+ بعد إنشاء نسخة |
| WP-4 | فتح ورقة مشاركة النظام لملف `.krt` | نفس الاختبار يثبت عرض «مشاركة النسخة» | الضغط على «مشاركة النسخة» على جهاز حقيقي |
| WP-8 | ظهور صورة الإشعار في معرض الصور | `test/widget/transaction_receipt_image_test.dart` يثبت إنتاج PNG واستدعاء `saveImageToPictures` | «حفظ» من ورقة تفاصيل عملية ثم فتح المعرض |
| WP-8 | فتح ورقة مشاركة الصورة كنص/صورة | نفس الاختبار يثبت وجود زر «مشاركة» وبلا نص TXT | مشاركة على جهاز حقيقي |
| WP-3 | ظهور ملف CSV في `Download/Krotak Pro/Exports/` | `test/widget/maintenance_hub_screen_test.dart` + `ledger_csv_export_service_test.dart` | فتح المجلد بعد «تصدير ملف CSV» |
| WP-5 | ظهور تقرير الاستيراد في `Exports/` | `test/widget/inventory_import_logs_screen_test.dart` | «تصدير تقرير النتائج» على جهاز |
| WP-9 | معيار القبول D11: 12 ساعة في الخلفية على Android 14/15 بلا نافذة ANR | أدلة أسباب الإنهاء (`ProcessExitReasonCodesTest.kt`) + `background_diagnostics_test.dart` + تحويل الخدمة إلى `specialUse` مع `onTimeout` | تشغيل 12 ساعة بقفل الشاشة وتوفير البطارية، مع رسالة SMS أثناء ذلك |
| WP-9 | حدود Force-stop/قيود OEM | موثّقة في `docs/exec/final-report.md` (لا تُمنع برمجيًا) | لا شيء — للتوعية فقط |
