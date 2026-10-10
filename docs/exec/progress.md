# تقدم تنفيذ خطة Krotak Pro — 2026-10-10

**الفرع:** `exec/krotak-hardening`  
**خط الأساس:** `development/full-completion` (فرع `development/next` غير موجود حالياً في الـ remote)

## WP-1 — حذف بطاقة «إدارة الكروت والفئات» من الإعدادات — منفّذ

- أُزيل `SettingsGroupNavRow` الخاص بإدارة الكروت والفئات من `lib/ui/screens/settings/settings_hub_screen.dart`.
- أُزيل الاستيراد غير المستخدم لـ `InventoryScreen`.
- تبويب الكروت في الشريط السفلي (`home_shell.dart`) يبقى كما هو.
- الحالة: مكتمل برمجياً.

## WP-2 — حذف إشعار «حساب دائم بدون فترة تجريبية» — منفّذ

- أُزيل استدعاء `_trialCard` من وضع إنشاء الحساب في `lib/ui/screens/account_auth_screen.dart`.
- أُزيلت الدالة `_trialCard` بالكامل.
- لم يُمس منطق `isTrial` أو الجلسة أو الخادم.
- الحالة: مكتمل برمجياً.

## التالي

- البنية المشتركة WP-S1 إلى S4.
- ثم WP-3 (صيانة موحدة) و WP-4 (نسخ ظاهر).
