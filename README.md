# كروتك برو — Krotak Pro
> تطبيق Flutter عربي لإدارة بيع كروت الإنترنت، التحويلات، الرسائل، العملاء، المحافظ، ونقاط البيع مع تخزين محلي أولاً.

## 📖 نظرة عامة

`Krotak Pro` تطبيق Android مبني بـ Flutter، واسم الحزمة في manifest هو `net_app`، بينما الاسم الظاهر هو `Krotak Pro` (`pubspec.yaml`، `android/app/src/main/AndroidManifest.xml`).

يبدأ التطبيق بقاعدة SQLite محلية مبنية على Drift، ويُنشئ ملف قاعدة البيانات باسم `net.sqlite` (`lib/application/app_container_impl.dart`).

يوجد مسار اختياري للحساب والسحابة عبر عميل Firebase REST للمصادقة وFirestore (`lib/data/cloud/firebase_rest_client.dart`، `lib/core/cloud_config.dart`).

واجهة التطبيق عربية وتستخدم اتجاه RTL وثيمات مخصصة ومكوّنات واجهة مشتركة (`lib/main.dart`، `lib/ui/theme/`، `lib/ui/widgets/net/`).

هذا المستند يصف ما يثبته المستودع الحالي فقط؛ لا يُفترض منه وجود خدمة منشورة أو إعداد غير موجود في الملفات.

## 🎯 المشكلة والحل

- المشكلة التجارية أو الجمهور المستهدف بالتفصيل: **غير موثّق في المستودع**.
- الحل المثبت في التنفيذ هو تطبيق محلي لإدارة العملاء، المحافظ، البطاقات، المبيعات، الرسائل الواردة، وقواعد نقاط البيع (`lib/domain/`، `lib/ui/screens/`).
- يعالج التطبيق الرسائل الواردة ويربطها بمسار التحويل والتسليم، مع حالات انتظار وفشل ورفض وسجل تدقيق (`lib/domain/services/message_parser.dart`، `lib/domain/services/message_delivery_worker.dart`، `lib/ui/screens/pending_messages_screen.dart`).
- يوفّر تكاملاً Android للرسائل النصية والإشعارات وجهات الاتصال، مع بقاء تفاصيل التشغيل الميداني حسب صلاحيات الجهاز (`android/app/src/main/AndroidManifest.xml`، `lib/platform/`).

## ✨ الميزات الرئيسية

