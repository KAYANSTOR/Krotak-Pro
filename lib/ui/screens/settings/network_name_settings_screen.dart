import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';

/// Edit the network display name shown on the Dashboard Header.
///
/// Persists via [SettingsRepository] under [SettingKeys.networkName].
class NetworkNameSettingsScreen extends StatefulWidget {
  const NetworkNameSettingsScreen({super.key});

  @override
  State<NetworkNameSettingsScreen> createState() =>
      _NetworkNameSettingsScreenState();
}

class _NetworkNameSettingsScreenState extends State<NetworkNameSettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.settings.find(SettingKeys.networkName);
    if (!mounted) return;
    if (result is Success<AppSetting?>) {
      final value = result.value?.value.trim();
      _controller.text =
          (value != null && value.isNotEmpty) ? value : SettingDefaults.networkName;
      setState(() => _loading = false);
    } else {
      _controller.text = SettingDefaults.networkName;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل اسم الشبكة';
      });
    }
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'اسم الشبكة مطلوب');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final c = AppScope.of(context);
    final result = await c.settings.save(
      AppSetting(
        key: SettingKeys.networkName,
        value: name,
        updatedAt: c.clock.now(),
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (result is Failure) {
      setState(() => _error = 'تعذر حفظ اسم الشبكة');
      return;
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسم الشبكة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'الاسم الظاهر في أعلى لوحة التحكم بجانب الشعار.',
                  style: TextStyle(fontFamily: 'Tajawal', fontSize: 14),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  enabled: !_saving,
                  maxLength: 48,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'اسم الشبكة',
                    border: OutlineInputBorder(),
                    hintText: SettingDefaults.networkName,
                  ),
                  style: const TextStyle(fontFamily: 'Tajawal'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(
                      fontFamily: 'Tajawal',
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'جاري الحفظ…' : 'حفظ'),
                ),
              ],
            ),
    );
  }
}
