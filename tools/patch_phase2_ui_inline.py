#!/usr/bin/env python3
from pathlib import Path

ROOT = Path('.')
cs_path = ROOT / 'lib/ui/screens/customers_screen.dart'
cd_path = ROOT / 'lib/ui/screens/customer_detail_screen.dart'
cs = cs_path.read_text()

old_row = '''class _AccountRow {
  const _AccountRow({
    required this.customer,
    this.balance,
    this.phone,
    this.altId,
    this.altLabel,
  });

  final Customer customer;
  final Money? balance;
  final String? phone;
  final String? altId;
  final String? altLabel;

  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;
}'''

new_row = '''class _AccountRow {
  const _AccountRow({
    required this.customer,
    this.balance,
    this.phone,
    this.altId,
    this.altLabel,
  });

  final Customer customer;
  final Money? balance;
  final String? phone;
  final String? altId;
  final String? altLabel;

  bool get hasPhone => phone != null && phone!.trim().isNotEmpty;

  bool get isProvisional => customer.status == CustomerStatus.provisional;
}'''

if old_row not in cs:
    raise SystemExit('AccountRow not found')
cs = cs.replace(old_row, new_row)

old_ind = """                    NetIndicatorTile(
                      label: 'غير مربوط',
                      value: '${_allRows.where((r) => !r.hasPhone).length}',
                      icon: Icons.link_off_rounded,
                      tint: net.warning,
                    ),
                    NetIndicatorTile(
                      label: 'إجمالي المدين',"""

new_ind = """                    NetIndicatorTile(
                      label: 'غير مربوط',
                      value: '${_allRows.where((r) => !r.hasPhone).length}',
                      icon: Icons.link_off_rounded,
                      tint: net.warning,
                    ),
                    NetIndicatorTile(
                      label: 'دفتر مؤقت',
                      value: '${_allRows.where((r) => r.isProvisional).length}',
                      icon: Icons.account_balance_wallet_outlined,
                      tint: net.warning,
                    ),
                    NetIndicatorTile(
                      label: 'إجمالي المدين',"""

if old_ind not in cs:
    raise SystemExit('indicator not found')
cs = cs.replace(old_ind, new_ind, 1)

idx = cs.rfind('if (!row.hasPhone)')
if idx < 0:
    raise SystemExit('badge not found')
sub = cs[idx:]
cidx = sub.find('chevron_left_rounded')
end_rel = sub.find('\n          ],', cidx)
old_badge = sub[: end_rel + len('\n          ],')]
new_badge = Path('tools/new_badge_snippet.dart').read_text()
cs = cs[:idx] + new_badge + cs[idx + len(old_badge):]
cs_path.write_text(cs)
print('customers', len(cs))

cd = cd_path.read_text()
marker = '''    await _load();
  }

  Future<void> _adjustBalance() async {'''
promote = Path('tools/promote_snippet.dart').read_text()
if marker not in cd:
    raise SystemExit('detail marker missing')
cd = cd.replace(marker, promote)

wrap_idx = cd.find('              Wrap(\n                spacing: 8,')
if wrap_idx < 0:
    raise SystemExit('Wrap missing')
banner = Path('tools/banner_snippet.dart').read_text()
cd = cd[:wrap_idx] + banner + cd[wrap_idx:]

old_name = """                        if (!_hasPrimaryPhone)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: context.netColors.warningContainer, borderRadius: BorderRadius.circular(8)),
                            child: Text('غير مربوط', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.w700, color: context.netColors.warning)),
                          ),"""
new_name = """                        if (customer.status == CustomerStatus.provisional)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: context.netColors.warningContainer, borderRadius: BorderRadius.circular(8)),
                            child: Text('دفتر مؤقت', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.w700, color: context.netColors.warning)),
                          )
                        else if (!_hasPrimaryPhone)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: context.netColors.warningContainer, borderRadius: BorderRadius.circular(8)),
                            child: Text('غير مربوط', style: TextStyle(fontFamily: 'Tajawal', fontSize: 11, fontWeight: FontWeight.w700, color: context.netColors.warning)),
                          ),"""
if old_name not in cd:
    raise SystemExit('name badge missing')
cd = cd.replace(old_name, new_name)
cd_path.write_text(cd)
print('detail', len(cd))

(ROOT / 'docs').mkdir(exist_ok=True)
(ROOT / 'docs/phase-2-provisional-ui.md').write_text(
    '# Phase 2 provisional UI\n\nBadge + promote + bind on accounts screens.\n'
)
assert 'isProvisional' in cs_path.read_text()
assert '_promoteToCustomer' in cd_path.read_text()
print('PHASE2_OK')