- ✅ إدارة العملاء وأرقامهم ودمج سجل حسابين (`lib/ui/screens/customers_screen.dart`، `lib/ui/screens/customer_detail_screen.dart`، `lib/domain/services/account_merge_service.dart`).
- ✅ إدارة المحافظ ومصادر الدفع وقوالب التحويل (`lib/ui/screens/wallets_screen.dart`، `lib/ui/screens/settings/wallet_notification_settings_screen.dart`، `lib/domain/entities/transfer_template.dart`).
- ✅ إدارة فئات البطاقات ومخزونها واستيراد البطاقات ومعالجة الحجز والبيع (`lib/ui/screens/inventory_screen.dart`، `lib/ui/widgets/dashboard/card_stock_sheet.dart`، `lib/domain/services/card_import_service.dart`، `lib/domain/services/inventory_and_sale_service.dart`).
- ✅ تنفيذ البيع المباشر وإيصال العملية واستعادة البطاقة عند مسار الإلغاء (`lib/ui/screens/direct_sale_screen.dart`، `lib/domain/services/manual_sale_service.dart`، `lib/ui/widgets/net/net_transaction_detail_sheet.dart`).
- ✅ إدارة نقاط البيع، حساباتها، كشف دفترها، وتسعير الجملة (`lib/ui/screens/pos_screen.dart`، `lib/ui/screens/reports/pos_accounts_ledger_screen.dart`، `lib/ui/screens/reports/pos_report_screen.dart`، `lib/domain/services/pos_wholesale_pricing.dart`).
- ✅ استقبال SMS وتحليل الرسائل وإرسال الرسائل الصادرة عبر جسر Android (`android/app/src/main/kotlin/com/kayan/net_app/SmsReceiver.kt`، `lib/platform/sms_bridge.dart`، `lib/domain/services/message_parser.dart`، `lib/domain/services/outgoing_dispatch_queue.dart`).
- ✅ التقاط إشعارات تطبيقات دفع مسموحة وإدارتها كمصادر قابلة للتفعيل أو التعطيل (`android/app/src/main/kotlin/com/kayan/net_app/NotificationListener.kt`، `lib/ui/screens/settings/wallet_notification_settings_screen.dart`، `lib/domain/services/notification_parser.dart`).
- ✅ متابعة الرسائل المعلقة والفاشلة والمرفوضة مع إعادة المعالجة ومسار مراجعة (`lib/ui/screens/pending_messages_screen.dart`، `lib/ui/screens/failed_messages_screen.dart`، `lib/ui/screens/rejected_messages_screen.dart`).
- ✅ العروض والمكافآت والترويج وقوالب مكافأة العملاء (`lib/ui/screens/offers_screen.dart`، `lib/ui/screens/offers_wizard_sheet.dart`، `lib/domain/services/promotion_fulfillment_service.dart`، `lib/ui/widgets/customer_promotion_progress.dart`).
- ✅ الإذاعة الجماعية للعملاء مع وظائف ومستلمين وحالات في قاعدة البيانات (`lib/ui/screens/broadcast_screen.dart`، `lib/domain/services/broadcast_service.dart`، `lib/data/database/app_database.dart`).
- ✅ التقارير الزمنية وتقارير نقاط البيع وسجل العمليات وتصدير تقرير PDF (`lib/ui/screens/reports/sales_period_report_screen.dart`، `lib/ui/screens/transactions_log_screen.dart`، `lib/ui/services/report_pdf_export.dart`).
- ✅ النسخ الاحتياطي والاستعادة المحلية مع تشفير AES-GCM واشتقاق مفتاح PBKDF2 وفحص بصمة المحتوى (`lib/domain/services/local_backup_service.dart`، `lib/ui/screens/settings/backup_restore_screen.dart`).
- ✅ فحص النظام وإعدادات البطارية والأذونات والتحقق من الجهاز وأرقام الحظر (`lib/ui/screens/system_check_screen.dart`، `lib/ui/screens/settings/battery_settings_screen.dart`، `lib/ui/widgets/permissions_onboarding.dart`، `lib/ui/screens/settings/device_verification_screen.dart`، `lib/ui/screens/settings/blocked_numbers_screen.dart`).
- ✅ حساب سحابي وتزامن حالة الحساب وإشعارات Firebase عند تهيئة قيم العميل (`lib/ui/screens/account_auth_screen.dart`، `lib/domain/services/cloud_account_service.dart`، `lib/platform/remote_push_notification_service.dart`).

## 🛠️ التقنيات

| المجال | التقنية | دليلها |
|---|---|---|
| واجهة التطبيق | Flutter وDart | `pubspec.yaml`، `lib/main.dart` |
| توطين وواجهة عربية | `flutter_localizations` وRTL | `pubspec.yaml`، `lib/main.dart` |
| التخزين المحلي | Drift فوق SQLite | `pubspec.yaml`، `lib/data/database/app_database.dart` |
| تشغيل SQLite | `sqlite3_flutter_libs` | `pubspec.yaml` |
| ملفات الجهاز | `path` و`path_provider` | `pubspec.yaml`، `lib/application/app_container_impl.dart` |
| الصلاحيات | `permission_handler` | `pubspec.yaml`، `lib/platform/system_diagnostics_bridge.dart` |
| التشفير | `cryptography` | `pubspec.yaml`، `lib/domain/services/local_backup_service.dart` |
| اختيار الملفات | `file_picker` | `pubspec.yaml`، `lib/ui/screens/settings/backup_restore_screen.dart` |
| PDF والمشاركة | `pdf` و`share_plus` | `pubspec.yaml`، `lib/ui/services/report_pdf_export.dart` |
| فتح الروابط | `url_launcher` | `pubspec.yaml`، `lib/ui/screens/help_center_screen.dart` |
| Firebase | `firebase_core` و`firebase_messaging` وREST APIs | `pubspec.yaml`، `lib/data/cloud/`، `lib/platform/remote_push_notification_service.dart` |
| إشعارات محلية | `flutter_local_notifications` | `pubspec.yaml`، `lib/platform/notification_bridge.dart` |
| Android | Kotlin وAndroid Gradle Plugin | `android/settings.gradle.kts`، `android/app/build.gradle.kts` |
| الخطوط | Tajawal | `pubspec.yaml`، `assets/fonts/` |
| توليد كود Drift | `build_runner` و`drift_dev` | `pubspec.yaml`، `lib/data/database/app_database.g.dart` |
| الاختبارات | `flutter_test` | `pubspec.yaml`، `test/` |

## 🏗️ هيكل المشروع

