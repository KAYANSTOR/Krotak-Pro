import 'package:flutter/material.dart';

import '../../../core/result.dart';
import '../../../domain/entities/setting.dart';
import '../../app_scope.dart';
import '../../widgets/async_views.dart';

/// إعدادات شرائح الاتصال المزدوجة + Auto-Failover — مطابق فيديو Z Net.
class SimSettingsScreen extends StatefulWidget {
  const SimSettingsScreen({super.key});

  @override
  State<SimSettingsScreen> createState() => _SimSettingsScreenState();
}

class _SimSettingsScreenState extends State<SimSettingsScreen> {
  bool _loading = true;
  String? _error;
  String _readSlot = SettingDefaults.preferredSimSlot;
  String _sendSlot = SettingDefaults.preferredSendSimSlot;
  bool _listen = true;
  bool _failover = SettingDefaults.simAutoFailover;
  bool _saving = false;

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
    final c = AppScope.of(context);
    Future<String?> read(String key) async {
      final r = await c.settings.find(key);
      return r is Success<AppSetting?> ? r.value?.value : null;
    }

    try {
      final readSlot = await read(SettingKeys.preferredSimSlot);
      final sendSlot = await read(SettingKeys.preferredSendSimSlot);
      final listen = await read(SettingKeys.smsListenEnabled);
      final failover = await read(SettingKeys.simAutoFailover);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _readSlot = (readSlot == null || readSlot.isEmpty)
            ? SettingDefaults.preferredSimSlot
            : readSlot;
        _sendSlot = (sendSlot == null || sendSlot.isEmpty)
            ? SettingDefaults.preferredSendSimSlot
            : sendSlot;
        _listen = SettingBool.read(listen, defaultValue: true);
        _failover = SettingBool.read(
          failover,
          defaultValue: SettingDefaults.simAutoFailover,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'تعذر قراءة الإعدادات';
        });
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final c = AppScope.of(context);
    final now = c.clock.now();
    await c.settings.save(
      AppSetting(key: SettingKeys.preferredSimSlot, value: _readSlot, updatedAt: now),
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.preferredSendSimSlot,
        value: _sendSlot,
        updatedAt: now,
      ),
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.smsListenEnabled,
        value: _listen.toString(),
        updatedAt: now,
      ),
    );
    await c.settings.save(
      AppSetting(
        key: SettingKeys.simAutoFailover,
        value: _failover.toString(),
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم حفظ إعدادات الشرائح',
          style: TextStyle(fontFamily: 'Tajawal'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'إعدادات شرائح الاتصال',
            style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFFF8FAFC),
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
        ),
        body: _loading
            ? const AsyncLoadingView()
            : _error != null
                ? AsyncErrorView(message: _error!, onRetry: _load)
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'ضبط شرائح القراءة والإرسال المستقلة',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'يمكنك فصل شريحة استقبال SMS عن شريحة الإرسال. عند تفعيل Auto-Failover ينتقل الإرسال للشريحة البديلة عند الفشل.',
                        style: TextStyle(
                          fontFamily: 'Tajawal',
                          fontSize: 12,
                          height: 1.4,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _readSlot,
                            decoration: const InputDecoration(
                              labelText: 'شريحة القراءة (استقبال SMS)',
                              labelStyle: TextStyle(fontFamily: 'Tajawal'),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '0',
                                child: Text('SIM 1', style: TextStyle(fontFamily: 'Tajawal')),
                              ),
                              DropdownMenuItem(
                                value: '1',
                                child: Text('SIM 2', style: TextStyle(fontFamily: 'Tajawal')),
                              ),
                            ],
                            onChanged: (v) => setState(() => _readSlot = v ?? '0'),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _sendSlot,
                            decoration: const InputDecoration(
                              labelText: 'شريحة الإرسال',
                              labelStyle: TextStyle(fontFamily: 'Tajawal'),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '0',
                                child: Text('SIM 1', style: TextStyle(fontFamily: 'Tajawal')),
                              ),
                              DropdownMenuItem(
                                value: '1',
                                child: Text('SIM 2', style: TextStyle(fontFamily: 'Tajawal')),
                              ),
                            ],
                            onChanged: (v) => setState(() => _sendSlot = v ?? '0'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _card(
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'استماع لرسائل SMS',
                              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'تفعيل استقبال رسائل المحافظ على شريحة القراءة',
                              style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                            ),
                            value: _listen,
                            activeColor: const Color(0xFF0F766E),
                            onChanged: (v) => setState(() => _listen = v),
                          ),
                          const Divider(height: 20),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'التبديل التلقائي عند فشل الإرسال (Auto-Failover)',
                              style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'عند فشل الإرسال من الشريحة الأساسية يُعاد عبر الشريحة الأخرى',
                              style: TextStyle(fontFamily: 'Tajawal', fontSize: 12),
                            ),
                            value: _failover,
                            activeColor: const Color(0xFF0F766E),
                            onChanged: (v) => setState(() => _failover = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0F766E),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'حفظ',
                                style: TextStyle(
                                  fontFamily: 'Tajawal',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
