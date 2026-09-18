# خطة ومتابعة تحديث الواجهات والهوية البصرية (UI / Theme Refresh)

**النطاق:** الواجهات والثيم والهوية والتنسيقات والخطوط والأيقونات والشاشات فقط.

**القاعدة الحاكمة التي التُزمت:** لا تغيير في منطق الأعمال، ولا في الحسابات المالية، ولا في
الربط مع البيانات. لم يُعدَّل أي ملف من `lib/domain/**` أو `lib/data/**` أو `lib/application/**`
أو `lib/platform/**`.

```
git diff --stat <baseline>..HEAD -- lib/domain lib/data lib/application lib/platform
→ (فارغ: لا تغييرات في طبقات المنطق والبيانات)
```

---

## 0) تدقيق الـBaseline (الجولة الحالية)

طُبِّق منهج «تدقيق الوضع الحالي → تحديد الفجوات → الاستكمال → التوحيد → التلميع» بدون أي
إعادة بناء لما اكتمل. نتائج التدقيق:

| السؤال | النتيجة |
|---|---|
| ما تم تطويره فعلاً | 15 مرحلة (الأساس + المكوّنات + 8 تبويبات رئيسية + الشاشات الثانوية) |
| المكوّنات الجديدة | 11 مكوّناً: `NetSurfaceCard`, `NetSheet`, `NetTabHeader`, `NetSparkline`, `NetAnimatedCounter`, `NetInitialAvatar`, `NetBalancePill`, `NetInlineNotice`, هياكل التحميل، `SettingsSearchScope/Row`, تسميات الـenums |
| الـTheme / Design System | `net_tokens.dart` (Spacing/Radii/Typography/Motion/Elevation/Sizes) + `net_theme.dart` (كل ثيم المكوّنات) + `kayan_palette.dart` + `net_semantic_colors.dart` |
| الأيقونات | توحيد تدريجي على `_rounded` / `_outlined`؛ الأيقونات المتناقضة استُبدلت داخل الشاشات المُراجَعة |
| الخطوط | Tajawal مُضمَّن (6 أوزان) — كان الثيم يطلبه بلا ملف خط |
| الشاشات المكتملة | Dashboard · Reports · Offers · Customers · Cards · Transactions log · Settings hub · Permissions · System check · Wallet notifications |
| الشاشات التي كانت بالتصميم القديم | 4 شاشات + 4 أوراق (مذكورة في القسم 6) |
| الشاشات الجزئية | 15 شاشة (رموز مطبَّقة، وبقيت توحيد البطاقات/الحالات) |
| تناقضات وُجدت وصُحِّحت | تكرار الرأس · FAB مزدوج · مديونية بالأخضر · تسريب أسماء enums · استيراد نسبيّ خاطئ · `const` حول `Theme.of` · مجرّد `netColors` خارج `build` |

**أهم نتيجة للتدقيق:** الـDesign System موحّد فعلاً، والفجوة المتبقية هي **تبنّي** هذا النظام
في شاشات/أوراق لم تُراجَع بعد، لا إنشاء نظام ثانٍ.

---

## 1) جدول الحالة

| # | المرحلة | الحالة |
|---|---|---|
| 1 | أساس التصميم: Tajawal + رموز + ثيم المكوّنات | ✅ مكتمل |
| 2 | المكوّنات المشتركة | ✅ مكتمل |
| 3 | توحيد الهيكل (رأس واحد + إزالة FAB المزدوج) | ✅ مكتمل |
| 4 | الوضع الداكن في كل الشاشات | ✅ مكتمل (صفر لون نص/خلفية ثابت) |
| 5 | لوحة التحكم | ✅ مكتمل |
| 6 | سجل العمليات | ✅ مكتمل |
| 7 | الحسابات + كشف العميل | 🟡 شبه مكتمل (بقيت توحيد البطاقات/الحالات في كشف العميل) |
| 8 | الكروت | ✅ مكتمل |
| 9 | العروض والتقارير | 🟡 شبه مكتمل (بقيت شاشة تقرير فترة المبيعات) |
| 10 | الإعدادات | 🟡 شبه مكتمل (بقيت قوالب الرسائل الصادرة + أوراق المحاكاة) |
| 11 | معالج الصلاحيات | ✅ مكتمل |
| 12 | النظام/الصحة (System Health) | ✅ مكتمل |
| 13 | إشعارات المحافظ | ✅ مكتمل |
| 14 | المحافظ ونقاط البيع (POS) | 🟡 شبه مكتمل (بقيت توحيد بطاقات القوائم) |
| 15 | الرسائل (معلّقة/مرفوضة/فاشلة/البث) | 🟡 شبه مكتمل (بقيت توحيد البطاقات + الهياكل) |
| 16 | الإيداع اليدوي/البيع المباشر | 🟡 شبه مكتمل (الأوراق تحتاج ترحيلاً كاملاً) |
| 17 | الصيانة/التصدير/التحقق من الجهاز | ✅ مكتمل |
| 18 | إزالة المكوّنات الميتة + تسريب enums | ✅ مكتمل |

---

## 2) ما نُفِّذ في الجولة الحالية (استكمال فوق الـBaseline)

