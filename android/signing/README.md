# توقيع الإصدار — مرحلة 7

ملف `net-upload.jks.b64` موجود تاريخياً لتوافق التحديثات مع النسخ المثبتة.

**لا يستخدمه CI بعد هذه المرحلة.** بناء الإصدار التجاري يعتمد فقط على GitHub Secrets:

- `APK_KEYSTORE_B64`
- `APK_KEYSTORE_PASSWORD`
- `APK_KEY_PASSWORD`
- `APK_KEY_ALIAS`

لا تُدار كلمات المرور في المستودع. تدوير المفتاح قرار مستقل لأنه قد يمنع تحديث APK المثبت.

التفاصيل: `docs/phase-7-ci-signing.md`