```text
.
├── pubspec.yaml                         # الاعتماديات والإصدار والأصول
├── pubspec.lock                         # غير موجود في المستودع
├── lib/
│   ├── main.dart                         # نقطة دخول Flutter
│   ├── application/                      # تركيب الخدمات والمستودعات
│   ├── core/                             # النتائج والهوية وإعداد السحابة
│   ├── domain/                           # الكيانات وقواعد العمل والخدمات
│   ├── data/
│   │   ├── database/                     # Drift/SQLite والمخطط المولّد
│   │   ├── repositories/                  # مستودعات التخزين المحلي
│   │   └── cloud/                         # Firebase REST
│   ├── platform/                         # MethodChannel وEventChannel وجسور Android
│   └── ui/                               # الشاشات والثيم والمكونات
├── android/
│   ├── app/src/main/AndroidManifest.xml  # الصلاحيات والمستقبلات والخدمة
│   └── app/src/main/kotlin/              # SMS وBoot والإشعارات وMainActivity
├── assets/                               # الأيقونات والخطوط
├── docs/                                 # قرارات المنتج وسجل التقدم والتوقيع
├── test/                                 # اختبارات وحدة وتكامل وWidget وSmoke
├── tools/                                # توليد الأيقونات وتجهيز توقيع Android
└── .github/workflows/                    # CI والتحليل التشخيصي
```

ملفات بنية البيانات الأساسية هي `customers` و`customer_identifiers` و`wallets` و`point_of_sales` و`card_categories` و`cards` و`transactions` و`sales` و`transfer_templates` و`incoming_messages` و`licenses` و`app_settings` و`audit_logs` (`lib/data/database/app_database.dart`).

ويضيف المصدر جدولَي `broadcast_jobs` و`broadcast_recipients` عبر تهيئة SQLite (`lib/data/database/app_database.dart`).

## 🚀 التشغيل المحلي

### المتطلبات المثبتة في المستودع

- Flutter SDK بقناة stable؛ يثبت CI الإصدار `3.35.5` (`.github/workflows/ci.yml`، `.github/workflows/diagnose-analyze.yml`).
- Dart SDK بإصدار يطابق القيد `^3.6.0` (`pubspec.yaml`).
- Android SDK وJDK 17 مطلوبان بحسب إعداد Gradle وKotlin (`android/app/build.gradle.kts`).
- ملف `local.properties` مع `flutter.sdk` مطلوب لتهيئة Gradle (`android/settings.gradle.kts`).

### الأوامر المثبتة

```bash
flutter pub get
```

لا يعرّف المستودع أمراً نصياً لـ `build_runner` في CI أو scripts؛ توجد الاعتمادية وملف Drift المولّد (`pubspec.yaml`، `lib/data/database/app_database.g.dart`).

```bash
flutter run
```

يبني الأمر التالي APK إصداراً، لكن إعداد التوقيع المحلي يرفض البناء إذا غاب `android/key.properties`، إلا مع خيار الاختبار الصريح الموجود في Gradle (`android/app/build.gradle.kts`):

```bash
flutter build apk --release
flutter build apk --release -PallowDebugRelease=true
```

