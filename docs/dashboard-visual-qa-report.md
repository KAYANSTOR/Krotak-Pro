# تقرير التحقق البصري والتكامل — Dashboard والثيم

**Commit المرجع السابق:** `610723d` ثم phase 6A حتى `78f5837`  
**Commit HomeShell:** `234df1d`  
**Commit إكمال الربط:** يُدفع فوق `234df1d`

## نتيجة التحليل والاختبارات

```text
flutter test test/widget/           → All tests passed! (22+)
  - net_components_test.dart
  - dashboard_navigation_test.dart
  - p1_navigation_smoke_test.dart
flutter analyze                     → analysis server OOM في هذه البيئة (exit -9)
flutter build apk --debug           → غير متاح (لا Android SDK)
```

ملاحظة: فشل بعض اختبارات `test/services/*` (مثل account_merge) موجود مسبقًا وغير ناتج عن تغييرات التنقل في Dashboard.

## الأجهزة / المقاسات

| البيئة | النتيجة |
|--------|----------|
| Widget tests — سطح Flutter الافتراضي | ناجح |
| RTL (`TextDirection.rtl`) | مدعوم |
| Light / Dark Theme | مدعوم |
| Android Emulator | **غير متاح** |
| `flutter build apk` | **No Android SDK** |

## التنقل الذي تم إصلاحه (جذريًا)

**Root cause:** `NetBalanceCard` وبطاقات المقاييس (الحسابات / الكروت) لم تكن مربوطة بأي callback من `DashboardScreen`، و`HomeShell` كان يحتفظ بـ `_route` داخليًا دون واجهة للطفل لطلب تبديل التبويب. لا يوجد SnackBar كبديل للتنقل.

**الحل الكامل:**

1. `DashboardScreen` يقبل `ValueChanged<String>? onNavigateToTab`.
2. `HomeShell` يمرّر `(id) => setState(() => _route = id)` إلى `DashboardScreen`.
3. `NetBalanceCard`: `onTapAccounts` → `'accounts'`، `onTapCards` → `'cards'`.
4. `NetMetricCard` للحسابات النشطة والكروت المتاحة مربوطان بنفس الـ callback.
5. Quick Actions (بيع مباشر، محافظ/POS، سجل العمليات، الإعدادات) عبر `AppRoutes` كما هي.
6. لا تغيير على Domain / Database / SMS / Business Logic.

## الاختبارات المضافة

- `test/widget/net_components_test.dart`: callbacks لـ Balance و Metric.
- `test/widget/dashboard_navigation_test.dart`: chips، metric، BottomNav ids، shell-style switch بدون SnackBar.

## مشاكل متبقية (بسبب البيئة)

- لا Android SDK → لا تحقق بصري على Emulator ولا APK build.
- لا يُدّعى التطابق البصري الكامل مع Kotlin.

## ما لم يُمس (حسب النطاق)

- Domain / Database / SMS / Transfer intelligence (phase 6A)
- Post-v1
- مطابقة بكسلية
