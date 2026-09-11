# NET Local Database — Schema v1

## الهدف

قاعدة SQLite محلية عبر Drift لتوفير التشغيل اليومي دون إنترنت. هذا الإصدار يثبت أسماء الجداول والحقول الأولية وفهارس uniqueness اللازمة لمنع التكرار.

## الجداول الأولية

| الجدول | الغرض |
|---|---|
| `customers` | بيانات العملاء وحالاتهم ومرجع الدمج المحتمل. |
| `customer_identifiers` | أرقام ومعرفات العميل المتعددة. |
| `wallets` | المحافظ المحلية. |
| `point_of_sales` | نقاط البيع. |
| `card_categories` | فئات الكروت وقيمها. |
| `cards` | المخزون وأكواد الكروت وحالة الحجز. |
| `transactions` | السجل المالي العام. |
| `sales` | ربط البيع بالعميل والكرت. |
| `transfer_templates` | قوالب تحليل التحويل. |
| `incoming_messages` | الرسائل الخام وحالة المعالجة ومنع التكرار. |
| `licenses` | حالة الترخيص محليًا. |
| `app_settings` | إعدادات التطبيق القابلة للحفظ. |
| `audit_logs` | سجل التدقيق للعمليات المؤثرة. |

## قواعد تنفيذية

كل جدول يملك مفتاحًا نصيًا صريحًا. المبالغ تحفظ في `amountMinorUnits` مع `currencyCode` بدل `double`. الرسائل تحفظ قبل التحليل. حالة الحجز تحفظ منفصلة عن حالة الكرت لتسهيل التعافي.

## فهارس uniqueness الحالية

| الفهرس | الجدول | الغرض |
|---|---|---|
| `idx_customer_identifiers_value` | `customer_identifiers(value)` | منع تكرار رقم العميل. |
| `idx_cards_serial_number` | `cards(serial_number)` | منع تكرار الرقم التسلسلي. |
| `idx_cards_secret_code` | `cards(secret_code)` | منع تكرار السر. |
| `idx_incoming_messages_external_reference` | `incoming_messages(external_reference)` | منع معالجة الرسالة مرتين. |
| `idx_transactions_reference` | `transactions(reference)` | منع تكرار الإيداع أو البيع بنفس المرجع. |

القيم `NULL` مسموحة أكثر من مرة في فهارس المراجع الاختيارية وفق سلوك SQLite.

## ما يزال مطلوبًا قبل الإصدار

يجب اعتماد foreign keys، وسياسة soft delete، والتشفير، ومهلة الحجز الإنتاجية، ومخطط migrations التالي. لا يجوز اعتبار المخطط الحالي جاهزًا للبيانات الإنتاجية قبل اختبارات الاستعادة والتشفير.
