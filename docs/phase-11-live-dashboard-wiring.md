# تنفيذ ربط المرحلة 11 في لوحة التحكم

**التاريخ:** 2026-09-22  
**الفرع:** `development/full-completion`  
**المرجع:** [phase-11-live-dashboard-counts.md](phase-11-live-dashboard-counts.md)

## ما تم

`MessageRepository.countByStatus` و`watchCountByStatus` كانا موجودين في المستودع واللوحة ما زالت تحمّل القوائم بـ`listByStatus`.

الربط في `lib/ui/screens/dashboard_screen.dart`:

- العدّ الأولي عبر `countByStatus`.
- اشتراك واحد في `watchCountByStatus` بعد أول تحميل ناجح.
- تحديث شارة الشريط السفلي وعداد المرفوضة دون إعادة تحميل كامل لللوحة.
