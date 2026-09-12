# تقدم تنفيذ خطة NET

## التحقق (2026-09-11)

```text
آخر تحقق موثّق قبل 6A:
dart analyze lib test  → No issues found!
flutter test           → All tests passed! (41+)
```

بعد دمج المرحلة 6A يُعاد تشغيل analyze/test محليًا قبل أي إصدار.

## Domain مكتمل ومختبر

عملاء، رصيد، مخزون FIFO، بيع+عكس، **Parser+Identity Resolver+Transfer (6A)**، استعادة رسائل، تسوية، دمج حسابات، Audit، SMS Bridge.

## المرحلة 6A (مكتملة)

- `TransferIdentifierType` وتصنيف phone/account/reference/name
- محرك قوالب موحّد `{ }` و `%`
- تطبيع الأرقام العربية
- `LocalCustomerIdentityResolver` مع Unresolved صريح و deliveryPhone
- `LocalTransferProcessor` يرفض دون تخمين ويسجّل Audit
- تقرير: `docs/phase-6a-payment-intelligence-report.md`

## واجهات

- Dashboard / Customers / Inventory / Settings: جزئية ومربوطة محدودًا
- Reports / Offers: placeholders صادقة
- لا شاشة مربوطة بالكامل مع Loading/Empty/Error + بيانات حية في كل الحالات

## اختبارات Widget مع AppContainer حقيقي (جديد)

`AppContainer.forTesting(...)` + `test/widget/app_container_screens_test.dart`
يغلقان فجوة "full widget tests need AppContainer bootstrap" لـ Dashboard/
Customers/Inventory/Reports/TransactionsLog/WalletsPos. التفاصيل والتنبيهات
في `docs/widget-integration-tests-report.md`. لم يُشغَّل `flutter test` محليًا
لعدم توفر Flutter SDK في بيئة الكتابة؛ التحقق النهائي عبر CI.

## متبقٍ (Post-v1 + UI)

سلفني، إشعارات المحافظ، التسوية التلقائية المجدولة، البث الجماعي، شاشات التقارير/المحافظ/الإعدادات الفرعية، ربط Dashboard بالبيانات الحية، عينات قوالب محفظة حقيقية.
