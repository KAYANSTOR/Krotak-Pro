import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

abstract final class AdminContact {
  static const phone = '967773303455';
  static const displayPhone = '+967 773 303 455';

  static Future<void> openWhatsApp(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent('مرحباً، أحتاج إلى التواصل مع إدارة كروتك.')}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب، تأكد من تثبيته على الجهاز')),
      );
    }
  }
}
