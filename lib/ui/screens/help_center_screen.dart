import 'package:flutter/material.dart';

/// Offline help topics aligned with product areas (no remote content).
class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const _topics = <(String, String)>[
    ('العملاء', 'إنشاء عميل برقم هاتف فريد، البحث بالاسم أو الرقم، والقائمة السوداء تمنع البيع.'),
    ('الرصيد والتحويل', 'الإيداع عبر رسائل SMS المطابقة للقوالب. المرجع المكرر آمن (idempotent).'),
    ('البيع', 'البيع من الرصيد يحجز كرتًا FIFO ثم يخصم الرصيد. فشل الرصيد لا يستهلك كرتًا.'),
    ('الترخيص', 'التفعيل محلي. انتهاء الصلاحية يُقيَّم عند كل قراءة للترخيص.'),
    ('SMS', 'يلزم إذن SMS. الرسائل تُحفظ ثم تُحلل ثم تُعالج؛ الاستعادة تعيد المعلّق.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('مركز المساعدة')),
      body: ListView.separated(
        itemCount: _topics.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final (title, body) = _topics[i];
          return ExpansionTile(
            title: Text(title, style: const TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(body, style: const TextStyle(fontFamily: 'Tajawal')),
              ),
            ],
          );
        },
      ),
    );
  }
}
