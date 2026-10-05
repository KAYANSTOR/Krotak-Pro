import 'dart:async';

import 'package:flutter/material.dart' hide Card;

import '../../core/result.dart';
import '../../domain/entities/audit.dart';
import '../../domain/entities/card.dart';
import '../../domain/entities/setting.dart';
import '../../domain/services/local_promotion_fulfillment_service.dart';
import '../../domain/services/promotion_reward_template.dart';
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
                          onPressed: _busy || _probing ? null : _promoteSelectedHold,
                          icon: const Icon(Icons.vertical_align_top),
                          label: Text(
                            'تقديم الكرت الظاهر ليُصرف أولاً (${_queuedCardIds.length})',
                            style: const TextStyle(fontFamily: NetTypography.family),
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
