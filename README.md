# NET Flutter

تطبيق Android لإدارة بيع الكروت والتحويلات عبر SMS — يعمل محلياً (Drift) مع جسر Native لاستقبال/إرسال الرسائل.

## المعمارية

```
UI (Flutter)
  → AppContainer (composition root)
  → Domain services / use cases
  → Repositories → Drift SQLite
  → Android SmsReceiver + MethodChannel/EventChannel
```

## التشغيل

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

صلاحيات SMS تُطلب من شاشة لوحة التحكم.

## الاختبار

```bash
flutter test
```

## المراحل المكتملة

انظر [docs/progress.md](docs/progress.md).
