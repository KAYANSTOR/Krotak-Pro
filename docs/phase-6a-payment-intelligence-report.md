# المرحلة 6A — تقرير ما قبل التنفيذ وما بعده: ذكاء رسائل التحويل

**التاريخ:** 2026-09-11  
**المستودع:** KAYANSTOR/Krotak-Pro  
**الحالة:** منفَّذ بالكامل في Domain + Parser + Identity Resolver + TransferProcessor + Tests

## 1. الوضع قبل التنفيذ

| المكوّن | الحالة السابقة | الفجوة |
|---|---|---|
| `LocalMessageParser` | `{amount}` `{phone}` `{ref}` فقط | لا `%account`، لا تصنيف نوع المعرف، لا أرقام عربية |
| `ParsedTransfer` | معرف نصي بلا نوع | خطر معاملة الحساب كرقم هاتف |
| حل الهوية | `findByIdentifier` مباشرة داخل Processor | لا فصل، لا Unresolved صريح، لا delivery phone |
| القوالب | محرك واحد جزئي | لا توحيد `%` و `{}` |

## 2. التصميم المعتمد (بدون Architecture موازية)

```text
SMS خام
  -> LocalMessageParser (Template Matching فقط)
  -> ParsedTransfer + TransferIdentifierType
  -> LocalCustomerIdentityResolver
  -> LocalTransferProcessor (ائتمان + Audit)
  -> (لاحقًا) تسليم الكرت عبر deliveryPhone فقط
```

قواعد إلزامية محققة:

- Parser لا يقرر تجاريًا ولا يرسل SMS.
- `%amount|%phone|%account|%ref` و `{...}` نفس المحرك.
- `TransferIdentifierType.phone|account|reference|name|unknown` صريح.
- Unresolved يُسجَّل Audit ويرفض الرسالة — بلا تخمين.
- رقم الحساب/الاسم لا يُستخدم كوجهة إرسال.

## 3. الملفات المتأثرة

- `lib/domain/entities/message.dart` — `TransferIdentifierType` + توسيع `ParsedTransfer`
- `lib/domain/services/local_message_parser.dart` — محرك موحّد + أرقام عربية
- `lib/domain/services/local_customer_identity_resolver.dart` — جديد
- `lib/domain/services/local_transfer_processor.dart` — يستخدم Resolver
- `test/services/message_parser_and_transfer_test.dart` — تغطية موسّعة
- لا Migration لقاعدة البيانات في هذه المرحلة (حسب شرط الخطة)

## 4. الاختبارات

- تطابق قالب الهاتف وتصنيف `phone`
- قالب `%account` وتصنيف `account`
- تطبيع الأرقام العربية-الهندية
- فشل عدم المطابقة وغياب القوالب
- Resolver: هاتف، حساب→delivery phone مختلف، Unresolved
- Processor: نجاح ائتمان، رفض غير الموجود + audit `transfer_unresolved`، رسالة معالجة مسبقًا

## 5. ما لم يُنفَّذ عمدًا (خارج نطاق 6A)

- قوالب إنتاج لكل محفظة يمنية دون عينات حقيقية منزوعة الحساسية
- Notification Listener للمحافظ
- تغيير Schema / Migrations
- ربط UI لإدارة القوالب المتقدمة

## 6. معيار القبول

الرسالة الخام تتحول إلى نتيجة منظمة ومصنفة، ثم تُحل إلى عميل ورقم تسليم عند وجود mapping، أو تتوقف بحالة Unresolved قابلة للتشخيص، دون تخمين أو تكرار أو Parser موازٍ.
