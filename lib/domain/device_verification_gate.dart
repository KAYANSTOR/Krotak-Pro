/// Yellow production gates that require a real Android device.
/// Software implementation is already in the repo; this catalog tracks
/// operator confirmation on hardware.
enum DeviceVerificationStatus { pending, passed, blocked }

final class DeviceVerificationItem {
  const DeviceVerificationItem({
    required this.id,
    required this.title,
    required this.detail,
    required this.phaseRef,
  });

  final String id;
  final String title;
  final String detail;
  final String phaseRef;
}

abstract final class DeviceVerificationCatalog {
  static const settingKey = 'device_verification_gates';

  static const items = <DeviceVerificationItem>[
    DeviceVerificationItem(
      id: 'sms_send_receive',
      title: 'استقبال وإرسال SMS',
      detail: 'رسالة واردة حقيقية تُحفظ وتُحلل؛ إرسال كرت يصل للمستلم.',
      phaseRef: 'Phase 3/6 SMS',
    ),
    DeviceVerificationItem(
      id: 'wallet_notifications',
      title: 'إشعارات المحافظ',
      detail: 'Notification Listener يلتقط إشعار محفظة حقيقي ويحوّله لمحرك الدفع.',
      phaseRef: 'Phase 3',
    ),
    DeviceVerificationItem(
      id: 'retry_recovery',
      title: 'إعادة المحاولة والاستعادة',
      detail: 'فشل إرسال ثم استعادة بعد إغلاق التطبيق دون تكرار مالي.',
      phaseRef: 'Phase 4',
    ),
    DeviceVerificationItem(
      id: 'salafni',
      title: 'سلفني على الجهاز',
      detail: 'طلب سلفني عبر SMS، حجز أدنى فئة، ثم تسديد من تحويل لاحق.',
      phaseRef: 'Phase 5',
    ),
    DeviceVerificationItem(
      id: 'pos_settlement',
      title: 'تسوية نقطة البيع',
      detail: 'حوالة بمعرف POS تُسجّل تسوية وتُرسل تأكيدًا.',
      phaseRef: 'Phase 6',
    ),
    DeviceVerificationItem(
      id: 'bulk_import',
      title: 'استيراد دفعة كروت',
      detail: 'ملف حقيقي يُتحقق ثم يُدخل دفعة مع تقرير مرفوض.',
      phaseRef: 'Phase 7',
    ),
    DeviceVerificationItem(
      id: 'broadcast_rate',
      title: 'معدل البث الجماعي',
      detail: 'قياس تأخير الإرسال على جهاز حقيقي وفق سياسة المشغّل.',
      phaseRef: 'Phase 8',
    ),
  ];

  static DeviceVerificationItem? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }
}
