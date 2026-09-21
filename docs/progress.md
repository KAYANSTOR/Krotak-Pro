# تقدم تنفيذ خطة NET

## التحقق (2026-09-13)

```text
CI على main — analyze + test + Android debug APK build
```

**قرارات المنتج:** [product-decisions.md](product-decisions.md)

## Post-V1

### Phase 43A — اقتراح أرقام العملاء في البيع المباشر (2026-09-21) ✅ برمجيًا

- البحث يبدأ من أول رقم عبر `CustomerRepository.suggestPhonesByPrefix`.
- التطبيع نفسه المعتمد في المستودع (`PhoneNormalizer` / أرقام عربية-لاتينية).
- عرض الرقم + الاسم، ترتيب بالأحدث، استبعاد الموقوف/المدمج/المؤرشف.
- الضغط يملأ الرقم (والاسم إن كان فارغًا) دون إنشاء عميل.
- Debounce 160ms + حد 8 نتائج لمنع N+1.
- زر جهات الاتصال ومسار `sellManual` بدون تغيير قواعد البيع.

