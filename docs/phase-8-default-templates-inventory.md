# Default templates inventory (product video)

## Built-in on first launch (no manual setup)

### 1) Four wallets
جيب / جوالي / ون كاش / فلوسك — `ensureDefaultWallets()`

### 2) Inbound parse templates (Phase-4 style)
`DefaultWalletTemplatesSeeder` (`default_wallet_templates_seeded_v2`):

| Wallet | Patterns |
|--------|----------|
| JAIB | تحويل مشترك اسم+رقم، رقم فقط، English received |
| JAWALI | تحويل مشترك، رقم فقط، English |
| ONE CASH | تحويل مشترك، استلمت حوالة، عام |
| FLOOSAK | تحويل مشترك، **استلمت حوالة** (فيديو)، عام |

Editable via معالج القالب / إدارة القوالب per wallet. Default can be changed; new wallets need manual templates.

### 3) Outbound feature templates
`DefaultOutboundTemplatesSeeder`:

- **سلفني**: قبول / رفض / سداد — screen `SalafniTemplatesScreen` (full edit + reset to default)
- **عروض**: `promotion_reward_sms_template` — `PromotionRewardTemplateScreen`

### 4) Wallets UI
Full `WalletsPosScreen` (cards, switch, ⋮ menu, edit sheet, POS tab) aligned with wallet video frames.
