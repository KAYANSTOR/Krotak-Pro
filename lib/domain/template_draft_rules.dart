import 'entities/message.dart';

/// قاعدة «مسودة» الموحّدة لأي قالب تحويل وارد.
///
/// القالب يكون **مسودة** إذا كان ناقصًا حقلًا لازمًا لمطابقة رسالة فعلية، فلا
/// يمكن تفعيله فعليًا (مفتاح التفعيل معطّل في شاشة القوالب) — مطابق لسلوك
/// «مسودة» في الفيديو المرجعي.
///
/// أنواع المعرّف التي تُقرأ **من رقم المرسل** لا تحتاج عنصرًا نائبًا في النص:
/// - [TemplateIdentifierKind.senderNameOnly]: هوية نقطة البيع/المرسل نفسه
///   (قوالب POS: «10 كرت 100»). كان هذا القالب المزروع افتراضيًا يُعرَض خطأً
///   «مسودة» بمفتاح معطّل لأن نوعه كان `phone` بلا `{phone}`، فيستحيل تفعيله.
/// - [TemplateIdentifierKind.balanceRequestCode]: قالب طلب الرصيد يُطابَق بنصّه
///   نفسه (مثل «111») بلا مبلغ ولا معرّف.
///
/// المصدر الواحد لهذه القاعدة يمنع تكرار المنطق بين الواجهة والخدمات ويسهّل
/// اختباره في `test/domain/pos_template_draft_rules_test.dart`.
bool isTemplateDraft(TransferTemplate template) {
  final pattern = template.pattern.trim();
  if (pattern.isEmpty) return true;

  // قالب طلب الرصيد: نصّه هو الرمز، والهوية من المرسل.
  if (template.identifierKind == TemplateIdentifierKind.balanceRequestCode) {
    return false;
  }

  final hasAmount =
      pattern.contains('{amount}') || pattern.contains('%amount');

  // قوالب تُطابَق بالكمية والمبلغ فقط، والهوية من رقم المرسل.
  if (template.identifierKind == TemplateIdentifierKind.senderNameOnly) {
    return !hasAmount;
  }

  final hasIdentifier = switch (template.identifierKind) {
    TemplateIdentifierKind.phone =>
      pattern.contains('{phone}') || pattern.contains('%phone'),
    _ => pattern.contains('{account}') || pattern.contains('%account'),
  };
  return !hasAmount || !hasIdentifier;
}
