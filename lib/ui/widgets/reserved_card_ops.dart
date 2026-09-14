import 'package:flutter/material.dart';

import '../../core/result.dart';
import '../../domain/entities/card.dart' as domain;
import '../../domain/entities/customer.dart';
import '../app_scope.dart';

/// تدخل يدوي على كرت محجوز: تأكيد تسليم أو إلغاء حجز + Rollback.
Future<void> showReservedCardOps({
  required BuildContext context,
  required domain.Card card,
  required domain.CardCategory category,
  required Future<void> Function() onDone,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              'كرت محجوز · ${card.serialNumber}',
              style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
            ),
            subtitle: Text(category.name, style: const TextStyle(fontFamily: 'Tajawal')),
          ),
          ListTile(
            leading: const Icon(Icons.check_circle_outline, color: Color(0xFF059669)),
            title: const Text('تأكيد التسليم يدويًا', style: TextStyle(fontFamily: 'Tajawal')),
            subtitle: const Text(
              'تسجيل الكرت كمباع بعد تسليمه خارج SMS',
              style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              await _confirmDelivery(context, card, onDone);
            },
          ),
          ListTile(
            leading: const Icon(Icons.undo, color: Color(0xFFDC2626)),
            title: const Text('إلغاء الحجز وإعادة للمخزون', style: TextStyle(fontFamily: 'Tajawal')),
            subtitle: const Text(
              'تحرير الكرت مع إمكانية إرجاع المبلغ للعميل',
              style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
            ),
            onTap: () async {
              Navigator.pop(ctx);
              await _releaseReserved(context, card, category, onDone);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDelivery(
  BuildContext context,
  domain.Card card,
  Future<void> Function() onDone,
) async {
  final c = AppScope.of(context);
  final saleId = c.ids.next('sale');
  final r = await c.voucherOps.confirmManualDelivery(
    cardId: card.id,
    saleId: saleId,
    note: 'manual_ui',
  );
  if (!context.mounted) return;
  if (r is Failure) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
    );
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('تم تأكيد التسليم', style: TextStyle(fontFamily: 'Tajawal'))),
  );
  await onDone();
}

Future<void> _releaseReserved(
  BuildContext context,
  domain.Card card,
  domain.CardCategory category,
  Future<void> Function() onDone,
) async {
  final phoneCtrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('إلغاء الحجز', style: TextStyle(fontFamily: 'Tajawal')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'أدخل جوال العميل لإرجاع المبلغ (اختياري — فارغ = تحرير مخزون فقط).',
              style: TextStyle(fontFamily: 'Tajawal', fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'جوال العميل',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'Tajawal'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنفيذ', style: TextStyle(fontFamily: 'Tajawal')),
          ),
        ],
      ),
    ),
  );
  final phone = phoneCtrl.text.trim();
  phoneCtrl.dispose();
  if (ok != true || !context.mounted) return;

  final c = AppScope.of(context);
  final rid = card.reservation.reservationId;

  if (phone.isEmpty) {
    if (rid != null) {
      final r = await c.inventoryService.releaseReservation(
        cardId: card.id,
        reservationId: rid,
      );
      if (!context.mounted) return;
      if (r is Failure) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
        );
        return;
      }
    }
  } else {
    final found = await c.customers.findByIdentifier(phone);
    if (!context.mounted) return;
    if (found is! Success<Customer?> || found.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لم يُعثر على عميل بهذا الرقم', style: TextStyle(fontFamily: 'Tajawal')),
        ),
      );
      return;
    }
    final customer = found.value!;
    final r = await c.voucherOps.releaseReservationAndRollback(
      cardId: card.id,
      customerId: customer.id,
      amount: category.faceValue,
      reservationId: rid,
      reason: 'manual_release_ui',
    );
    if (!context.mounted) return;
    if (r is Failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error.message, style: const TextStyle(fontFamily: 'Tajawal'))),
      );
      return;
    }
  }

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('تم تحرير الكرت', style: TextStyle(fontFamily: 'Tajawal'))),
  );
  await onDone();
}
