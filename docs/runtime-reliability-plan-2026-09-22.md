# خطة موثوقية التشغيل — محدّثة R4 + DB

| مرحلة | الحالة |
|--------|--------|
| R1 SMS SENT | ✅ |
| R2 محافظ | ✅ |
| R3 أداء إرسال | ✅ |
| **R4 بطارية/OEM/onboarding** | **✅ كود** — تحقق أجهزة معلّق |
| R5 سقف دين POS | ✅ |
| DB hot-path indexes + WAL | ✅ |

## R4
- onboarding v7: نصوص أوضح + خطوة تأكيد ميداني
- BatterySettingsScreen: حالة فعلية + أزرار OEM + قائمة تحقق

## DB
فهارس: audit entity/occurred، messages status/received، transactions customer/created،
sales customer/created، cards category+status، customer_identifiers customer
+ جداول broadcast + PRAGMA WAL/synchronous=NORMAL
