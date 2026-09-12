import 'package:flutter/material.dart';

import '../widgets/dashboard/direct_sale_sheet.dart';

/// Entry for direct/manual sale — presents the product bottom sheet.
///
/// Prefer [DirectSaleSheet.show] from callers that already have a surface
/// (e.g. Dashboard). This screen exists for deep links / AppRoutes.
class DirectSaleScreen extends StatefulWidget {
  const DirectSaleScreen({super.key});

  @override
  State<DirectSaleScreen> createState() => _DirectSaleScreenState();
}

class _DirectSaleScreenState extends State<DirectSaleScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openSheet());
  }

  Future<void> _openSheet() async {
    final result = await DirectSaleSheet.show(context);
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black54,
      body: SizedBox.expand(),
    );
  }
}
