import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../../core/result.dart';
import '../../domain/entities/audit.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/setting.dart';
import '../../domain/services/local_promotion_fulfillment_service.dart';
import '../../domain/services/promotion_reward_template.dart';
import '../../domain/services/reward_probe_place.dart';
import '../../domain/services/reward_probe_swap.dart';
import '../../domain/services/reward_probe_rotate.dart';
import '../../domain/services/reward_probe_reverse_span.dart';
import '../../domain/services/reward_probe_rotate_span.dart';
import '../../domain/services/reward_probe_rotate_span_steps.dart';
import '../../domain/services/reward_probe_rotate_open_span_steps.dart';
import '../../domain/services/reward_probe_reverse_open_span.dart';
import '../../domain/services/reward_probe_reverse_open_span_interior.dart';
import '../../domain/services/reward_probe_rotate_open_span_interior_steps.dart';
import '../../domain/services/reward_probe_advance_open_span_interior.dart';
import '../../domain/services/reward_probe_delay_open_span_interior.dart';
import '../../domain/services/reward_probe_delay_open_span_interior_steps.dart';
import '../../domain/services/reward_probe_advance_open_span_interior_steps.dart';
import '../../domain/services/reward_probe_swap_open_span.dart';
import '../../domain/services/reward_probe_swap_open_span_interior_steps.dart';
import '../../domain/services/reward_probe_swap_open_span_interior_steps_back.dart';
import '../../domain/services/reward_probe_swap_open_span_interior_neighbor_steps_back.dart';
import '../../domain/services/reward_probe_swap_open_span_interior_neighbor_steps.dart';
import '../../domain/services/reward_probe_swap_open_span_interior_mirror_steps.dart';
import '../../domain/services/reward_probe_rotate_open_span_interior_mirror_steps.dart';
import '../../domain/services/reward_probe_rotate_open_span_interior_mirror_steps_back.dart';
import '../../domain/services/reward_probe_rotate_open_span_interior_mirror_count_steps.dart';
import '../../domain/services/reward_probe_rotate_open_span_interior_mirror_count_steps_back.dart';
import '../../domain/services/reward_probe_shift_open_span_interior_mirror_gap_steps.dart';
import '../../domain/services/reward_probe_shift_open_span_interior_mirror_gap_count_steps.dart';
import '../../domain/services/reward_probe_shift_open_span_interior_mirror_gap_count_steps_back.dart';
import '../../domain/services/reward_probe_reverse_open_span_interior_mirror_gap.dart';
import '../../domain/services/reward_probe_reverse_open_span_interior_mirror_edge_gap.dart';
import '../../domain/services/reward_probe_reverse_open_span_interior_mirror_both_gaps.dart';
import '../../domain/services/reward_probe_shift_open_span_interior_mirror_gap_steps_back.dart';
import '../../platform/sms_bridge.dart';
import '../app_scope.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_surface_card.dart';

/// تحرير قالب رسالة المكافأة من شاشة العروض مع تتبّع الكتابة قبل الحفظ.
///
/// بدون [promotionId] يُحفظ القالب العام. مع معرّف العرض يُحفظ تخصيص هذا العرض فقط.
/// مع [customerId] ومعرّف العرض يُحفظ تخصيص هذا العميل داخل العرض.
/// مع [customerId] دون عرض يُحفظ قالب العميل العام لكل العروض.
Future<bool?> showOffersRewardTemplateSheet(
  BuildContext context, {
  String? promotionId,
  String? promotionTitle,
  String? customerId,
  String? customerLabel,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _OffersRewardTemplateSheet(
      promotionId: promotionId,
      promotionTitle: promotionTitle,
      customerId: customerId,
      customerLabel: customerLabel,
    ),
  );
}

class _OffersRewardTemplateSheet extends StatefulWidget {
  const _OffersRewardTemplateSheet({
    this.promotionId,
    this.promotionTitle,
    this.customerId,
    this.customerLabel,
  });

  final String? promotionId;
  final String? promotionTitle;
  final String? customerId;
  final String? customerLabel;

  @override
  State<_OffersRewardTemplateSheet> createState() =>
      _OffersRewardTemplateSheetState();
}

class _OffersRewardTemplateSheetState extends State<_OffersRewardTemplateSheet> {
  final _body = TextEditingController();
  final _phone = TextEditingController();
  final _placePosition = TextEditingController();
  final _spanSteps = TextEditingController();
  final _spanFrom = TextEditingController();
  var _loading = true;
  var _busy = false;
  var _probing = false;
  var _dirty = false;
  StreamSubscription<SmsDeliveryEvent>? _probeDelivery;
  String _draft = '';
  String? _status;
  bool _statusIsError = true;
  String? _storedGlobal;
  String? _storedOffer;
  String? _storedCustomer;
  String? _storedCustomerGlobal;
  RewardProbeReceipt? _probeReceipt;
  var _useLiveCard = false;
  var _holdNextPayout = false;
  RewardProbeCardSnapshot? _liveCard;
  List<RewardProbeCardSnapshot> _availableCards = const [];
  String? _holdReservationId;
  int _holdQueueCount = 0;
  List<String> _queuedCardIds = const [];

  String get _fallback =>
      LocalPromotionFulfillmentService.defaultRewardSmsTemplate;

  @override
  void initState() {
    super.initState();
    _body.addListener(_onTyped);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _onTyped() {
    final next = _body.text;
    if (next == _draft && _dirty) return;
    final receipt = _probeReceipt;
    setState(() {
      _draft = next;
      _dirty = true;
      if (receipt == null) {
        _status = null;
        _statusIsError = true;
      } else {
        _status = receipt.labelFor(_currentProbeBody());
        _statusIsError = receipt.isError || !receipt.matchesBody(_currentProbeBody());
      }
    });
  }

  String? _currentProbeBody() {
    final rendered = PromotionRewardTemplate.probeBody(
      _body.text,
      values: _probeValues,
    );
    return rendered is Success<String> ? rendered.value : null;
  }

  Map<String, String> get _probeValues => PromotionRewardTemplate.probeValues(
        card: _useLiveCard ? _liveCard : null,
        promotionName: widget.promotionTitle,
        customerName: widget.customerLabel,
      );

  Future<void> _toggleLiveCard(bool enabled) async {
    if (!enabled) {
      await _releaseHold();
      if (!mounted) return;
      setState(() {
        _useLiveCard = false;
        _holdNextPayout = false;
        _liveCard = null;
        _availableCards = const [];
        final receipt = _probeReceipt;
        _status = receipt?.labelFor(_currentProbeBody());
        _statusIsError = receipt == null ||
            receipt.isError ||
            !receipt.matchesBody(_currentProbeBody() ?? '');
      });
      return;
    }
    final c = AppScope.of(context);
    final listed = await c.cards.listByStatus(CardStatus.available);
    if (!mounted) return;
    if (listed is! Success<List<Card>> || listed.value.isEmpty) {
      setState(() {
        _useLiveCard = false;
        _liveCard = null;
        _availableCards = const [];
        _status = 'لا يوجد كرت متاح. بقيت المعاينة على القيم التجريبية';
        _statusIsError = true;
      });
      return;
    }
    final snapshots = <RewardProbeCardSnapshot>[];
    for (final card in listed.value.take(40)) {
      final category = await c.categories.findById(card.categoryId);
      if (!mounted) return;
      final found = category is Success<CardCategory?> ? category.value : null;
      final title = found?.name.trim().isNotEmpty == true
          ? found!.name.trim()
          : 'كرت متاح';
      final amount = found == null
          ? PromotionRewardTemplate.sampleValues['amount']!
          : (found.faceValue.minorUnits / 100).toStringAsFixed(2);
      snapshots.add(
        RewardProbeCardSnapshot(
          cardId: card.id,
          categoryId: card.categoryId,
          title: title,
          serial: card.serialNumber,
          secret: card.secretCode,
          amount: amount,
        ),
      );
    }
    final selected = PromotionRewardTemplate.selectProbeCard(snapshots);
    final holding = await _holdMatches(selected);
    if (!mounted) return;
    setState(() {
      _useLiveCard = selected != null;
      _availableCards = snapshots;
      _liveCard = selected;
      _holdNextPayout = holding;
      _status = selected == null
          ? 'لا يوجد كرت متاح. بقيت المعاينة على القيم التجريبية'
          : holding
              ? _holdStatus
              : 'المعاينة تعرض الكرت المختار دون حجز أو خصم';
      _statusIsError = selected == null;
    });
  }

  Future<void> _selectLiveCard(String? cardId) async {
    final selected = PromotionRewardTemplate.selectProbeCard(
      _availableCards,
      selectedId: cardId,
    );
    if (selected == null) return;
    if (_holdNextPayout && selected.cardId != _liveCard?.cardId) {
      final moved = await _holdCard(selected);
      if (!mounted || !moved) return;
      return;
    }
    final holding = await _holdMatches(selected);
    if (!mounted) return;
    setState(() {
      _liveCard = selected;
      _holdNextPayout = holding;
      _status = holding
          ? _holdStatus
          : 'المعاينة تعرض الكرت المختار دون حجز أو خصم';
      _statusIsError = false;
    });
  }

  Future<bool> _holdMatches(RewardProbeCardSnapshot? card) async {
    if (card == null || card.categoryId.isEmpty) return false;
    final c = AppScope.of(context);
    final found = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = found is Success<AppSetting?> ? found.value?.value : null;
    final hold = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: _holdCustomerId,
    );
    if (hold == null || !hold.isActiveAt(c.clock.now()) || !hold.holdsCard(card.cardId)) {
      return false;
    }
    _holdReservationId = hold.cardFor(card.cardId)?.reservationId;
    _holdQueueCount = hold.cards.length;
    _queuedCardIds = [for (final item in hold.cards) item.cardId];
    return true;
  }

