# المرحلة 24 — ربط عدّاد لوحة التحكم الحي

**التاريخ:** 2026-09-29  
**الفرع:** `development/full-completion`  
**الأساس:** `docs/phase-14-live-dashboard-message-counts.md` و`docs/phase-21-dashboard-count-live-wire.md`

## المشكلة

عقد `countByStatus` / `watchCountByStatus` كان موجوداً في المستودع وDrift، لكن `dashboard_screen.dart` ما زال يحمّل عدّادات الانتباه عبر `listByStatus` (قوائم كاملة).

## الحل

- `_load` يعدّ عبر `MessageRepository.countByStatus` لحالات: rejected / received / parsed / failed.
- بعد التحميل تُشترك اللوحة في `watchCountByStatus` لتحديث الشارة دون إعادة تحميل المخزون والمبيعات.
- الاشتراكات تُلغى في `dispose` وقبل إعادة الربط.

## معيار القبول

- لا تُحمَّل قوائم الرسائل لمجرد عرض العدّاد.
- وصول رسالة جديدة يحدّث الشارة أثناء بقاء الشاشة مفتوحة.
