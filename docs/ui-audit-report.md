# تقرير مراجعة واجهات Flutter مقابل Kotlin

**Commit المراجع:** `82ed9f028ca47a915d75f0849b0b77cc873b6df4` (main)  
**مرجع Kotlin:** `kayan-android-kotlan` @ `1e26933`  
**تاريخ المراجعة:** 2026-09-11  
**طريقة التحقق:** قراءة الشاشات المحلية + التنقل في `HomeShell` + `AppScope`/`AppContainer` + مقارنة feature tree في Kotlin.  
**تحليل/اختبارات عند المراجعة:**

```text
dart analyze lib test     → No issues found!
flutter test              → All tests passed! (41)
Commit قاعدة المراجعة     → 82ed9f0 (قبل دمج الحسابات)
```

بعد هذه المراجعة نُفِّذ أيضًا: `LocalAccountMergeService` + إصلاح تعيين تبويبات HomeShell + شاشات placeholder صادقة للتقارير/العروض.

---

## ملخص نسبة الإنجاز (واجهات)

| التصنيف | العدد التقريبي | النسبة من شاشات Kotlin الرئيسية (~22) |
|---|---|---|
| منفذة ومربوطة بالكامل (Domain + حالات تشغيلية كاملة) | **0** | **0%** |
| منفذة بصريًا جزئيًا + ربط محدود | **5** | ~23% |
| منفذة جزئيًا (هيكل/نماذج إدخال فقط) | ضمن الخمسة أعلاه | — |
| غير منفذة | **~17** | ~77% |
| تحتاج إصلاحًا (تعيين تبويبات خاطئ / أرقام ثابتة) | **3+** | — |

**تقدير إنجاز الواجهات الفعلي (سلوك + ربط + حالات):** **≈ 12–18%**  
ليس نسبة وجود ملفات Widget.

---

## جدول الشاشات

| شاشة Kotlin | شاشة Flutter | نُقلت/أُعيدت؟ | مكتملة بصريًا؟ | مربوطة Domain/Repos؟ | Loading / Empty / Error / Success | مشاكل / غير منفَّذ | مرحلة الخطة |
|---|---|---|---|---|---|---|---|
| **MainDashboardScreen** | `DashboardScreen` | إعادة كتابة جزئية (هيكل) | جزئي (بطاقات + شبكة إجراءات) | جزئي: ترخيص + صلاحية SMS فقط؛ أرصدة/مبيعات ثابتة `0` | Loading جزئي عند الإقلاع؛ لا Empty لآخر العمليات؛ Error محدود | أرقام ثابتة؛ لا BottomSheets؛ FAB غير موجود؛ إعدادات top bar فارغة | UI shell / dashboard |
| **AccountsScreen** | `CustomersScreen` | جزئي (نموذج إنشاء فقط) | لا (ليست قائمة حسابات) | نعم لـ`create` فقط | Busy + Success/Error نصي؛ لا قائمة Empty/Loading قائمة | لا بحث/قائمة/تفاصيل/blacklist UI/دمج | accounts |
| **CardsScreen** | `InventoryScreen` | جزئي (فئة + استيراد) | لا | نعم لـ`saveCategory` + `importCards` | Busy + نص حالة؛ لا قائمة مخزون | لا جدول كروت/حالات/حجز بصري | cards |
| **CategoriesScreen** | ضمن `InventoryScreen` | جزئي | لا | حفظ فئة فقط | نفسه | لا شاشة فئات مستقلة | cards/catalog |
| **ReportsScreen** | **غير موجود** — التبويب يفتح `MessagesScreen` | لا | لا | لا | لا | تعيين خاطئ في `HomeShell` | reports |
| **SalesReportScreen** | غير موجود | لا | لا | لا | لا | — | reports |
| **SalesPointsReportScreen** | غير موجود | لا | لا | لا | لا | — | reports |
| **TransactionsLogScreen** | غير موجود | لا | لا | لا | لا | — | reports |
| **RejectedMessagesScreen** | غير موجود | لا | لا | لا | لا | — | reports/messages |
| **SuspendedMessagesScreen** | غير موجود | لا | لا | لا | لا | — | reports/messages |
| **SettingsScreen** (+ فرعية) | `SettingsScreen` | جزئي جدًا | لا | `activateOffline` + `createBackup` فقط | Busy + نص | لا SIM/قوالب/بطارية/تصدير/تجديد اشتراك كما في Kotlin | settings |
| **BatterySettingsScreen** | غير موجود | لا | لا | لا | لا | — | settings |
| **SimSettingsScreen** | غير موجود | لا | لا | لا | لا | — | settings |
| **CustomerTemplatesScreen** | غير موجود | لا | لا | لا | لا | — | settings |
| **TemplateSimulationScreen** | غير موجود | لا | لا | لا | لا | — | settings |
| **ExportLedgerScreen** | غير موجود | لا | لا | لا | لا | — | settings |
| **CleanLogsScreen / DeepCleanScreen** | غير موجود | لا | لا | لا | لا | — | settings |
| **RenewSubscriptionScreen** | غير موجود | لا | لا | لا | لا | — | license |
| **ActivationScreen** | غير موجود | لا | لا | Domain الترخيص موجود بلا شاشة تفعيل كاملة | لا | — | license/activation |
| **HelpCenterScreen** | غير موجود | لا | لا | لا | لا | — | help |
| **WalletsAndPosScreen** | غير موجود | لا | لا | Repository محفظة موجود بلا UI | لا | — | wallets |
| **TemplatesScreen / TemplateWizardScreen** | غير موجود | لا | لا | قوالب التحويل في Domain فقط | لا | — | wallets/templates |
| **تبويب العروض (offers)** | يفتح `SettingsScreen` خطأ | لا | لا | لا | لا | تعيين خاطئ في `HomeShell` | offers (Post-v1) |
| **محاكاة SMS** | `MessagesScreen` | أداة تطوير محلية | لا (ليست شاشة تقارير) | مربوطة `smsHandler.handleManual` | Busy + Success/Error | ليست مكافئًا لأي شاشة Kotlin إنتاجية | dev / SMS bridge |

