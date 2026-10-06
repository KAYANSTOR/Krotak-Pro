# إكمال ربط المرحلة 14 في لوحة التحكم

**التاريخ:** 2026-09-27

كان عقد `countByStatus` / `watchCountByStatus` موجوداً في المستودع وDrift، لكن `dashboard_screen.dart` ما زال يحمّل العداد عبر `listByStatus`.

## ما تم

- `_load` يستدعي `messages.countByStatus` لحالات الانتباه: rejected / received / parsed / failed.
- بعد التحميل يشترك `watchCountByStatus` لتحديث الشارة الحية دون إعادة تحميل المخزون والمبيعات.
- إلغاء الاشتراكات في `dispose`.

تغيير الكود: `lib/ui/screens/dashboard_screen.dart`.
