import 'package:flutter/material.dart';

import '../widgets/async_views.dart';

/// Offers are Post-v1 — explicit empty product surface, not a wrong screen.
class OffersScreen extends StatelessWidget {
  const OffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AsyncEmptyView(
      icon: Icons.local_offer_outlined,
      message: 'العروض خارج نطاق الشاشات الأساسية الحالية (Post-v1).',
    );
  }
}
