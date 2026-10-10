# جرد متغيرات القوالب — خطوة 1 من WP-6

**الطريقة:** قراءة `OutboundTemplateRenderer` (المحرك المركزي) + كل مواضع
`renderRegistered` / `renderStrict` في `lib/**` + `OutboundTemplateCatalog`
+ خريطة أسماء المتغيرات في `outbound_message_templates_screen.dart`.
**القاعدة الحاكمة:** D9 — **لا يُدمج متغيران إلا إذا حلّهما المحرك إلى الحقل نفسه.**

---

## 1. المجموعات المؤكدة بالكود (نفس الحقل ⇒ دمج بالدلالة)

| المجموعة | المفاتيح | الحقل الحقيقي | موضع الحل |
|---|---|---|---|
| رقم/سيريال الكرت | `serial`, `serial_number`, `CARD_SERIAL`, `CARD_CODE`, `الرقم` | `serialNumber` | `outbound_template_renderer.dart:285-292`, `pos_order_message_renderer.dart:61-66` |
| الرمز السري | `code`, `secret`, `CODE`, `SECRET`, `الرمز` | `secretCode` | `outbound_template_renderer.dart:288-290`, `pos_order_message_renderer.dart:62-65` |
| فئة/قيمة الكرت | `CARD_VALUE`, `الفئة` | قيمة الكرت المعروضة | `outbound_template_renderer.dart:295-296` |
| اسم الشبكة/المحفظة | `NETWORK_NAME`, `network`, `network_name`, `اسم_المحفظة` | `networkName` (من الإعدادات) | `outbound_template_renderer.dart:297-300` |
| رقم العميل | `phone`, `customer_phone`, `CUSTOMER_PHONE`, `destination` | رقم تسليم العميل | `pos_order_message_renderer.dart:70-72`, `:95-97` |
| اسم نقطة البيع | `pos`, `pos_name`, `POS_NAME` | `posAccount.name` | `pos_order_message_renderer.dart:92-94` |
| المبلغ | `amount`, `AMOUNT`, `المبلغ` | مبلغ العملية | `local_transfer_processor.dart:1489-1491`, `pos_order_message_renderer.dart:105-106` |
| الإجمالي | `total`, `TOTAL` | إجمالي الطلب | `pos_order_message_renderer.dart:107-108` |
| عدد الكروت | `QUANTITY`, `quantity`, `QUANTITY_TEXT`, `quantity_text` | العدد (`_quantityText`) | `pos_order_message_renderer.dart:74-78` |
| بيانات الكروت | `cards`, `CARDS` | كتل الكروت | `pos_order_message_renderer.dart:79-80` |
| العملة | `CURRENCY` | `ر.ي` | كل المواضع |
| اسم الفئة | `category`, `category_name` | اسم الفئة | `pos_order_message_renderer.dart:68-69` |

**قرار D9 المطبّق:** `serial` (رقم الكرت) و`secret` (الرمز السري) **يبقيان منفصلين** — ولهذا
`CARD_CODE` يُدمج مع `serial` لا مع `code` (الدليل: المحرك نفسه).

---

## 2. مشكلات مؤكدة بالكود (سبب WP-6)

1. **زرّان بنفس المعنى وبنفس القيمة:** `code` و`secret` يعرضان «الرمز» و«الرمز السري» لكن
   المحرك يمرّر لهما **القيمة نفسها** (`secretCode`) ⇒ إدراج أيّهما يعطي نتيجة واحدة.
2. **تناقض تسمية:** الواجهة تسمّي `CARD_CODE` = «كود الكرت»، بينما المحرك يحلّه إلى
   **الرقم/السيريال** (`outbound_template_renderer.dart:291`) — أي أن التسمية الحالية مضلّلة.
3. **أكواد لاتينية ظاهرة للمستخدم:** أزرار المتغيرات تعرض `CARD_CODE` / `QUANTITY_TEXT` /
   `NETWORK_NAME` (القيمة الافتراضية في `_variableLabel` هي المتغير نفسه عند غياب التسمية).
4. **متغير معلن بلا مصدر قيمة:** `{المستخدم}`/`user` معلن في العقد وممرَّر في التسليم فقط
   (هوية الكرت)، ولا يُمرَّر في «إيداع بلا كرت» — موثّق في الكود كقرار مالك معلّق.
5. **غياب محقّق مستقل:** التحقق الحالي داخل `renderRegistered` (متغير غير معروف/قيمة ناقصة)
   لكن لا يمنع **التكرار بعد التطبيع** ولا يمنع إدراج مرادفين لنفس الحقل في قالب واحد.

---

## 3. الحقول المعلنة في العقد (`OutboundTemplateCatalog.definitions`)

كل تعريف يعلن `variables` (المسموح) و`requiredVariables` (المطلوب). أمثلة مؤكدة:

| القالب | المطلوب |
|---|---|
| تسليم كرت للعميل | `code` |
| تسليم كروت طلب نقطة البيع | `cards` |
| تأكيد سداد دين العميل | `amount`, `paid`, `surplus`, `balance` |
| نجاح طلب نقطة البيع | `QUANTITY_TEXT` |
| تأكيد الشحن الفوري | `amount`, `phone` |
| مكافأة العرض | `serial` |
| قبول سلفني | `amount` |
| سداد سلفني | `amount`, `paid`, `surplus`, `balance` |
| تنبيه انخفاض مخزون الكروت | `category`, `category_name`, `count`, `CARD_VALUE` |

> ⚠️ `requiredVariables` تستعمل الصيغة اللاتينية فقط، وبعضها `QUANTITY_TEXT` و`CARD_VALUE`
> (قيمتان مرادفتان لمفاتيح أخرى) — يُوحَّد ذلك في `TemplateVariableRegistry` (WP-S2).

---

## 4. المتبقي لإكمال الجرد (قبل إغلاق WP-6)

- استخراج خرائط القيم من المواضع المتبقية: `local_settlement_service.dart:181`,
  `local_advance_service.dart:497`, `local_low_stock_alert_service.dart:127`,
  `local_pos_daily_summary_service.dart:230`, `local_pos_balance_request_service.dart:91`,
  `local_pos_auto_settlement_service.dart:304`, `local_promotion_fulfillment_service.dart:365`,
  `promotion_reward_template.dart:146`, `local_transfer_processor.dart:1996`.
- التأكد أن كل مفتاح في العقد له **حلّ فعلي** في مسار واحد على الأقل (وإلا فهو متغير وهمي).
- تثبيت الجدول النهائي في `docs/exec/decisions-log.md` قبل بناء `TemplateVariableRegistry`.