  Future<void> _toggleHold(bool enabled) async {
    final card = _liveCard;
    if (card == null) return;
    if (!enabled) {
      await _releaseHold();
      if (!mounted) return;
      setState(() {
        _holdNextPayout = false;
        _status = 'المعاينة تعرض الكرت المختار دون حجز أو خصم';
        _statusIsError = false;
      });
      return;
    }
    await _holdCard(card);
  }

  Future<bool> _holdCard(RewardProbeCardSnapshot card) async {
    if (card.categoryId.isEmpty) return false;
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final now = c.clock.now();
    final reservationId = c.ids.next('reward-probe-hold');
    final holdFor = _holdDuration;
    final reserved = await c.cards.reserve(
      card.cardId,
      CardReservation(
        reservationId: reservationId,
        reservedAt: now,
        expiresAt: now.add(holdFor),
      ),
    );
    if (!mounted) return false;
    if (reserved is Failure<void>) {
      setState(() {
        _busy = false;
        _status = 'تعذر حجز الكرت للصرف التالي';
        _statusIsError = true;
      });
      return false;
    }
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final hold = RewardProbeHold(
      categoryId: card.categoryId,
      cardId: card.cardId,
      reservationId: reservationId,
      expiresAt: now.add(holdFor),
      customerId: _holdCustomerId ?? '',
    );
    final encoded = PromotionRewardTemplate.enqueueCrossCategoryHold(raw, hold);
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    final stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_held',
        occurredAt: now,
        payloadJson: '{"categoryId":"${card.categoryId}","reservationId":"$reservationId","customerId":"${_holdCustomerId ?? ''}"}',
      ),
    );
    if (!mounted) return false;
    setState(() {
      _busy = false;
      _liveCard = card;
      _holdNextPayout = true;
      _holdReservationId = reservationId;
      _holdQueueCount = stored?.cards.length ?? 1;
      _queuedCardIds = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
      _status = _holdStatus;
      _statusIsError = false;
    });
    return true;
  }

  Future<void> _releaseHold({bool quiet = false}) async {
    final card = _liveCard;
    final reservationId = _holdReservationId;
    if (card == null || reservationId == null || card.categoryId.isEmpty) {
      _holdReservationId = null;
      _holdQueueCount = 0;
      _queuedCardIds = const [];
      return;
    }
    final c = AppScope.of(context);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final hold = PromotionRewardTemplate.lookupCrossCategoryHold(
      raw,
      customerId: _holdCustomerId,
    );
    final queued = hold?.cards ?? [RewardProbeHeldCard(cardId: card.cardId, reservationId: reservationId)];
    for (final item in queued) {
      await c.cards.releaseReservation(item.cardId, item.reservationId);
    }
    final now = c.clock.now();
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: _holdCustomerId == null
            ? PromotionRewardTemplate.clearHold(
                PromotionRewardTemplate.clearCrossCategoryHold(raw),
                card.categoryId,
              )
            : PromotionRewardTemplate.clearCrossCategoryHold(
                raw,
                customerId: _holdCustomerId,
              ),
        updatedAt: now,
      ),
    );
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_released',
        occurredAt: now,
        payloadJson: '{"categoryId":"${card.categoryId}","reservationId":"$reservationId","customerId":"${_holdCustomerId ?? ''}"}',
      ),
    );
    _holdReservationId = null;
    _holdQueueCount = 0;
      _queuedCardIds = const [];
    if (!quiet && mounted) {
      setState(() => _holdNextPayout = false);
    }
  }

  /// يُخرج الكرت الظاهر فقط. بقية الطابور تبقى محجوزة حتى الصرف أو الإيقاف.
  Future<void> _dropSelectedHold() async {
    final card = _liveCard;
    final reservationId = _holdReservationId;
    if (card == null || reservationId == null || card.categoryId.isEmpty) return;
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    await c.cards.releaseReservation(card.cardId, reservationId);
    final now = c.clock.now();
    final encoded = PromotionRewardTemplate.dropQueuedCard(
      raw,
      cardId: card.cardId,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    final remaining = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_dropped',
        occurredAt: now,
        payloadJson: '{"categoryId":"${card.categoryId}","reservationId":"$reservationId","customerId":"${_holdCustomerId ?? ''}","remaining":"${remaining?.cards.length ?? 0}"}',
      ),
    );
    if (!mounted) return;
    final next = remaining?.cards.isNotEmpty == true ? remaining!.cards.first : null;
    setState(() {
      _busy = false;
      _holdNextPayout = next != null;
      _holdReservationId = next?.reservationId;
      _holdQueueCount = remaining?.cards.length ?? 0;
      _queuedCardIds = [for (final item in remaining?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
      _status = next == null
          ? 'أُخرج الكرت من الطابور ولم يبقَ حجز'
          : 'أُخرج الكرت الظاهر وبقي ${_holdQueueCount} في الطابور';
      _statusIsError = false;
    });
  }

  /// يقدّم الكرت الظاهر ليُصرف أولاً دون تحرير حجزه أو مسح بقية الطابور.
  Future<void> _promoteSelectedHold() async {
    final card = _liveCard;
    if (card == null || _queuedCardIds.isEmpty || _queuedCardIds.first == card.cardId) {
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = PromotionRewardTemplate.promoteQueuedCard(
      raw,
      cardId: card.cardId,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    final stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_promoted',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
      _status = _queuedCardIds.isNotEmpty && _queuedCardIds.first == card.cardId
          ? 'قُدّم الكرت الظاهر ليُصرف أولاً، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تقديم الكرت الظاهر';
      _statusIsError = _queuedCardIds.isEmpty || _queuedCardIds.first != card.cardId;
    });
  }


  /// يؤخّر الكرت الظاهر خطوة واحدة دون تحرير حجزه أو مسح بقية الطابور.
  Future<void> _delaySelectedHold() async {
    final card = _liveCard;
    if (card == null || _queuedCardIds.length < 2 || _queuedCardIds.last == card.cardId) {
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = PromotionRewardTemplate.delayQueuedCard(
      raw,
      cardId: card.cardId,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_delayed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final previousIndex = _queuedCardIds.indexOf(card.cardId);
    final nextIndex = ids.indexOf(card.cardId);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = nextIndex == previousIndex + 1
          ? 'أُخّر الكرت الظاهر خطوة واحدة، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تأخير الكرت الظاهر';
      _statusIsError = nextIndex != previousIndex + 1;
    });
  }

  /// يقدّم الكرت الظاهر خطوة واحدة نحو أول الصرف دون تحرير حجزه.
  Future<void> _advanceSelectedHold() async {
    final card = _liveCard;
    if (card == null || _queuedCardIds.length < 2 || _queuedCardIds.first == card.cardId) {
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = PromotionRewardTemplate.advanceQueuedCard(
      raw,
      cardId: card.cardId,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_advanced',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final previousIndex = _queuedCardIds.indexOf(card.cardId);
    final nextIndex = ids.indexOf(card.cardId);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = nextIndex == previousIndex - 1
          ? 'قُدّم الكرت الظاهر خطوة واحدة، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تقديم الكرت الظاهر خطوة واحدة';
      _statusIsError = nextIndex != previousIndex - 1;
    });
  }

  /// يؤخّر الكرت الظاهر ليُصرف آخراً دون تحرير حجزه أو مسح بقية الطابور.
  Future<void> _demoteSelectedHold() async {
    final card = _liveCard;
    if (card == null || _queuedCardIds.length < 2 || _queuedCardIds.last == card.cardId) {
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = PromotionRewardTemplate.demoteQueuedCard(
      raw,
      cardId: card.cardId,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_demoted',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final nextIndex = ids.indexOf(card.cardId);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = nextIndex == ids.length - 1
          ? 'أُخّر الكرت الظاهر ليُصرف آخراً، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تأخير الكرت الظاهر إلى آخر الطابور';
      _statusIsError = nextIndex != ids.length - 1;
    });
  }



  /// ينقل الكرت الظاهر إلى موضع صرف يدخله المشغّل دون تحرير حجزه.
  Future<void> _placeSelectedHold() async {
    final card = _liveCard;
    final position = int.tryParse(_placePosition.text.trim());
    if (card == null || _queuedCardIds.length < 2 || position == null || position < 1) {
      return;
    }
    final currentIndex = _queuedCardIds.indexOf(card.cardId);
    if (currentIndex == (position - 1).clamp(0, _queuedCardIds.length - 1)) {
      setState(() {
        _status = 'الكرت الظاهر في الموضع $position أصلاً';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbePlace.placeQueuedCard(
      raw,
      cardId: card.cardId,
      position: position,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_placed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","position":$position,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final nextIndex = ids.indexOf(card.cardId);
    final target = (position - 1).clamp(0, ids.isEmpty ? 0 : ids.length - 1);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = nextIndex == target
          ? 'نُقل الكرت الظاهر إلى الموضع ${nextIndex + 1}، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر نقل الكرت الظاهر إلى الموضع المطلوب';
      _statusIsError = nextIndex != target;
    });
  }

  /// يبادل الكرت الظاهر مع كرت الموضع المدخل دون إزاحة بقية الطابور.
  Future<void> _swapSelectedHold() async {
    final card = _liveCard;
    final position = int.tryParse(_placePosition.text.trim());
    if (card == null || _queuedCardIds.length < 2 || position == null || position < 1) {
      return;
    }
    final currentIndex = _queuedCardIds.indexOf(card.cardId);
    if (currentIndex == (position - 1).clamp(0, _queuedCardIds.length - 1)) {
      setState(() {
        _status = 'الكرت الظاهر في الموضع $position أصلاً';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwap.swapQueuedCard(
      raw,
      cardId: card.cardId,
      position: position,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_swapped',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","position":$position,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final nextIndex = ids.indexOf(card.cardId);
    final target = (position - 1).clamp(0, ids.isEmpty ? 0 : ids.length - 1);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = nextIndex == target
          ? 'بُودل الكرت الظاهر مع الموضع ${nextIndex + 1}، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الكرت الظاهر مع الموضع المطلوب';
      _statusIsError = nextIndex != target;
    });
  }


  /// يدوّر الطابور الذي يحمل الكرت الظاهر بعدد خطوات يدخله المشغّل.
  Future<void> _rotateSelectedHold() async {
    final card = _liveCard;
    final steps = int.tryParse(_placePosition.text.trim());
    if (card == null || _queuedCardIds.length < 2 || steps == null || steps < 1) {
      return;
    }
    final shift = steps % _queuedCardIds.length;
    if (shift == 0) {
      setState(() {
        _status = 'التدوير بعدد يساوي طول الطابور لا يغيّر الترتيب';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotate.rotateQueuedCard(
      raw,
      cardId: card.cardId,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_rotated',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = [..._queuedCardIds.sublist(shift), ..._queuedCardIds.sublist(0, shift)];
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر الطابور $shift خطوات، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير الطابور';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يعكس المقطع بين الكرت الظاهر والموضع المدخل دون تحريك ما خارجه.
  Future<void> _reverseSpanSelectedHold() async {
    final card = _liveCard;
    final position = int.tryParse(_placePosition.text.trim());
    if (card == null || _queuedCardIds.length < 2 || position == null || position < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    if (visibleIndex < 0 || position > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (position == visibleIndex + 1) {
      setState(() {
        _status = 'الكرت الظاهر في الموضع $position أصلاً';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeReverseSpan.reverseQueuedSpan(
      raw,
      cardId: card.cardId,
      position: position,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_span_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","position":$position,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final start = visibleIndex < position - 1 ? visibleIndex : position - 1;
    final end = visibleIndex < position - 1 ? position - 1 : visibleIndex;
    final expected = [
      ..._queuedCardIds.sublist(0, start),
      ..._queuedCardIds.sublist(start, end + 1).reversed,
      ..._queuedCardIds.sublist(end + 1),
    ];
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'عُكس المقطع من الموضع ${start + 1} إلى $position، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس مقطع الطابور';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يدوّر المقطع بين الكرت الظاهر والموضع المدخل خطوة واحدة دون تحريك ما خارجه.
  Future<void> _rotateSpanSelectedHold() async {
    final card = _liveCard;
    final position = int.tryParse(_placePosition.text.trim());
    if (card == null || _queuedCardIds.length < 2 || position == null || position < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    if (visibleIndex < 0 || position > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (position == visibleIndex + 1) {
      setState(() {
        _status = 'الكرت الظاهر في الموضع $position أصلاً';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateSpan.rotateQueuedSpan(
      raw,
      cardId: card.cardId,
      position: position,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_span_rotated',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","position":$position,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final start = visibleIndex < position - 1 ? visibleIndex : position - 1;
    final end = visibleIndex < position - 1 ? position - 1 : visibleIndex;
    final span = _queuedCardIds.sublist(start, end + 1);
    final expected = [
      ..._queuedCardIds.sublist(0, start),
      ...span.sublist(1),
      span.first,
      ..._queuedCardIds.sublist(end + 1),
    ];
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر المقطع من الموضع ${start + 1} إلى ${end + 1} خطوة واحدة، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير مقطع الطابور';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }




  /// يعكس مقطعًا بين موضعين مدخلين. الكرت الظاهر يحدد الطابور ويقع داخل المقطع.
  Future<void> _reverseOpenSpanSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    if (card == null ||
        _queuedCardIds.length < 2 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (start == end) {
      setState(() {
        _status = 'طرفا المقطع هما نفس الموضع';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex < start - 1 || visibleIndex > end - 1) {
      setState(() {
        _status = 'الكرت الظاهر خارج المقطع المختار';
        _statusIsError = true;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeReverseOpenSpan.reverseOpenSpan(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final span = _queuedCardIds.sublist(start - 1, end).reversed.toList();
    final expected = [
      ..._queuedCardIds.sublist(0, start - 1),
      ...span,
      ..._queuedCardIds.sublist(end),
    ];
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'عُكس المقطع من الموضع $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس المقطع بين الموضعين';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }



  /// يعكس الكروت بين طرفي المقطع دون تحريك الطرفين. الكرت الظاهر يحدد الطابور ويقع داخل المقطع.
  Future<void> _reverseOpenSpanInteriorSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    if (card == null ||
        _queuedCardIds.length < 3 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 2) {
      setState(() {
        _status = 'لا كروت بين طرفي المقطع';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex < start - 1 || visibleIndex > end - 1) {
      setState(() {
        _status = 'الكرت الظاهر خارج المقطع المختار';
        _statusIsError = true;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeReverseOpenSpanInterior.reverseOpenSpanInterior(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final interior = expected.sublist(start, end - 1).reversed.toList();
    expected.replaceRange(start, end - 1, interior);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'عُكس داخل المقطع من الموضع $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يدوّر الكروت بين طرفي المقطع بعدد خطوات دون تحريك الطرفين.
  Future<void> _rotateOpenSpanInteriorStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps == null ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتدوير';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex < start - 1 || visibleIndex > end - 1) {
      setState(() {
        _status = 'الكرت الظاهر خارج المقطع المختار';
        _statusIsError = true;
      });
      return;
    }
    final interiorLength = end - start - 1;
    final shift = steps % interiorLength;
    if (shift == 0) {
      setState(() {
        _status = 'التدوير بعدد يساوي طول الداخل لا يغيّر الترتيب';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateOpenSpanInteriorSteps.rotateOpenSpanInteriorSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_rotated_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final interior = _queuedCardIds.sublist(start, end - 1);
    final expected = List<String>.of(_queuedCardIds);
    expected.replaceRange(start, end - 1, [
      ...interior.sublist(shift),
      ...interior.sublist(0, shift),
    ]);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر داخل المقطع من الموضع $start إلى $end بعدد $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يقدّم الكرت الظاهر خطوة واحدة داخل المقطع دون تحريك الطرفين.
  Future<void> _advanceOpenSpanInteriorSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتقديم';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex >= end - 2) {
      setState(() {
        _status = 'الكرت الظاهر على حافة الداخل باتجاه الطرف الأعلى';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeAdvanceOpenSpanInterior.advanceOpenSpanInterior(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_advanced',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final currentCard = expected[visibleIndex];
    expected[visibleIndex] = expected[visibleIndex + 1];
    expected[visibleIndex + 1] = currentCard;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'قُدّم الكرت الظاهر خطوة داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تقديم الكرت الظاهر داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يؤخّر الكرت الظاهر خطوة واحدة داخل المقطع دون تحريك الطرفين.
  Future<void> _delayOpenSpanInteriorSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتأخير';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex <= start) {
      setState(() {
        _status = 'الكرت الظاهر على حافة الداخل باتجاه الطرف الأدنى';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeDelayOpenSpanInterior.delayOpenSpanInterior(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_delayed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final currentCard = expected[visibleIndex];
    expected[visibleIndex] = expected[visibleIndex - 1];
    expected[visibleIndex - 1] = currentCard;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'أُخّر الكرت الظاهر خطوة داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تأخير الكرت الظاهر داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يؤخّر الكرت الظاهر بعدد خطوات داخل المقطع دون تحريك الطرفين.
  Future<void> _delayOpenSpanInteriorStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتأخير';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرت الظاهر من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeDelayOpenSpanInteriorSteps.delayOpenSpanInteriorSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_delayed_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final currentCard = expected.removeAt(visibleIndex);
    expected.insert(visibleIndex - steps, currentCard);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'أُخّر الكرت الظاهر $steps خطوة داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تأخير الكرت الظاهر بعدد خطوات داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يقدّم الكرت الظاهر بعدد خطوات نحو الطرف الأعلى داخل مقطع مدخل دون تحريك الطرفين.
  Future<void> _advanceOpenSpanInteriorStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتقديم';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرت الظاهر من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeAdvanceOpenSpanInteriorSteps.advanceOpenSpanInteriorSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_advanced_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final currentCard = expected.removeAt(visibleIndex);
    expected.insert(visibleIndex + steps, currentCard);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'قُدّم الكرت الظاهر $steps خطوة داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تقديم الكرت الظاهر بعدد خطوات داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يبدّل الكرت الظاهر مع كرت بعدد خطوات نحو الطرف الأعلى داخل مقطع مدخل دون تحريك الطرفين.
  Future<void> _swapOpenSpanInteriorStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتبديل';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التبديل من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwapOpenSpanInteriorSteps.swapOpenSpanInteriorSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_swapped_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final partner = expected[visibleIndex + steps];
    expected[visibleIndex + steps] = expected[visibleIndex];
    expected[visibleIndex] = partner;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'بُدّل الكرت الظاهر مع كرت يبعد $steps خطوة نحو الأعلى داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الكرت الظاهر بعدد خطوات داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يبدّل الكرت الظاهر مع كرت بعدد خطوات نحو الطرف الأدنى داخل مقطع مدخل دون تحريك الطرفين.
  Future<void> _swapOpenSpanInteriorStepsBackSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 4 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 3) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع للتبديل';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التبديل من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwapOpenSpanInteriorStepsBack.swapOpenSpanInteriorStepsBack(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_swapped_steps_back',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final partner = expected[visibleIndex - steps];
    expected[visibleIndex - steps] = expected[visibleIndex];
    expected[visibleIndex] = partner;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'بُدّل الكرت الظاهر مع كرت يبعد $steps خطوة نحو الأدنى داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الكرت الظاهر بعدد خطوات نحو الأدنى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يبدّل كرتًا أدنى من الكرت الظاهر بعدد خطوات مع الكرت الذي قبله داخل مقطع مدخل دون تحريك الطرفين.
  Future<void> _swapOpenSpanInteriorNeighborStepsBackSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتبديل كرت غير الظاهر';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps - 1 <= start - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التبديل من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwapOpenSpanInteriorNeighborStepsBack
        .swapOpenSpanInteriorNeighborStepsBack(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_neighbor_swapped_steps_back',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final target = visibleIndex - steps;
    final neighbor = target - 1;
    final partner = expected[neighbor];
    expected[neighbor] = expected[target];
    expected[target] = partner;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'بُدّل كرت يبعد $steps خطوة نحو الأدنى مع الكرت الذي قبله داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الكرت الأدنى بعدد خطوات داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يبدّل كرتًا أعلى من الكرت الظاهر بعدد خطوات مع الكرت الذي بعده داخل مقطع مدخل دون تحريك الطرفين.
  Future<void> _swapOpenSpanInteriorNeighborStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتبديل كرت غير الظاهر';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex + steps + 1 >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التبديل من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwapOpenSpanInteriorNeighborSteps
        .swapOpenSpanInteriorNeighborSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_neighbor_swapped_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final target = visibleIndex + steps;
    final neighbor = target + 1;
    final partner = expected[neighbor];
    expected[neighbor] = expected[target];
    expected[target] = partner;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'بُدّل كرت يبعد $steps خطوة نحو الأعلى مع الكرت الذي بعده داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الكرت الأعلى بعدد خطوات داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يبدّل الكرتين المقابلتين بعدد خطوات حول الكرت الظاهر داخل مقطع مدخل دون تحريك الطرفين.
  Future<void> _swapOpenSpanInteriorMirrorStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتبديل كرتين مقابلتين';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التبديل من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwapOpenSpanInteriorMirrorSteps
        .swapOpenSpanInteriorMirrorSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_swapped_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    final partner = expected[higher];
    expected[higher] = expected[lower];
    expected[lower] = partner;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'بُدّلت الكرتان المقابلتان على مسافة $steps حول الكرت الظاهر داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الكرتين المقابلتين داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يدوّر الكرت الظاهر مع الكرتين المقابلتين خطوة نحو الأعلى. الطرفان لا يتحركان.
  Future<void> _rotateOpenSpanInteriorMirrorStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتدوير الكرت الظاهر مع مقابليه';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التدوير من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateOpenSpanInteriorMirrorSteps
        .rotateOpenSpanInteriorMirrorSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_rotated_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    final lowerCard = expected[lower];
    final visibleCard = expected[visibleIndex];
    final higherCard = expected[higher];
    expected[lower] = higherCard;
    expected[visibleIndex] = lowerCard;
    expected[higher] = visibleCard;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر الكرت الظاهر مع الكرتين المقابلتين خطوة نحو الأعلى على مسافة $steps داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير الكرت الظاهر مع الكرتين المقابلتين داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يدوّر الكرت الظاهر مع الكرتين المقابلتين خطوة نحو الأدنى. الطرفان لا يتحركان.
  Future<void> _rotateOpenSpanInteriorMirrorStepsBackSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتدوير الكرت الظاهر مع مقابليه';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التدوير من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateOpenSpanInteriorMirrorStepsBack
        .rotateOpenSpanInteriorMirrorStepsBack(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_rotated_steps_back',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    final lowerCard = expected[lower];
    final visibleCard = expected[visibleIndex];
    final higherCard = expected[higher];
    expected[lower] = visibleCard;
    expected[visibleIndex] = higherCard;
    expected[higher] = lowerCard;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر الكرت الظاهر مع الكرتين المقابلتين خطوة نحو الأدنى على مسافة $steps داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير الكرت الظاهر مع الكرتين المقابلتين نحو الأدنى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يدوّر الكرت الظاهر مع الكرتين المقابلتين بعدد خطوات نحو الأعلى. الطرفان لا يتحركان.
  Future<void> _rotateOpenSpanInteriorMirrorCountStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1 ||
        steps % 3 == 0) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتدوير الكرت الظاهر مع مقابليه';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التدوير من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateOpenSpanInteriorMirrorCountSteps
        .rotateOpenSpanInteriorMirrorCountSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_rotated_count_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    var lowerCard = expected[lower];
    var visibleCard = expected[visibleIndex];
    var higherCard = expected[higher];
    for (var turn = 0; turn < steps % 3; turn++) {
      final rotatedLower = higherCard;
      final rotatedVisible = lowerCard;
      final rotatedHigher = visibleCard;
      lowerCard = rotatedLower;
      visibleCard = rotatedVisible;
      higherCard = rotatedHigher;
    }
    expected[lower] = lowerCard;
    expected[visibleIndex] = visibleCard;
    expected[higher] = higherCard;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر الكرت الظاهر مع الكرتين المقابلتين $steps خطوة نحو الأعلى داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير الكرت الظاهر مع الكرتين المقابلتين بعدد خطوات نحو الأعلى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يدوّر الكرت الظاهر مع الكرتين المقابلتين بعدد خطوات نحو الأدنى. الطرفان لا يتحركان.
  Future<void> _rotateOpenSpanInteriorMirrorCountStepsBackSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 5 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 1 ||
        steps % 3 == 0) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 4) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لتدوير الكرت الظاهر مع مقابليه';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج التدوير من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateOpenSpanInteriorMirrorCountStepsBack
        .rotateOpenSpanInteriorMirrorCountStepsBack(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_rotated_count_steps_back',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    var lowerCard = expected[lower];
    var visibleCard = expected[visibleIndex];
    var higherCard = expected[higher];
    for (var turn = 0; turn < steps % 3; turn++) {
      final rotatedLower = visibleCard;
      final rotatedVisible = higherCard;
      final rotatedHigher = lowerCard;
      lowerCard = rotatedLower;
      visibleCard = rotatedVisible;
      higherCard = rotatedHigher;
    }
    expected[lower] = lowerCard;
    expected[visibleIndex] = visibleCard;
    expected[higher] = higherCard;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر الكرت الظاهر مع الكرتين المقابلتين $steps خطوة نحو الأدنى داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير الكرت الظاهر مع الكرتين المقابلتين بعدد خطوات نحو الأدنى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يزيح الكروت بين الكرتين المقابلتين خطوة نحو الأعلى. الظاهر والمقابلتان والطرفان لا يتحركون.
  Future<void> _shiftOpenSpanInteriorMirrorGapStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 9 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 8) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لإزاحة ما بين الكرتين المقابلتين';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeShiftOpenSpanInteriorMirrorGapSteps
        .shiftOpenSpanInteriorMirrorGapSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_gap_shifted_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    if (visibleIndex - lower > 2) {
      final last = expected[visibleIndex - 1];
      for (var index = visibleIndex - 1; index > lower + 1; index--) {
        expected[index] = expected[index - 1];
      }
      expected[lower + 1] = last;
    }
    if (higher - visibleIndex > 2) {
      final last = expected[higher - 1];
      for (var index = higher - 1; index > visibleIndex + 1; index--) {
        expected[index] = expected[index - 1];
      }
      expected[visibleIndex + 1] = last;
    }
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'أُزيحت الكروت بين الكرتين المقابلتين خطوة نحو الأعلى داخل المقطع من $start إلى $end بمسافة $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر إزاحة الكروت بين الكرتين المقابلتين خطوة نحو الأعلى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يزيح الكروت بين الكرتين المقابلتين خطوة نحو الأدنى. الظاهر والمقابلتان والطرفان لا يتحركون.
  Future<void> _shiftOpenSpanInteriorMirrorGapCountStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 9 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 8) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لإزاحة ما بين الكرتين المقابلتين بعدد خطوات';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeShiftOpenSpanInteriorMirrorGapCountSteps
        .shiftOpenSpanInteriorMirrorGapCountSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_gap_shifted_count_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    final lowerSpan = visibleIndex - 1 - (lower + 1) + 1;
    final higherSpan = higher - 1 - (visibleIndex + 1) + 1;
    if (lowerSpan > 1) {
      final turns = steps % lowerSpan;
      for (var turn = 0; turn < turns; turn++) {
        final last = expected[visibleIndex - 1];
        for (var index = visibleIndex - 1; index > lower + 1; index--) {
          expected[index] = expected[index - 1];
        }
        expected[lower + 1] = last;
      }
    }
    if (higherSpan > 1) {
      final turns = steps % higherSpan;
      for (var turn = 0; turn < turns; turn++) {
        final last = expected[higher - 1];
        for (var index = higher - 1; index > visibleIndex + 1; index--) {
          expected[index] = expected[index - 1];
        }
        expected[visibleIndex + 1] = last;
      }
    }
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'أُزيحت الكروت بين الكرتين المقابلتين بعدد $steps خطوات نحو الأعلى داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر إزاحة الكروت بين الكرتين المقابلتين بعدد خطوات نحو الأعلى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }


  /// يزيح الكروت بين الكرتين المقابلتين بعدد خطوات نحو الأدنى. الظاهر والمقابلتان والطرفان لا يتحركون.



  Future<void> _reverseOpenSpanInteriorMirrorBothGapsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 13 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 12) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لعكس ما بين الكرتين المقابلتين والظاهر والطرفين';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex - steps < start + 2 || visibleIndex + steps > end - 4) {
      setState(() {
        _status = 'لا يكفي كرتان بين الكرت المقابل وطرف المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeReverseOpenSpanInteriorMirrorBothGaps
        .reverseOpenSpanInteriorMirrorBothGaps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_both_gaps_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    void reverseRange(int from, int to) {
      if (to - from < 1) return;
      var left = from;
      var right = to;
      while (left < right) {
        final swap = expected[left];
        expected[left] = expected[right];
        expected[right] = swap;
        left++;
        right--;
      }
    }
    reverseRange(start, lower - 1);
    reverseRange(lower + 1, visibleIndex - 1);
    reverseRange(visibleIndex + 1, higher - 1);
    reverseRange(higher + 1, end - 2);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'عُكست الكروت بين الكرتين المقابلتين والكرت الظاهر وطرفي المقطع من $start إلى $end بمسافة $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس الكروت بين الكرتين المقابلتين والكرت الظاهر وطرفي المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  Future<void> _reverseOpenSpanInteriorMirrorEdgeGapSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 13 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 12) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لعكس ما بين الكرتين المقابلتين والطرفين';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex - steps < start + 2 || visibleIndex + steps > end - 4) {
      setState(() {
        _status = 'لا يكفي كرتان بين الكرت المقابل وطرف المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeReverseOpenSpanInteriorMirrorEdgeGap
        .reverseOpenSpanInteriorMirrorEdgeGap(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_edge_gap_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    void reverseRange(int from, int to) {
      if (to - from < 1) return;
      var left = from;
      var right = to;
      while (left < right) {
        final swap = expected[left];
        expected[left] = expected[right];
        expected[right] = swap;
        left++;
        right--;
      }
    }
    reverseRange(start, lower - 1);
    reverseRange(higher + 1, end - 2);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'عُكست الكروت بين الكرتين المقابلتين وطرفي المقطع من $start إلى $end بمسافة $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس الكروت بين الكرتين المقابلتين وطرفي المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  Future<void> _reverseOpenSpanInteriorMirrorGapSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 9 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 8) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لعكس ما بين الكرتين المقابلتين';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeReverseOpenSpanInteriorMirrorGap
        .reverseOpenSpanInteriorMirrorGap(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_gap_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    void reverseRange(int from, int to) {
      if (to - from < 1) return;
      var left = from;
      var right = to;
      while (left < right) {
        final swap = expected[left];
        expected[left] = expected[right];
        expected[right] = swap;
        left++;
        right--;
      }
    }
    reverseRange(lower + 1, visibleIndex - 1);
    reverseRange(visibleIndex + 1, higher - 1);
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'عُكست الكروت بين الكرتين المقابلتين والكرت الظاهر داخل المقطع من $start إلى $end بمسافة $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس الكروت بين الكرتين المقابلتين والكرت الظاهر داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  Future<void> _shiftOpenSpanInteriorMirrorGapCountStepsBackSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 9 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 8) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لإزاحة ما بين الكرتين المقابلتين بعدد خطوات نحو الأدنى';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeShiftOpenSpanInteriorMirrorGapCountStepsBack
        .shiftOpenSpanInteriorMirrorGapCountStepsBack(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_gap_shifted_count_steps_back',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    final lowerSpan = visibleIndex - 1 - (lower + 1) + 1;
    final higherSpan = higher - 1 - (visibleIndex + 1) + 1;
    if (lowerSpan > 1) {
      final turns = steps % lowerSpan;
      for (var turn = 0; turn < turns; turn++) {
        final first = expected[lower + 1];
        for (var index = lower + 1; index < visibleIndex - 1; index++) {
          expected[index] = expected[index + 1];
        }
        expected[visibleIndex - 1] = first;
      }
    }
    if (higherSpan > 1) {
      final turns = steps % higherSpan;
      for (var turn = 0; turn < turns; turn++) {
        final first = expected[visibleIndex + 1];
        for (var index = visibleIndex + 1; index < higher - 1; index++) {
          expected[index] = expected[index + 1];
        }
        expected[higher - 1] = first;
      }
    }
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'أُزيحت الكروت بين الكرتين المقابلتين بعدد $steps خطوات نحو الأدنى داخل المقطع من $start إلى $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر إزاحة الكروت بين الكرتين المقابلتين بعدد خطوات نحو الأدنى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  Future<void> _shiftOpenSpanInteriorMirrorGapStepsBackSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 9 ||
        startPosition == null ||
        endPosition == null ||
        steps == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps < 3) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (end - start < 8) {
      setState(() {
        _status = 'لا يكفي كروت داخل المقطع لإزاحة ما بين الكرتين المقابلتين نحو الأدنى';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex <= start - 1 || visibleIndex >= end - 1) {
      setState(() {
        _status = 'الكرت الظاهر يجب أن يقع بين طرفي المقطع';
        _statusIsError = true;
      });
      return;
    }
    if (visibleIndex - steps <= start - 1 || visibleIndex + steps >= end - 1) {
      setState(() {
        _status = 'عدد الخطوات يخرج الكرتين المقابلتين من داخل المقطع';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeShiftOpenSpanInteriorMirrorGapStepsBack
        .shiftOpenSpanInteriorMirrorGapStepsBack(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_interior_mirror_gap_shifted_steps_back',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final lower = visibleIndex - steps;
    final higher = visibleIndex + steps;
    if (visibleIndex - lower > 2) {
      final first = expected[lower + 1];
      for (var index = lower + 1; index < visibleIndex - 1; index++) {
        expected[index] = expected[index + 1];
      }
      expected[visibleIndex - 1] = first;
    }
    if (higher - visibleIndex > 2) {
      final first = expected[visibleIndex + 1];
      for (var index = visibleIndex + 1; index < higher - 1; index++) {
        expected[index] = expected[index + 1];
      }
      expected[higher - 1] = first;
    }
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'أُزيحت الكروت بين الكرتين المقابلتين خطوة نحو الأدنى داخل المقطع من $start إلى $end بمسافة $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر إزاحة الكروت بين الكرتين المقابلتين خطوة نحو الأدنى داخل المقطع';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يبدّل طرفي مقطع بين موضعين مدخلين. الكرت الظاهر يحدد الطابور ويقع داخل المقطع.
  Future<void> _swapOpenSpanSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    if (card == null ||
        _queuedCardIds.length < 2 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (start == end) {
      setState(() {
        _status = 'طرفا المقطع هما نفس الموضع';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex < start - 1 || visibleIndex > end - 1) {
      setState(() {
        _status = 'الكرت الظاهر خارج المقطع المختار';
        _statusIsError = true;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeSwapOpenSpan.swapOpenSpan(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_swapped',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final expected = List<String>.of(_queuedCardIds);
    final left = expected[start - 1];
    expected[start - 1] = expected[end - 1];
    expected[end - 1] = left;
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'بُدّل الموضع $start مع $end، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تبديل الموضعين';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يدوّر مقطعًا بين موضعين مدخلين بعدد خطوات. الكرت الظاهر يحدد الطابور ويقع داخل المقطع.
  Future<void> _rotateOpenSpanStepsSelectedHold() async {
    final card = _liveCard;
    final startPosition = int.tryParse(_spanFrom.text.trim());
    final endPosition = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 2 ||
        startPosition == null ||
        endPosition == null ||
        startPosition < 1 ||
        endPosition < 1 ||
        steps == null ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    final start = startPosition < endPosition ? startPosition : endPosition;
    final end = startPosition < endPosition ? endPosition : startPosition;
    if (visibleIndex < 0 || end > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (start == end) {
      setState(() {
        _status = 'طرفا المقطع هما نفس الموضع';
        _statusIsError = false;
      });
      return;
    }
    if (visibleIndex < start - 1 || visibleIndex > end - 1) {
      setState(() {
        _status = 'الكرت الظاهر خارج المقطع المختار';
        _statusIsError = true;
      });
      return;
    }
    final spanLength = end - start + 1;
    final shift = steps % spanLength;
    if (shift == 0) {
      setState(() {
        _status = 'التدوير بعدد يساوي طول المقطع لا يغيّر الترتيب';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateOpenSpanSteps.rotateOpenSpanSteps(
      raw,
      cardId: card.cardId,
      startPosition: start,
      endPosition: end,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_open_span_rotated_steps',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","start":$start,"end":$end,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final span = _queuedCardIds.sublist(start - 1, end);
    final expected = [
      ..._queuedCardIds.sublist(0, start - 1),
      ...span.sublist(shift),
      ...span.sublist(0, shift),
      ..._queuedCardIds.sublist(end),
    ];
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر المقطع من الموضع $start إلى $end بعدد $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير المقطع بين الموضعين';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يدوّر المقطع بين الكرت الظاهر والموضع المدخل بعدد خطوات دون تحريك ما خارجه.
  Future<void> _rotateSpanStepsSelectedHold() async {
    final card = _liveCard;
    final position = int.tryParse(_placePosition.text.trim());
    final steps = int.tryParse(_spanSteps.text.trim());
    if (card == null ||
        _queuedCardIds.length < 2 ||
        position == null ||
        position < 1 ||
        steps == null ||
        steps < 1) {
      return;
    }
    final visibleIndex = _queuedCardIds.indexOf(card.cardId);
    if (visibleIndex < 0 || position > _queuedCardIds.length) {
      setState(() {
        _status = 'الموضع خارج طول الطابور';
        _statusIsError = true;
      });
      return;
    }
    if (position == visibleIndex + 1) {
      setState(() {
        _status = 'الكرت الظاهر في الموضع $position أصلاً';
        _statusIsError = false;
      });
      return;
    }
    final start = visibleIndex < position - 1 ? visibleIndex : position - 1;
    final end = visibleIndex < position - 1 ? position - 1 : visibleIndex;
    final spanLength = end - start + 1;
    final shift = steps % spanLength;
    if (shift == 0) {
      setState(() {
        _status = 'التدوير بعدد يساوي طول المقطع لا يغيّر الترتيب';
        _statusIsError = false;
      });
      return;
    }
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = RewardProbeRotateSpanSteps.rotateQueuedSpanSteps(
      raw,
      cardId: card.cardId,
      position: position,
      steps: steps,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_span_rotated_steps',
        occurredAt: now,
        payloadJson:
            '{"customerId":"${_holdCustomerId ?? ''}","position":$position,"steps":$steps,"queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final span = _queuedCardIds.sublist(start, end + 1);
    final expected = [
      ..._queuedCardIds.sublist(0, start),
      ...span.sublist(shift),
      ...span.sublist(0, shift),
      ..._queuedCardIds.sublist(end + 1),
    ];
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = _sameOrder(ids, expected)
          ? 'دُوّر المقطع من الموضع ${start + 1} إلى ${end + 1} بعدد $steps، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر تدوير مقطع الطابور بعدد الخطوات';
      _statusIsError = !_sameOrder(ids, expected);
    });
  }

  /// يعكس ترتيب الطابور الذي يحمل الكرت الظاهر دون تحرير حجزه.
  Future<void> _reverseSelectedHold() async {
    final card = _liveCard;
    if (card == null || _queuedCardIds.length < 2) return;
    final c = AppScope.of(context);
    setState(() => _busy = true);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeHolds);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    final now = c.clock.now();
    final encoded = PromotionRewardTemplate.reverseQueuedCard(
      raw,
      cardId: card.cardId,
      customerId: _holdCustomerId,
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeHolds,
        value: encoded,
        updatedAt: now,
      ),
    );
    var stored = PromotionRewardTemplate.lookupCrossCategoryHold(
      encoded,
      customerId: _holdCustomerId,
    );
    if (stored == null || !stored.holdsCard(card.cardId)) {
      stored = PromotionRewardTemplate.lookupHold(
        encoded,
        card.categoryId,
        customerId: _holdCustomerId,
      );
    }
    await c.auditLogs.append(
      AuditLog(
        id: c.ids.next('reward-probe-hold'),
        entityType: 'promotion_reward_template',
        entityId: card.cardId,
        action: 'reward_probe_card_reversed',
        occurredAt: now,
        payloadJson: '{"customerId":"${_holdCustomerId ?? ''}","queue":${stored?.cards.length ?? 0}}',
      ),
    );
    if (!mounted) return;
    final ids = [for (final item in stored?.cards ?? const <RewardProbeHeldCard>[]) item.cardId];
    final previous = List<String>.from(_queuedCardIds);
    final reversed = previous.reversed.toList();
    setState(() {
      _busy = false;
      _holdReservationId = stored?.cardFor(card.cardId)?.reservationId ?? _holdReservationId;
      _holdQueueCount = stored?.cards.length ?? _holdQueueCount;
      _queuedCardIds = ids;
      _status = ids.length == previous.length && _sameOrder(ids, reversed)
          ? 'عُكس ترتيب الطابور، وبقي ${_holdQueueCount} في الطابور'
          : 'تعذر عكس ترتيب الطابور';
      _statusIsError = !(ids.length == previous.length && _sameOrder(ids, reversed));
    });
  }

  bool _sameOrder(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }

  bool get _perOffer => widget.promotionId != null && widget.promotionId!.isNotEmpty;

  bool get _perCustomer =>
      _perOffer && widget.customerId != null && widget.customerId!.isNotEmpty;

  bool get _perCustomerGlobal =>
      !_perOffer && widget.customerId != null && widget.customerId!.isNotEmpty;

  String? get _holdCustomerId {
    final id = widget.customerId?.trim() ?? '';
    return id.isEmpty ? null : id;
  }

  Duration get _holdDuration => _holdCustomerId == null
      ? PromotionRewardTemplate.sharedCrossCategoryHoldDuration
      : PromotionRewardTemplate.customerCrossCategoryHoldDuration;

  String get _holdStatus {
    if (_holdQueueCount > 1) {
      return _holdCustomerId == null
          ? 'طابور الصرف عبر الفئات: $_holdQueueCount كروت لمدة 7 أيام، بلا خصم حتى يُصرف كرت الفئة المطابقة'
          : 'طابور هذا العميل عبر الفئات: $_holdQueueCount كروت لمدة 7 أيام، بلا خصم حتى يُصرف كرت الفئة المطابقة';
    }
    return _holdCustomerId == null
        ? 'الكرت المختار محجوز للصرف التالي لمدة 7 أيام، بلا خصم حتى يُصرف'
        : 'الكرت المختار محجوز لصرف هذا العميل لمدة 7 أيام، بلا خصم حتى يُصرف';
  }

  PromotionRewardResolution get _resolution {
    final draft = _draft.trim();
    final editingCustomer = _perCustomer;
    final editingCustomerGlobal = _perCustomerGlobal;
    final editingOffer = _perOffer && !editingCustomer;
    final editingGlobal =
        !editingOffer && !editingCustomer && !editingCustomerGlobal;
    String? layer(bool editing, String? stored) =>
        editing ? (draft.isEmpty ? null : draft) : stored;
    return PromotionRewardTemplate.resolveLayer(
      perCustomer: layer(editingCustomer, _storedCustomer),
      perOffer: layer(editingOffer, _storedOffer),
      perCustomerGlobal: layer(editingCustomerGlobal, _storedCustomerGlobal),
      global: layer(editingGlobal, _storedGlobal),
      fallback: _fallback,
    );
  }

  Future<void> _load() async {
    final c = AppScope.of(context);
    final global = await c.settings.find(SettingKeys.promotionRewardSmsTemplate);
    final stored = global is Success<AppSetting?> ? global.value?.value : null;
    _storedGlobal = stored;
    var text = PromotionRewardTemplate.normalize(stored, fallback: _fallback);
    final offerMap = await c.settings.find(SettingKeys.promotionRewardSmsTemplates);
    final offerRaw = offerMap is Success<AppSetting?> ? offerMap.value?.value : null;
    if (_perOffer) {
      final specific = PromotionRewardTemplate.lookup(offerRaw, widget.promotionId!);
      _storedOffer = specific;
      if (specific != null) text = specific;
    }
    final customerMap = await c.settings.find(
      SettingKeys.promotionRewardCustomerSmsTemplates,
    );
    final customerRaw =
        customerMap is Success<AppSetting?> ? customerMap.value?.value : null;
    if (_perCustomer) {
      final specific = PromotionRewardTemplate.lookupCustomer(
        customerRaw,
        widget.promotionId!,
        widget.customerId!,
      );
      _storedCustomer = specific;
      if (specific != null) text = specific;
    }
    final customerGlobalMap = await c.settings.find(
      SettingKeys.promotionRewardCustomerGlobalSmsTemplates,
    );
    final customerGlobalRaw = customerGlobalMap is Success<AppSetting?>
        ? customerGlobalMap.value?.value
        : null;
    if (_perCustomerGlobal || _perCustomer) {
      _storedCustomerGlobal = PromotionRewardTemplate.lookupGlobalCustomer(
        customerGlobalRaw,
        widget.customerId!,
      );
    }
    if (_perCustomerGlobal && _storedCustomerGlobal != null) {
      text = _storedCustomerGlobal!;
    }
    _body.removeListener(_onTyped);
    _body.text = text;
    _body.addListener(_onTyped);
    final probes = await c.settings.find(SettingKeys.promotionRewardProbeReceipts);
    final probeRaw = probes is Success<AppSetting?> ? probes.value?.value : null;
    final receipt = PromotionRewardTemplate.lookupProbe(probeRaw, _scope);
    if (!mounted) return;
    setState(() {
      _draft = text;
      _dirty = false;
      _loading = false;
      _probeReceipt = receipt;
      if (receipt != null) {
        _status = receipt.labelFor(_currentProbeBody());
        _statusIsError = receipt.isError || !receipt.matchesBody(_currentProbeBody());
      }
    });
    if (receipt != null && receipt.state == 'sent' && receipt.requestId != null) {
      _listenForProbeDelivery();
    }
  }

  String get _scope => PromotionRewardTemplate.probeScope(
        promotionId: widget.promotionId,
        customerId: widget.customerId,
      );

  Future<void> _persistProbe(RewardProbeReceipt receipt) async {
    final c = AppScope.of(context);
    final current = await c.settings.find(SettingKeys.promotionRewardProbeReceipts);
    final raw = current is Success<AppSetting?> ? current.value?.value : null;
    await c.settings.save(
      AppSetting(
        key: SettingKeys.promotionRewardProbeReceipts,
        value: PromotionRewardTemplate.rememberProbe(raw, receipt),
        updatedAt: c.clock.now(),
      ),
    );
    _probeReceipt = receipt;
  }

  Future<void> _save() async {
    final c = AppScope.of(context);
    late final AppSetting setting;
    if (_perCustomer) {
      final map = await c.settings.find(
        SettingKeys.promotionRewardCustomerSmsTemplates,
      );
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      setting = AppSetting(
        key: SettingKeys.promotionRewardCustomerSmsTemplates,
        value: PromotionRewardTemplate.encodeCustomerMap(
          raw,
          promotionId: widget.promotionId!,
          customerId: widget.customerId!,
          body: _draft.trim(),
        ),
        updatedAt: c.clock.now(),
      );
    } else if (_perCustomerGlobal) {
      final map = await c.settings.find(
        SettingKeys.promotionRewardCustomerGlobalSmsTemplates,
      );
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      setting = AppSetting(
        key: SettingKeys.promotionRewardCustomerGlobalSmsTemplates,
        value: PromotionRewardTemplate.encodeGlobalCustomerMap(
          raw,
          customerId: widget.customerId!,
          body: _draft.trim(),
        ),
        updatedAt: c.clock.now(),
      );
    } else if (_perOffer) {
      final map = await c.settings.find(SettingKeys.promotionRewardSmsTemplates);
      final raw = map is Success<AppSetting?> ? map.value?.value : null;
      setting = AppSetting(
        key: SettingKeys.promotionRewardSmsTemplates,
        value: PromotionRewardTemplate.encodeMap(
          raw,
          promotionId: widget.promotionId!,
          body: _draft.trim(),
        ),
        updatedAt: c.clock.now(),
      );
    } else {
      setting = AppSetting(
        key: SettingKeys.promotionRewardSmsTemplate,
        value: PromotionRewardTemplate.normalize(_draft, fallback: _fallback),
        updatedAt: c.clock.now(),
      );
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await c.settings.save(
      setting,
    );
    if (!mounted) return;
    if (result is Failure) {
      setState(() {
        _busy = false;
        _status = result.error.message;
        _statusIsError = true;
      });
      return;
    }
    Navigator.pop(context, true);
  }

  Future<void> _sendProbe() async {
    final destination = PromotionRewardTemplate.probeDestination(_phone.text);
    if (destination is Failure<String>) {
      setState(() {
        _status = destination.error.message;
        _statusIsError = true;
      });
      return;
    }
    final body = PromotionRewardTemplate.probeBody(_resolution.template, values: _probeValues);
    if (body is Failure<String>) {
      setState(() {
        _status = body.error.message;
        _statusIsError = true;
      });
      return;
    }
    final phone = (destination as Success<String>).value;
    final text = (body as Success<String>).value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إرسال رسالة تجريبية', style: TextStyle(fontFamily: NetTypography.family)),
        content: Text(
          _useLiveCard
              ? 'ستُرسل المعاينة إلى $phone بقيم كرت متاح، مع بادئة توضح أنها ليست صرفاً. لن يُحجز الكرت ولن يُحفظ القالب.'
              : 'ستُرسل المعاينة إلى $phone مع بادئة توضح أنها ليست كرتاً صادراً. لن يُحفظ القالب ولن يُخصم مخزون.',
          style: const TextStyle(fontFamily: NetTypography.family),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _probing = true;
      _status = null;
    });
    final c = AppScope.of(context);
    try {
      final receipt = await c.smsBridge.sendSms(to: phone, body: text);
      if (!mounted) return;
      if (!receipt.sent) {
        setState(() {
          _probing = false;
          _status = 'تعذر تسليم الرسالة للشبكة';
          _statusIsError = true;
        });
        return;
      }
      await c.auditLogs.append(
        AuditLog(
          id: c.ids.next('reward-probe'),
          entityType: 'promotion_reward_template',
          entityId: widget.promotionId ?? widget.customerId ?? 'global',
          action: 'reward_sms_probe_sent',
          occurredAt: c.clock.now(),
          payloadJson: '{"to":"$phone","layer":"${_resolution.source.name}"}',
        ),
      );
      if (!mounted) return;
      final requestId = receipt.requestId;
      final stored = RewardProbeReceipt(
        scope: _scope,
        to: phone,
        requestId: requestId,
        state: requestId == null ? 'untracked' : 'sent',
        body: text,
      );
      await _persistProbe(stored);
      if (!mounted) return;
      setState(() {
        _probing = false;
        _probeReceipt = stored;
        _status = stored.labelFor(text);
        _statusIsError = stored.isError;
      });
      if (requestId != null) _listenForProbeDelivery();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _probing = false;
        _status = 'تعذر الإرسال: $e';
        _statusIsError = true;
      });
    }
  }

  void _listenForProbeDelivery() {
    final c = AppScope.of(context);
    _probeDelivery ??= c.smsBridge.outboundEvents.listen((event) async {
      final applied = PromotionRewardTemplate.applyProbeDelivery(
        current: _probeReceipt,
        eventRequestId: event.requestId,
        delivered: event.delivered,
        resultCode: event.resultCode,
      );
      if (applied is Failure<RewardProbeReceipt>) return;
      final stored = (applied as Success<RewardProbeReceipt>).value;
      await _persistProbe(stored);
      await c.auditLogs.append(
        AuditLog(
          id: c.ids.next('reward-probe-delivery'),
          entityType: 'promotion_reward_template',
          entityId: widget.promotionId ?? widget.customerId ?? 'global',
          action: event.delivered
              ? 'reward_sms_probe_delivered'
              : 'reward_sms_probe_delivery_failed',
          occurredAt: c.clock.now(),
          payloadJson:
              '{"to":"${event.to}","requestId":${event.requestId},"resultCode":${event.resultCode}}',
        ),
      );
      if (!mounted) return;
      setState(() {
        _probeReceipt = stored;
        _status = stored.labelFor(_currentProbeBody());
        _statusIsError = stored.isError || !stored.matchesBody(_currentProbeBody());
      });
    });
  }

  @override
  void dispose() {
    _probeDelivery?.cancel();
    _body.removeListener(_onTyped);
    _body.dispose();
    _phone.dispose();
    _placePosition.dispose();
    _spanSteps.dispose();
    _spanFrom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unknown = PromotionRewardTemplate.unknownPlaceholders(_draft);
    final resolution = _resolution;
    final preview = PromotionRewardTemplate.renderPreview(
      resolution.template,
      values: _probeValues,
    );
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: NetSpacing.screen,
          child: _loading
              ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _perCustomer
                          ? 'قالب العميل: ${widget.customerLabel ?? 'عميل العرض'}'
                          : _perCustomerGlobal
                          ? 'قالب العميل العام: ${widget.customerLabel ?? 'العميل'}'
                          : _perOffer
                          ? 'قالب مكافأة: ${widget.promotionTitle ?? 'هذا العرض'}'
                          : 'قالب رسالة المكافأة',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _perCustomer
                          ? 'يُستخدم لهذا العميل داخل العرض فقط، ويتقدّم على قالب العرض. امسح النص واحفظ للعودة إلى قالب العرض. المتغيرات: {customer_name} {title} {serial} {secret} {code} {amount} {promotion_name} {reward_value}'
                          : _perCustomerGlobal
                          ? 'يُستخدم لكل عروض هذا العميل ما لم يوجد قالب للعرض أو تخصيص داخل العرض. امسح النص واحفظ للعودة إلى قالب العرض أو العام. المتغيرات: {customer_name} {title} {serial} {secret} {code} {amount} {promotion_name} {reward_value}'
                          : _perOffer
                          ? 'يُستخدم لهذا العرض فقط ويتقدّم على قالب العميل العام. امسح النص واحفظ للعودة إلى قالب العميل العام ثم العام. المتغيرات: {title} {serial} {secret} {code} {amount} {promotion_name} {reward_value} {customer_name}'
                          : 'القالب العام لكل العروض التي بلا قالب خاص. المتغيرات: {title} {serial} {secret} {code} {amount} {promotion_name} {reward_value} {customer_name}',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 12),
                    NetSurfaceCard(
                      child: TextField(
                        controller: _body,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'نص الرسالة',
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontFamily: NetTypography.family),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ستُصرف من: ${resolution.sourceLabel}',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      style: const TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      _liveCard == null
                          ? 'قيم المعاينة تجريبية وليست كرتاً حقيقياً.'
                          : _holdNextPayout
                              ? 'الكرت محجوز للصرف التالي لمدة 7 أيام، ولم يُخصم بعد.'
                              : 'قيم الكرت من المخزون المتاح، دون حجز أو خصم.',
                      style: TextStyle(
                        fontFamily: NetTypography.family,
                        fontSize: 11.5,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _useLiveCard,
                      onChanged: _busy || _probing ? null : _toggleLiveCard,
                      title: const Text(
                        'معاينة بكرت متاح',
                        style: TextStyle(fontFamily: NetTypography.family),
                      ),
                      subtitle: Text(
                        _liveCard == null
                            ? 'بدون هذا الخيار تبقى الأرقام تجريبية ولا تُرسل من المخزون'
                            : 'الرقم الظاهر من المخزون، والكرت يبقى متاحاً',
                        style: const TextStyle(fontFamily: NetTypography.family),
                      ),
                    ),
                    if (_useLiveCard && _availableCards.length > 1)
                      DropdownButtonFormField<String>(
                        value: _liveCard?.cardId,
                        decoration: const InputDecoration(
                          labelText: 'الكرت المستخدم في المعاينة',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final card in _availableCards)
                            DropdownMenuItem(
                              value: card.cardId,
                              child: Text(
                                '${card.title} · ${card.serial}',
                                style: const TextStyle(fontFamily: NetTypography.family),
                              ),
                            ),
                        ],
                        onChanged: _busy || _probing ? null : _selectLiveCard,
                      ),
                    if (_useLiveCard && _liveCard != null)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _holdNextPayout,
                        onChanged: _busy || _probing ? null : _toggleHold,
                        title: Text(
                          _holdCustomerId == null
                              ? 'أضف الكرت لطابور الصرف عبر الفئات'
                              : 'أضف الكرت لطابور هذا العميل عبر الفئات',
                          style: const TextStyle(fontFamily: NetTypography.family),
                        ),
                        subtitle: Text(
                          _holdCustomerId == null
                              ? 'كروت فئات مختلفة تبقى في طابور الصرف حتى 32 كرتاً ولمدة 7 أيام. الصرف يأخذ أول كرت ما زال محجوزاً لفئة المكافأة.'
                              : 'كروت فئات مختلفة تبقى في طابور هذا العميل حتى 32 كرتاً ولمدة 7 أيام. الصرف يأخذ أول كرت ما زال محجوزاً لفئة المكافأة.',
                          style: const TextStyle(fontFamily: NetTypography.family),
                        ),
                      ),
                    if (_holdNextPayout && _holdQueueCount > 1 && _queuedCardIds.isNotEmpty && _queuedCardIds.first != _liveCard?.cardId) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _advanceSelectedHold,
                          icon: const Icon(Icons.arrow_upward),
                          label: Text(
                            'تقديم الكرت الظاهر خطوة واحدة (${_queuedCardIds.length})',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _promoteSelectedHold,
                          icon: const Icon(Icons.vertical_align_top),
                          label: Text(
                            'تقديم الكرت الظاهر ليُصرف أولاً (${_queuedCardIds.length})',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                    ],
                    if (_holdNextPayout && _holdQueueCount > 1 && _queuedCardIds.isNotEmpty && _queuedCardIds.last != _liveCard?.cardId) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _delaySelectedHold,
                          icon: const Icon(Icons.arrow_downward),
                          label: Text(
                            'تأخير الكرت الظاهر خطوة واحدة (${_queuedCardIds.length})',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _demoteSelectedHold,
                          icon: const Icon(Icons.vertical_align_bottom),
                          label: Text(
                            'تأخير الكرت الظاهر ليُصرف آخراً (${_queuedCardIds.length})',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: Text(
                            'عكس ترتيب الطابور (${_queuedCardIds.length})',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: TextField(
                              controller: _placePosition,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'موضع',
                                hintText: '1',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _busy || _probing ? null : _placeSelectedHold,
                              icon: const Icon(Icons.format_list_numbered),
                              label: Text(
                                'نقل الكرت الظاهر إلى الموضع',
                                style: const TextStyle(fontFamily: NetTypography.family),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapSelectedHold,
                          icon: const Icon(Icons.swap_horiz),
                          label: Text(
                            'تبديل الكرت الظاهر مع الموضع',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateSelectedHold,
                          icon: const Icon(Icons.rotate_left),
                          label: Text(
                            'تدوير الطابور بعدد الخطوات',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseSpanSelectedHold,
                          icon: const Icon(Icons.unfold_more),
                          label: Text(
                            'عكس المقطع حتى الموضع',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateSpanSelectedHold,
                          icon: const Icon(Icons.rotate_right),
                          label: Text(
                            'تدوير المقطع خطوة حتى الموضع',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: TextField(
                              controller: _spanSteps,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'خطوات',
                                hintText: '1',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _busy || _probing ? null : _rotateSpanStepsSelectedHold,
                              icon: const Icon(Icons.rotate_90_degrees_ccw),
                              label: const Text(
                                'تدوير المقطع بعدد خطوات حتى الموضع',
                                style: TextStyle(fontFamily: NetTypography.family),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          SizedBox(
                            width: 88,
                            child: TextField(
                              controller: _spanFrom,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                labelText: 'من',
                                hintText: '1',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextButton.icon(
                              onPressed: _busy || _probing ? null : _rotateOpenSpanStepsSelectedHold,
                              icon: const Icon(Icons.swap_horiz),
                              label: const Text(
                                'تدوير مقطع بين موضعين بعدد الخطوات',
                                style: TextStyle(fontFamily: NetTypography.family),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseOpenSpanSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text(
                            'عكس مقطع بين موضعين',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapOpenSpanSelectedHold,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text(
                            'تبديل طرفي مقطع بين موضعين',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseOpenSpanInteriorSelectedHold,
                          icon: const Icon(Icons.unfold_more),
                          label: const Text(
                            'عكس داخل المقطع دون تحريك الطرفين',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateOpenSpanInteriorStepsSelectedHold,
                          icon: const Icon(Icons.rotate_left),
                          label: const Text(
                            'تدوير داخل المقطع دون تحريك الطرفين',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _advanceOpenSpanInteriorSelectedHold,
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text(
                            'تقديم الكرت الظاهر خطوة داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _delayOpenSpanInteriorSelectedHold,
                          icon: const Icon(Icons.arrow_downward),
                          label: const Text(
                            'تأخير الكرت الظاهر خطوة داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _delayOpenSpanInteriorStepsSelectedHold,
                          icon: const Icon(Icons.keyboard_double_arrow_down),
                          label: const Text(
                            'تأخير الكرت الظاهر بعدد خطوات داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _advanceOpenSpanInteriorStepsSelectedHold,
                          icon: const Icon(Icons.keyboard_double_arrow_up),
                          label: const Text(
                            'تقديم الكرت الظاهر بعدد خطوات داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapOpenSpanInteriorStepsSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text(
                            'تبديل الكرت الظاهر مع كرت بعدد خطوات داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapOpenSpanInteriorStepsBackSelectedHold,
                          icon: const Icon(Icons.swap_vert_circle_outlined),
                          label: const Text(
                            'تبديل الكرت الظاهر مع كرت بعدد خطوات نحو الطرف الأدنى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapOpenSpanInteriorNeighborStepsBackSelectedHold,
                          icon: const Icon(Icons.swap_horizontal_circle_outlined),
                          label: const Text(
                            'تبديل كرت أدنى بعدد خطوات مع الكرت الذي قبله داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapOpenSpanInteriorNeighborStepsSelectedHold,
                          icon: const Icon(Icons.swap_horizontal_circle),
                          label: const Text(
                            'تبديل كرت أعلى بعدد خطوات مع الكرت الذي بعده داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _swapOpenSpanInteriorMirrorStepsSelectedHold,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text(
                            'تبديل الكرتين المقابلتين بعدد خطوات حول الكرت الظاهر داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateOpenSpanInteriorMirrorStepsSelectedHold,
                          icon: const Icon(Icons.rotate_right),
                          label: const Text(
                            'تدوير الكرت الظاهر مع الكرتين المقابلتين خطوة نحو الأعلى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateOpenSpanInteriorMirrorCountStepsSelectedHold,
                          icon: const Icon(Icons.rotate_right),
                          label: const Text(
                            'تدوير الكرت الظاهر مع الكرتين المقابلتين بعدد خطوات نحو الأعلى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateOpenSpanInteriorMirrorStepsBackSelectedHold,
                          icon: const Icon(Icons.rotate_left),
                          label: const Text(
                            'تدوير الكرت الظاهر مع الكرتين المقابلتين خطوة نحو الأدنى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _rotateOpenSpanInteriorMirrorCountStepsBackSelectedHold,
                          icon: const Icon(Icons.rotate_left),
                          label: const Text(
                            'تدوير الكرت الظاهر مع الكرتين المقابلتين بعدد خطوات نحو الأدنى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _shiftOpenSpanInteriorMirrorGapStepsSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text(
                            'إزاحة الكروت بين الكرتين المقابلتين خطوة نحو الأعلى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _shiftOpenSpanInteriorMirrorGapCountStepsSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text(
                            'إزاحة الكروت بين الكرتين المقابلتين بعدد خطوات نحو الأعلى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _shiftOpenSpanInteriorMirrorGapCountStepsBackSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text(
                            'إزاحة الكروت بين الكرتين المقابلتين بعدد خطوات نحو الأدنى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseOpenSpanInteriorMirrorGapSelectedHold,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text(
                            'عكس الكروت بين الكرتين المقابلتين والكرت الظاهر داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseOpenSpanInteriorMirrorEdgeGapSelectedHold,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text(
                            'عكس الكروت بين الكرتين المقابلتين وطرفي المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _reverseOpenSpanInteriorMirrorBothGapsSelectedHold,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text(
                            'عكس الكروت بين الكرتين المقابلتين والكرت الظاهر وطرفي المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _shiftOpenSpanInteriorMirrorGapStepsBackSelectedHold,
                          icon: const Icon(Icons.swap_vert),
                          label: const Text(
                            'إزاحة الكروت بين الكرتين المقابلتين خطوة نحو الأدنى داخل المقطع',
                            style: TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),

                    ],
                    if (_holdNextPayout && _holdQueueCount > 0) ...[
                      const SizedBox(height: 4),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: TextButton.icon(
                          onPressed: _busy || _probing ? null : _dropSelectedHold,
                          icon: const Icon(Icons.remove_circle_outline),
                          label: Text(
                            _holdQueueCount > 1
                                ? 'إخراج الكرت الظاهر وإبقاء ${_holdQueueCount - 1}'
                                : 'إخراج الكرت الظاهر من الطابور',
                            style: const TextStyle(fontFamily: NetTypography.family),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'رقم الرسالة التجريبية',
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontFamily: NetTypography.family),
                    ),
                    if (unknown.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'متغيرات غير معروفة وستُرسل كما هي: ${unknown.map((e) => '{$e}').join(' ')}',
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                    if (_status != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _status!,
                        style: TextStyle(
                          fontFamily: NetTypography.family,
                          color: _statusIsError
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || _probing ? null : _sendProbe,
                      icon: _probing
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.sms_outlined),
                      label: const Text('إرسال الرسالة التجريبية', style: TextStyle(fontFamily: NetTypography.family)),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _busy || !_dirty ? null : _save,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('حفظ القالب', style: TextStyle(fontFamily: NetTypography.family)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
