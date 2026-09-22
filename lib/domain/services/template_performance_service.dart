import 'dart:convert';

import '../../core/result.dart';
import '../entities/message.dart';
import '../entities/setting.dart';
import '../repositories/repositories.dart';

/// Persistent per-template match counters (audit §4 item 8).
///
/// Stored as a single settings JSON document so historical devices do not
/// require a Drift schema bump. Counters survive backup/restore with settings.
final class TemplatePerformanceService {
  TemplatePerformanceService({
    required this.settings,
    this.now,
  });

  static const settingKey = 'template_match_stats_v1';
  static const unmatchedId = '__unmatched__';

  final SettingsRepository settings;
  final DateTime Function()? now;

  DateTime _now() => now?.call() ?? DateTime.now().toUtc();

  Future<void> recordMatch(String templateId) async {
    final id = templateId.trim();
    if (id.isEmpty) {
      await recordUnmatched();
      return;
    }
    await _bump(id);
  }

  Future<void> recordUnmatched() => _bump(unmatchedId);

  Future<List<TemplatePerformanceRow>> snapshot(
    List<TransferTemplate> templates,
  ) async {
    final raw = await _load();
    final rows = <TemplatePerformanceRow>[];
    for (final t in templates) {
      final entry = raw[t.id];
      rows.add(
        TemplatePerformanceRow(
          templateId: t.id,
          name: t.name,
          pattern: t.pattern,
          isActive: t.isActive,
          matchCount: entry?.count ?? 0,
          lastMatchedAt: entry?.lastMatchedAt,
          unmatched: false,
        ),
      );
    }
    final unmatched = raw[unmatchedId];
    if (unmatched != null && unmatched.count > 0) {
      rows.add(
        TemplatePerformanceRow(
          templateId: unmatchedId,
          name: 'بلا مطابقة',
          pattern: '',
          isActive: false,
          matchCount: unmatched.count,
          lastMatchedAt: unmatched.lastMatchedAt,
          unmatched: true,
        ),
      );
    }
    rows.sort((a, b) {
      final byCount = b.matchCount.compareTo(a.matchCount);
      if (byCount != 0) return byCount;
      return a.name.compareTo(b.name);
    });
    return rows;
  }

  Future<Map<String, _Stat>> _load() async {
    final found = await settings.find(settingKey);
    if (found is! Success<AppSetting?> || found.value == null) {
      return {};
    }
    try {
      final decoded = jsonDecode(found.value!.value);
      if (decoded is! Map) return {};
      final out = <String, _Stat>{};
      decoded.forEach((key, value) {
        if (key is! String || value is! Map) return;
        final count = value['count'];
        final last = value['lastMatchedAt'];
        out[key] = _Stat(
          count: count is int ? count : int.tryParse('$count') ?? 0,
          lastMatchedAt: last is String ? DateTime.tryParse(last) : null,
        );
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _bump(String id) async {
    final map = await _load();
    final current = map[id];
    map[id] = _Stat(
      count: (current?.count ?? 0) + 1,
      lastMatchedAt: _now(),
    );
    final encoded = jsonEncode({
      for (final e in map.entries)
        e.key: {
          'count': e.value.count,
          'lastMatchedAt': e.value.lastMatchedAt?.toIso8601String(),
        },
    });
    await settings.save(
      AppSetting(key: settingKey, value: encoded, updatedAt: _now()),
    );
  }
}

final class TemplatePerformanceRow {
  const TemplatePerformanceRow({
    required this.templateId,
    required this.name,
    required this.pattern,
    required this.isActive,
    required this.matchCount,
    required this.unmatched,
    this.lastMatchedAt,
  });

  final String templateId;
  final String name;
  final String pattern;
  final bool isActive;
  final int matchCount;
  final bool unmatched;
  final DateTime? lastMatchedAt;
}

final class _Stat {
  const _Stat({required this.count, this.lastMatchedAt});
  final int count;
  final DateTime? lastMatchedAt;
}