للتحقق المحلي كما تستخدمه CI:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test
```

لا يوجد في المستودع أمر مستقل لتشغيل Backend أو خادم ويب؛ التطبيق Android/Flutter (`pubspec.yaml`، `android/`).

## 🔐 متغيرات البيئة

لا يوجد ملف `.env.example` أو `.env.*.example` في المستودع، ولذلك لا يمكن توثيق جدول متغيرات بيئة تطبيقية مطابق لذلك المثال.

| الاسم | الغرض المثبت | مطلوب/اختياري |
|---|---|---|
| `.env.example` | غير موجود في المستودع | غير منطبق |
| متغيرات `--dart-define` | مفاتيح إعداد عميل Firebase في وقت البناء؛ يثبتها `lib/core/cloud_config.dart` فقط | اختيارية للتكوين السحابي؛ لا يعمل تسجيل الحساب دون قيم التكوين |
| متغيرات توقيع `tools/setup_upload_keystore.sh` | تجهيز ملف توقيع Android من Base64 وكلمات مرور ومُعرّف المفتاح | مطلوبة لذلك السكربت فقط؛ القيم السرية غير موثقة هنا |

أسماء مفاتيح Firebase المعرفة في الكود هي `KROTAK_FIREBASE_API_KEY` و`KROTAK_FIREBASE_PROJECT_ID` و`KROTAK_FIREBASE_AUTH_DOMAIN` (`lib/core/cloud_config.dart`).

وأسماء متغيرات سكربت التوقيع هي `APK_KEYSTORE_B64` و`APK_KEYSTORE_PASSWORD` و`APK_KEY_PASSWORD` و`APK_KEY_ALIAS` (`tools/setup_upload_keystore.sh`). لا تُضع قيم هذه المتغيرات في README أو المستودع.

## 📜 الأوامر المتاحة

| الأمر | ما يفعله وفق التعريف/الملفات |
|---|---|
| `flutter pub get` | تثبيت اعتماديات Dart/Flutter؛ مستخدم في CI (`.github/workflows/ci.yml`) |
| `flutter run` | تشغيل تطبيق Flutter؛ يرد في توثيق التوقيع (`docs/signing-and-updates-ar.md`) |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | تحليل Dart مع عدم جعل المعلومات والتحذيرات قاتلة في CI (`.github/workflows/ci.yml`) |
| `flutter test` | تشغيل اختبارات Flutter (`.github/workflows/ci.yml`) |
| `flutter build apk --release` | بناء APK إصدار (`.github/workflows/ci.yml`، `android/app/build.gradle.kts`) |
| `flutter build apk --release -PallowDebugRelease=true` | بناء إصدار محلي موقّع debug وفق الفرع الصريح في Gradle (`android/app/build.gradle.kts`) |
| `sh ./tools/setup_upload_keystore.sh` | إنشاء `android/key.properties` مؤقتاً وتشغيل بناء APK من متغيرات التوقيع (`tools/setup_upload_keystore.sh`) |
| `python3 tools/apply_krotak_icon.py` | إعادة توليد موارد الأيقونة؛ يوضح `tools/README.md` أن الناتج مرفوع مسبقاً ولا تشغله CI |

## 🌐 النشر

- يعرّف CI وظيفة بناء APK ورفع artifact باسم يعتمد على وضع التوقيع (`.github/workflows/ci.yml`).
- يمكن لـ CI توزيع APK إلى Firebase App Distribution عند توفر إعدادات وأسرار GitHub المطلوبة (`.github/workflows/ci.yml`).
- يمكن لـ CI نشر GitHub Release على فرع `main` عند نجاح التوقيع المستقر (`.github/workflows/ci.yml`).
- يعرّف CI اختبار Firebase Test Lab من نوع Robo عند توفر إعداداته (`.github/workflows/ci.yml`).
- إعدادات Vercel وNetlify وDocker وFirebase Hosting غير موجودة في الملفات المفحوصة.
- رابط Demo أو رابط تطبيق حي منشور: **غير موثّق في المستودع**.

## 🔒 الأمان

- صلاحيات Android المعلنة تشمل SMS وجهات الاتصال والإشعارات والبدء بعد الإقلاع وخدمة foreground وقفل الاستيقاظ وتجاهل تحسين البطارية (`android/app/src/main/AndroidManifest.xml`).
- يستقبل `SmsReceiver` رسائل SMS، ويستعيد مسار العمل بعد الإقلاع عبر `BootReceiver`، ويستقبل إشعارات الحزم المسموحة عبر `NotificationListener` (`android/app/src/main/kotlin/com/kayan/net_app/`).
- يحتفظ التطبيق بسجل تدقيق للكيانات والرسائل وعمليات البيع (`lib/domain/entities/audit.dart`، `lib/data/database/app_database.dart`، `lib/domain/services/message_delivery_worker.dart`).
- يطبق التخزين المحلي فهارس فريدة لمنع التكرار للمعرّفات والبطاقات والحجوزات والرسائل والمعاملات والمبيعات (`lib/data/database/app_database.dart`).
- يحمي ملف النسخ الاحتياطي بكلمة مرور عبر AES-GCM وPBKDF2 وSHA-256 للتحقق من السلامة (`lib/domain/services/local_backup_service.dart`).
- يتضمن التطبيق حظر أرقام وفحص جهاز وتحكم مصادر إشعارات الدفع (`lib/domain/services/blocked_number_service.dart`، `lib/domain/services/device_verification_service.dart`، `lib/domain/services/payment_source_registry.dart`).
- توجد مصادقة سحابية عبر Firebase REST وجلسة محلية تتضمن المعرّف ورمز التجديد في الكود (`lib/data/cloud/firebase_rest_client.dart`).
- لا توجد ملفات `firestore.rules` أو ملفات RLS في المستودع؛ قواعد الخادم التفصيلية: **غير موثّق في المستودع**.
- لا يحتوي المستودع على ملف ترخيص أو سياسة خصوصية منشورة بحسب الفحص؛ لا يُستنتج مستوى أمان تشغيلي يتجاوز ما يطبقه الكود.

## 📄 الترخيص

- ملف `LICENSE` أو `COPYING` غير موجود في المستودع.
- نوع الترخيص وحقوق النشر: **غير موثّق في المستودع**.