---

## تفصيل التصنيفات

### 1) منفذة ومربوطة بالكامل
**لا شيء.** لا توجد شاشة Flutter تغطي قائمة + تفاصيل + كل حالات Loading/Empty/Error مع بيانات حية من المستودعات كما في Kotlin.

### 2) منفذة بصريًا جزئيًا + ربط محدود
- `DashboardScreen` — هيكل Kotlin (تحية، حالة نظام، بطاقة رصيد، مبيعات، إجراءات سريعة) لكن البيانات غير حية.
- `CustomersScreen` — نموذج إنشاء مربوط `CustomerService.create`.
- `InventoryScreen` — نموذج فئة/استيراد مربوط Catalog.
- `SettingsScreen` — زرّان مربوطان License/Backup.
- `MessagesScreen` — محاكاة SMS مربوطة بالمعالج.

### 3) غير منفذة
كل شاشات التقارير الفرعية، الإعدادات الفرعية، التفعيل، مركز المساعدة، المحافظ/نقاط البيع، معالج القوالب، العروض.

### 4) تحتاج إصلاحًا عاجلًا
1. **`HomeShell._pageFor`**: `reports` → Messages، `offers` → Settings (تعيين خاطئ).
2. **Dashboard**: أرقام `0` ثابتة بدل استعلام الرصيد/المبيعات/عدد الحسابات.
3. **لا مسارات `Navigator` لشاشات فرعية** (لا hierarchy مثل Kotlin).
4. **حالات Empty/Error موحدة ناقصة** في كل الشاشات القائمة.

---

## التنقل الفعلي (سلوك)

```text
HomeShell
 ├─ dashboard  → DashboardScreen
 ├─ reports    → MessagesScreen   ❌ يجب تقارير
 ├─ offers     → SettingsScreen   ❌ يجب عروض
 ├─ accounts   → CustomersScreen  (جزئي)
 └─ cards      → InventoryScreen  (جزئي)
```

لا يوجد `routes`/`GoRouter`؛ لا شاشات مودال/BottomSheet مطابقة لـ Kotlin.

---

## ربط Domain المتاح وغير المستخدم من UI

| خدمة / مستودع | موجود في Domain | مستخدم في UI؟ |
|---|---|---|
| CustomerService | نعم | create فقط |
| CustomerBalanceService | نعم | لا (أرقام ثابتة) |
| SaleService | نعم | لا |
| CardCatalog / Inventory | نعم | فئة + استيراد فقط |
| TransferProcessor / SMS | نعم | محاكاة يدوية |
| SettlementService | نعم | لا UI |
| MessageRecoveryService | نعم | لا UI |
| License / Backup | نعم | أزرار إعدادات |
| Wallets / POS repos | نعم | لا UI |

---

## الخلاصة التنفيذية

- نجاح `analyze`/`test` يثبت **صحة طبقة Domain/Data** أكثر مما يثبت **جاهزية الواجهة**.
- الواجهة الحالية أقرب إلى **لوحة تشغيل/تشخيص** منها إلى تطبيق إنتاجي مطابق لـ Kotlin.
- الأولوية الهندسية التالية يُفضَّل أن تكون:
  1. إصلاح تعيين التبويبات + ربط Dashboard بالبيانات الحية.
  2. إكمال قائمة الحسابات والكروت (قراءة من المستودع + حالات).
  3. ثم Post-v1 Domain (دمج حسابات، سلفني، …) مع UI مرتبط.

لا يُدَّعى اكتمال أي شاشة إنتاجية في هذا التقرير.
