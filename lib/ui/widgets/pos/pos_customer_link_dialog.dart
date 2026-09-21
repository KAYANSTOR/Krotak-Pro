import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_semantic_colors.dart';
import '../../theme/net_tokens.dart';

/// تأكيد ربط نقطة بيع بحساب عميل قائم يحمل نفس رقم الجوال.
///
/// لا يوجد دفتر مالي مستقل لنقاط البيع: كل نقطة بيع مرتبطة بحساب عميل في
/// الدفتر (`PosAccount.customerId`). لذلك عندما يكون رقم الجوال مسجّلاً لعميل
/// قائم، فالخيار الوحيد القابل للتنفيذ هو ربط نقطة البيع بنفس الحساب بدل رفض
/// الإنشاء — لكن الحساب يصبح مشتركاً، فيجب أن يكون الربط بموافقة صريحة.
///
/// يرجع `true` فقط عند ضغط المستخدم على «ربط وإنشاء».
Future<bool> confirmLinkPosToCustomer({
  required BuildContext context,
  required String customerName,
  required String phone,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final palette = KayanPalette.of(ctx);
      final net = ctx.netColors;
      final body = TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 13,
        height: 1.5,
        color: palette.textPrimary,
      );
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.link_rounded, size: 20, color: palette.primary),
              const SizedBox(width: NetSpacing.sm),
              const Expanded(
                child: Text(
                  'الرقم مسجّل كعميل',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الرقم ' + phone + ' مسجّل لحساب العميل «' + customerName + '».',
                  style: body,
                ),
                const SizedBox(height: NetSpacing.sm),
                Text(
                  'نقاط البيع في النظام لا تملك دفتراً مالياً مستقلاً؛ كل نقطة بيع '
                  'مرتبطة بحساب عميل في الدفتر. لذلك سيتم ربط نقطة البيع بحساب هذا '
                  'العميل نفسه بدل رفض الإنشاء.',
                  style: body,
                ),
                const SizedBox(height: NetSpacing.md),
                Container(
                  padding: const EdgeInsets.all(NetSpacing.md),
                  decoration: BoxDecoration(
                    color: net.warningContainer,
                    borderRadius: NetRadii.smAll,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 18, color: net.warning),
                      const SizedBox(width: NetSpacing.sm),
                      Expanded(
                        child: Text(
                          'تنبيه محاسبي: سيصبح الحساب مشتركاً — حركات الرصيد '
                          'والتحويلات الواردة على هذا الرقم تُحتسب على نفس الحساب '
                          'وتظهر أيضاً في تقارير نقطة البيع. إن أردت حساباً مستقلاً، '
                          'اضغط «إلغاء» ثم استخدم رقماً آخر لنقطة البيع.',
                          style: TextStyle(
                            fontFamily: NetTypography.family,
                            fontSize: 12,
                            height: 1.5,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(fontFamily: NetTypography.family),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(
                'ربط وإنشاء',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  return confirmed ?? false;
}
