import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/broadcast.dart';
import '../../domain/entities/customer.dart';
import '../../domain/entities/pos_account.dart';
import '../../domain/entities/wallet.dart';
import '../app_scope.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_sheet.dart';
import '../widgets/net/net_surface_card.dart';

/// ورقة «إرسال رسالة للعملاء» — بث SMS جماعي بنطاق محدد.
///
/// النطاقات: كل العملاء · من عليهم دين · تحديد يدوي · نقاط البيع.
/// المنطق نفسه: نفس `BroadcastService` ونفس كلمة التأكيد — لا تكرار للإرسال.
class BroadcastSheet extends StatefulWidget {
  const BroadcastSheet({super.key});

  static Future<void> show(BuildContext context) async {
    await NetSheet.show<void>(
      context,
      builder: (ctx) => const BroadcastSheet(),
    );
  }

  @override
  State<BroadcastSheet> createState() => _BroadcastSheetState();
}

class _BroadcastSheetState extends State<BroadcastSheet> {
  final _bodyCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  BroadcastAudience _audience = BroadcastAudience.allCustomers;
  final Set<String> _selected = <String>{};

  List<Customer> _customers = const [];
  int _posAccounts = 0;
  bool _loadingTargets = true;
  String? _error;

  BroadcastPreview? _preview;
  bool _loadingPreview = false;
  bool _sending = false;
  int _previewToken = 0;
  BroadcastProgress? _progress;
  BroadcastJob? _job;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTargets());
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    final c = AppScope.of(context);
    final customers = await c.customers.search('');
    final pos = await c.posRegistry.listAll();
    if (!mounted) return;
    setState(() {
      _loadingTargets = false;
      _customers = customers is Success<List<Customer>> ? customers.value : const [];
      _posAccounts = pos is Success<List<PosAccount>>
          ? pos.value.where((e) => e.status == PointOfSaleStatus.active).length
          : 0;
      if (customers is Failure<List<Customer>>) {
        _error = customers.error.message;
      }
    });
    await _refreshPreview();
  }

  Future<void> _refreshPreview() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      setState(() {
        _preview = null;
        _loadingPreview = false;
      });
      return;
    }
    final token = ++_previewToken;
    setState(() => _loadingPreview = true);
    final result = await AppScope.of(context).broadcastService.preview(
          body: body,
          audience: _audience,
          customerIds: _selected.toList(growable: false),
        );
    if (!mounted || token != _previewToken) return;
    setState(() {
      _loadingPreview = false;
      if (result is Success<BroadcastPreview>) {
        _preview = result.value;
        _error = null;
      } else {
        _preview = null;
        _error = (result as Failure<BroadcastPreview>).error.message;
      }
    });
  }

  Future<void> _send() async {
    final body = _bodyCtrl.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'اكتب نص الرسالة أولاً');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final confirmed = await c.broadcastService.confirm(
      body: body,
      confirmationPhrase: 'إرسال',
      audience: _audience,
      customerIds: _selected.toList(growable: false),
    );
    if (!mounted) return;
    if (confirmed is Failure<BroadcastJob>) {
      setState(() {
        _sending = false;
        _error = confirmed.error.message;
      });
      return;
    }
    final job = (confirmed as Success<BroadcastJob>).value;
    final ran = await c.broadcastService.run(
      job.id,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ran is Failure<BroadcastJob>) {
        _error = ran.error.message;
      } else {
        _job = (ran as Success<BroadcastJob>).value;
      }
    });
  }

  String get _audienceHint => switch (_audience) {
        BroadcastAudience.allCustomers =>
          'إرسال رسالة نصية قصيرة (SMS) إلى كل العملاء النشطين المرتبطين بأرقام صالحة.',
        BroadcastAudience.debtorCustomers =>
          'تقتصر الرسالة على العملاء الذين عليهم دين قائم في الدفتر.',
        BroadcastAudience.selectedCustomers =>
          'اختر العملاء المستهدفين يدوياً من القائمة.',
        BroadcastAudience.posAccounts =>
          'رسالة إلى نقاط البيع المفعّلة على رقم الإشعار المحفوظ لكل نقطة.',
      };

  int get _targetCount => switch (_audience) {
        BroadcastAudience.posAccounts => _posAccounts,
        BroadcastAudience.selectedCustomers => _selected.length,
        _ => _customers.length,
      };

  List<Customer> get _visibleCustomers {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return _customers;
    return _customers
        .where((e) => e.displayName.contains(q))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: NetSheet(
        title: 'إرسال رسالة للعملاء',
        subtitle: 'رسالة نصية قصيرة (SMS) جماعية بنطاق محدد',
        icon: Icons.campaign_rounded,
        footer: _footer(context),
        children: [
          NetInlineNotice(
            message: _audienceHint,
            icon: Icons.campaign_outlined,
          ),
          const SizedBox(height: NetSpacing.md),

          // ── نطاق المستهدفين ──
          _AudienceChips(
            value: _audience,
            customersCount: _customers.length,
            debtorsLabel: 'عليهم دين',
            posCount: _posAccounts,
            selectedCount: _selected.length,
            onChanged: (value) {
              setState(() => _audience = value);
              _refreshPreview();
            },
          ),

          if (_audience == BroadcastAudience.selectedCustomers) ...[
            const SizedBox(height: NetSpacing.md),
            _manualPicker(palette),
          ],

          const SizedBox(height: NetSpacing.md),

          // ── نص الرسالة ──
          NetSurfaceCard(
            padding: const EdgeInsets.all(NetSpacing.md),
            child: TextField(
              controller: _bodyCtrl,
              minLines: 3,
              maxLines: 6,
              textDirection: TextDirection.rtl,
              onChanged: (_) => _refreshPreview(),
              decoration: const InputDecoration(
                labelText: 'نص الرسالة',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
              style: TextStyle(
                fontFamily: NetTypography.family,
                color: palette.textPrimary,
              ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: NetSpacing.md),
            NetInlineNotice(
              message: _error!,
              icon: Icons.error_outline_rounded,
              color: net.rejected,
            ),
          ],

          const SizedBox(height: NetSpacing.md),
          _statsCard(palette, net),

          if (_progress != null) ...[
            const SizedBox(height: NetSpacing.md),
            NetSurfaceCard(
              padding: const EdgeInsets.all(NetSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'جارٍ الإرسال… ${_progress!.done} / ${_progress!.total}',
                    style: TextStyle(
                      fontFamily: NetTypography.family,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: NetSpacing.sm),
                  ClipRRect(
                    borderRadius: NetRadii.xsAll,
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: _progress!.total == 0
                          ? 0
                          : _progress!.done / _progress!.total,
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_job != null) ...[
            const SizedBox(height: NetSpacing.md),
            NetInlineNotice(
              message: 'تم الإرسال: ${_job!.sentCount} نجحت · '
                  '${_job!.failedCount} فشلت · ${_job!.skippedCount} تخطي',
              icon: Icons.check_circle_outline_rounded,
              color: _job!.failedCount == 0 ? net.available : net.warning,
            ),
          ],
        ],
      ),
    );
  }

  Widget _manualPicker(KayanPalette palette) {
    if (_loadingTargets) {
      return const AsyncLoadingView(skeleton: true, skeletonCount: 2);
    }
    final visible = _visibleCustomers;
    return NetSurfaceCard(
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.md,
        NetSpacing.sm,
        NetSpacing.md,
        NetSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'اختيار يدوي — ${_selected.length} محدد',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (_selected.length == _customers.length) {
                    _selected.clear();
                  } else {
                    _selected
                      ..clear()
                      ..addAll(_customers.map((e) => e.id));
                  }
                }),
                child: const Text(
                  'تحديد الكل',
                  style: TextStyle(fontFamily: NetTypography.family),
                ),
              ),
            ],
          ),
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'بحث بالاسم…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: NetSpacing.sm),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: NetSpacing.md),
              child: AsyncEmptyView(
                message: 'لا يوجد عملاء مطابقون',
                icon: Icons.groups_outlined,
                compact: true,
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final customer = visible[index];
                  final checked = _selected.contains(customer.id);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      customer.displayName,
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13.5,
                        color: palette.textPrimary,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selected.add(customer.id);
                        } else {
                          _selected.remove(customer.id);
                        }
                      });
                      _refreshPreview();
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _statsCard(KayanPalette palette, NetSemanticColors net) {
    final preview = _preview;
    final length = SmsLength.compute(_bodyCtrl.text);
    final parts = length.parts;
    final eligible = preview?.eligibleCount ?? 0;
    final total = eligible * parts;

    Widget row(String label, String value, {Color? color, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: NetSpacing.sm),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: palette.textTertiary),
              const SizedBox(width: NetSpacing.sm),
            ],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13,
                  color: palette.textSecondary,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: color ?? palette.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    return NetSurfaceCard(
      padding: const EdgeInsets.all(NetSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'معلومات الرسالة',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (_loadingPreview)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          row(
            'عدد المستهدفين',
            '$eligible من $_targetCount',
            color: net.available,
            icon: Icons.groups_2_outlined,
          ),
          row(
            'حجم الرسالة والترميز',
            '${length.chars} حرف ${length.unicode ? 'UCS-2' : 'GSM 7-bit'}',
            icon: Icons.text_fields_rounded,
          ),
          row(
            'عدد الرسائل لكل مستهدف',
            '$parts رسالة',
            icon: Icons.splitscreen_rounded,
          ),
          row(
            'إجمالي الرسائل المتوقع إرسالها',
            '$total رسالة',
            color: net.premium,
            icon: Icons.mark_email_read_outlined,
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final net = context.netColors;
    final canSend =
        !_sending && (_preview?.eligibleCount ?? 0) > 0 && _job == null;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _sending ? null : () => Navigator.of(context).maybePop(),
            child: const Text(
              'إلغاء',
              style: TextStyle(fontFamily: NetTypography.family),
            ),
          ),
        ),
        const SizedBox(width: NetSpacing.md),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: canSend ? _send : null,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(
              _sending ? 'جارٍ الإرسال…' : 'إرسال الرسالة',
              style: const TextStyle(
                fontFamily: NetTypography.family,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: canSend ? KayanPalette.of(context).primary : net.pendingContainer,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

class _AudienceChips extends StatelessWidget {
  const _AudienceChips({
    required this.value,
    required this.customersCount,
    required this.debtorsLabel,
    required this.posCount,
    required this.selectedCount,
    required this.onChanged,
  });

  final BroadcastAudience value;
  final int customersCount;
  final String debtorsLabel;
  final int posCount;
  final int selectedCount;
  final ValueChanged<BroadcastAudience> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final entries = <(BroadcastAudience, String, IconData)>[
      (BroadcastAudience.allCustomers, 'الكل ($customersCount)', Icons.groups_rounded),
      (BroadcastAudience.debtorCustomers, debtorsLabel, Icons.south_west_rounded),
      (BroadcastAudience.posAccounts, 'نقاط البيع ($posCount)', Icons.storefront_rounded),
      (
        BroadcastAudience.selectedCustomers,
        'تحديد يدوي${selectedCount > 0 ? ' ($selectedCount)' : ''}',
        Icons.checklist_rounded,
      ),
    ];

    return Wrap(
      spacing: NetSpacing.sm,
      runSpacing: NetSpacing.sm,
      children: [
        for (final entry in entries)
          FilterChip(
            selected: value == entry.$1,
            showCheckmark: false,
            avatar: Icon(
              entry.$3,
              size: 16,
              color: value == entry.$1 ? Colors.white : palette.textSecondary,
            ),
            label: Text(
              entry.$2,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: value == entry.$1 ? Colors.white : palette.textPrimary,
              ),
            ),
            selectedColor: palette.primary,
            backgroundColor: palette.surface,
            side: BorderSide(
              color: value == entry.$1 ? palette.primary : palette.border,
            ),
            shape: RoundedRectangleBorder(borderRadius: NetRadii.pillAll),
            onSelected: (_) => onChanged(entry.$1),
          ),
      ],
    );
  }
}

/// حساب حجم الرسالة وعدد الأجزاء (GSM 7-bit مقابل UCS-2) — عرض فقط.
final class SmsLength {
  const SmsLength({
    required this.chars,
    required this.unicode,
    required this.parts,
  });

  final int chars;
  final bool unicode;
  final int parts;

  static SmsLength compute(String body) {
    final chars = body.length;
    final unicode = body.runes.any((rune) => rune > 0x7F);
    final single = unicode ? 70 : 160;
    final multipart = unicode ? 67 : 153;
    if (chars == 0) return const SmsLength(chars: 0, unicode: false, parts: 0);
    final parts = chars <= single ? 1 : (chars / multipart).ceil();
    return SmsLength(chars: chars, unicode: unicode, parts: parts);
  }
}
