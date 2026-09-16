import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/device_verification_gate.dart';
import '../../../domain/services/local_device_verification_service.dart';
import '../../app_scope.dart';
import '../../theme/kayan_palette.dart';
import '../../widgets/async_views.dart';
import '../../widgets/settings/settings_section_header.dart';

class DeviceVerificationScreen extends StatefulWidget {
  const DeviceVerificationScreen({super.key});

  @override
  State<DeviceVerificationScreen> createState() => _DeviceVerificationScreenState();
}

class _DeviceVerificationScreenState extends State<DeviceVerificationScreen> {
  bool _loading = true;
  String? _error;
  DeviceVerificationSnapshot _snapshot = const DeviceVerificationSnapshot(statuses: {});

  LocalDeviceVerificationService _service() {
    final c = AppScope.of(context);
    return LocalDeviceVerificationService(settings: c.settings, clock: c.clock);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _service().load();
    if (!mounted) return;
    if (result is Failure<DeviceVerificationSnapshot>) {
      setState(() {
        _loading = false;
        _error = result.error.message;
      });
      return;
    }
    setState(() {
      _loading = false;
      _snapshot = (result as Success<DeviceVerificationSnapshot>).value;
    });
  }

  Future<void> _set(String id, DeviceVerificationStatus status) async {
    String? note;
    if (status == DeviceVerificationStatus.passed &&
        DeviceVerificationCatalog.measurementGateIds.contains(id)) {
      note = await _askNote(id);
      if (!mounted) return;
      if (note == null || note.trim().isEmpty) return;
    }
    final result = await _service().mark(gateId: id, status: status, note: note);
    if (!mounted) return;
    if (result is Success<DeviceVerificationSnapshot>) {
      setState(() => _snapshot = result.value);
    }
  }

  Future<String?> _askNote(String id) async {
    final controller = TextEditingController();
    final title = id == 'bulk_import' ? 'قياس الاستيراد' : 'قياس البث';
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title, style: const TextStyle(fontFamily: 'Tajawal')),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'مثال: 80 صف مقبول في 1.4 ثانية / 11 رسالة في 9 ثوان',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: palette.appBackground,
        appBar: AppBar(
          title: const Text('تحقق الجهاز', style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          backgroundColor: palette.appBackground,
          foregroundColor: palette.textPrimary,
          elevation: 0,
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Text(
                        'بوابات الإنتاج الصفراء — ${_snapshot.passedCount}/${_snapshot.total} مؤكدة على جهاز حقيقي',
                        style: TextStyle(fontFamily: 'Tajawal', fontSize: 14, color: palette.textSecondary),
                      ),
                      const SettingsSectionHeader(title: 'البوابات'),
                      for (final item in DeviceVerificationCatalog.items)
                        _GateCard(
                          item: item,
                          status: _snapshot.of(item.id),
                          evidence: _snapshot.evidenceOf(item.id),
                          onPassed: () => _set(item.id, DeviceVerificationStatus.passed),
                          onBlocked: () => _set(item.id, DeviceVerificationStatus.blocked),
                          onReset: () => _set(item.id, DeviceVerificationStatus.pending),
                        ),
                    ],
                  ),
      ),
    );
  }
}

class _GateCard extends StatelessWidget {
  const _GateCard({
    required this.item,
    required this.status,
    required this.evidence,
    required this.onPassed,
    required this.onBlocked,
    required this.onReset,
  });

  final DeviceVerificationItem item;
  final DeviceVerificationStatus status;
  final DeviceGateEvidence evidence;
  final VoidCallback onPassed;
  final VoidCallback onBlocked;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final label = switch (status) {
      DeviceVerificationStatus.passed => 'مؤكد',
      DeviceVerificationStatus.blocked => 'موقوف',
      DeviceVerificationStatus.pending => 'بانتظار الجهاز',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: palette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: TextStyle(
                        fontFamily: 'Tajawal',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  Text(label, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textSecondary)),
                ],
              ),
              const SizedBox(height: 6),
              Text(item.detail, style: TextStyle(fontFamily: 'Tajawal', fontSize: 13, color: palette.textSecondary)),
              const SizedBox(height: 4),
              Text(item.phaseRef, style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textTertiary)),
              if (evidence.hasOperatorNote) ...[
                const SizedBox(height: 6),
                Text(
                  evidence.note!,
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 12, color: palette.textPrimary),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: onPassed, child: const Text('تم على الجهاز')),
                  TextButton(onPressed: onBlocked, child: const Text('موقوف')),
                  TextButton(onPressed: onReset, child: const Text('إعادة')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