**أ) الألوان والوضعان (Light/Dark)**
- استُبدلت كل الألوان الثابتة المتبقية (الباستيل الفاتح، الرمادي الكحلي، التيل الخارج عن الرمز،
  الوردي القديم) برموز `KayanPalette` / `NetSemanticColors` / `NetSpacing` + `NetRadii`.
- البقايا الثلاث المتعمَّدة فقط: خرائط ألوان العلامات (هوية المحافظ)، وألوان التغذية الراجعة
  المشبعة (SnackBar نجاح/خطأ) التي تبقى مقروءة في الوضعين.

**ب) الشاشات المرحّلة إلى النظام**
`system_check` · `wallet_notification_settings` · `activate` · `messages` (محاكاة) ·
`renew_subscription` · `battery_settings` · `export_ledger` · `network_name_settings` ·
`promotion_reward_template` · `device_verification` · `broadcast` · `reports/messages_by_status`

**ج) توحيد الحالات**
- التحميل: `AsyncLoadingView(skeleton: true)` في كل الشاشات المرحّلة (بدل مؤشر دوّار).
- الفراغ: `AsyncEmptyView` مع أيقونة + تلميح + إجراء (إضافة/إعادة تحميل) بدل نص فقط.
- الأخطاء: `AsyncErrorView` / `NetInlineNotice` بلون الخطأ الدلالي بدل `Colors.red` ونصوص عارية.

**د) توحيد المكوّنات**
- البطاقات: `NetSurfaceCard` بدل `Container(color: …)` و`Material(shape: …)` و`Card` الخام.
- الأزرار: إزالة `backgroundColor` اليدوي من `FilledButton` ليتبع ثيم النظام (مع إبقاء الأحمر
  للحذف فقط عبر `netColors.rejected`).
- القوائم: `ListTile` داخل `NetSurfaceCard` بحدود ونصف قطر موحّدين.

**هـ) إصلاحات دلالية/عرضية**
- رسالة `broadcast`: كانت تعرض `status.name` إنجليزيًا → الآن `broadcastStatusLabel` عربي + لون دلالي.
- قائمة الرسائل حسب الحالة: كانت تعرض `m.status.name` → الآن تسمية عربية + شارة ملوّنة + وقت نسبي.
- `help_center`: دالة `_tone` تفتح درجة لون التصنيف في الوضع الداكن (كانت ألوان العلامات
  البنفسجية/الزرقاء تُقرأ بصعوبة على الأسطح الداكنة).

---

## 3) مصفوفة التغطية (آخر تدقيق)

| المجموعة | الشاشات | الحالة |
|---|---|---|
| مكتملة تمامًا على النظام | Dashboard, Reports, Offers, Customers, Cards/Inventory, Transactions log, Settings hub, Permissions, System check, Wallet notifications | ✅ |
| نظام مُطبَّق + بقيت توحيد بطاقات/حالات | customer_detail, pending, rejected, failed, help_center, wallets_pos, templates, template_wizard, sim_settings, template_simulation, clean_logs, low_stock, salafni_templates, pos_report, reserved_card_ops, card_stock_sheet, quick_actions_sheet | 🟡 |
| بالتصميم القديم (تحتاج ترحيلاً) | `reports/sales_period_report_screen` (236) · `settings/outbound_message_templates_screen` (332) · `dashboard/sales_period_sheet` (359) · `dashboard/direct_sale_sheet` (193) | ❌ |
| ليست شاشات (مضيف/شعار) | `settings_screen` (غلاف) · `direct_sale_screen` (مضيف ورقة) · `net_app_logo` · `net_app_bar_title` (جزء من النظام) | — |

---

## 4) الاختبارات والتحقق

CI هو المرجع (بيئة العمل هنا بلا Flutter SDK):

```
flutter pub get
flutter analyze --no-fatal-infos     → No issues found
flutter test                        → كل الاختبارات نجحت
flutter build apk --release         → APK + GitHub Release
```

كل دفعة في هذه الجولة مرّت على هذه البوابة، والدفعات التي أظهرت أخطاءً حقيقية (استيراد
`kayan_palette` ناقص، `const` حول استدعاء ثيم، `messageStatusContainer` غير موجود، دالة
`_tone` في موضع خاطئ) صُحِّحت ثم أُعيد التحقق.

---

## 5) ما لم يُنفَّذ (بأسباب موضوعية)

1. **شريط تقدّم لكل عرض ترويجي في شاشة العروض**: الكتالوج لا يحمل مبلغ تراكم؛ التقدّم الحقيقي
   في `CustomerPromotionProgress` من بيانات العميل. عرض رقم في الكتالوج = حساب تجميعي جديد أو
   بيانات وهمية، وكلاهما مرفوض.
2. **انتقال Hero من بطاقة الرصيد إلى سجل العمليات**: لا بطاقة رصيد مقابل في الشاشة الهدف.
3. **إجراءات الحساب الفردي (حذف/أرشفة)**: تغيير منطقي — خارج النطاق.
4. **تبديل تبويبات المنصة بتلاشٍ متقاطع**: `IndexedStack` يحفظ حالة كل تبويب؛ أي
   `AnimatedSwitcher` حوله يفقد الحالة.
