import 'package:flutter_test/flutter_test.dart';
import 'package:net_app/ui/perf/screen_open_trace.dart';

void main() {
  test('يسجّل أول إطار واكتمال البيانات ويبقي الحد', () {
    var tick = DateTime(2026, 10, 9, 12);
    final trace = ScreenOpenTrace(
      maxSamples: 2,
      clock: () => tick,
    );

    final first = trace.start('dashboard', kind: 'tab');
    tick = tick.add(const Duration(milliseconds: 16));
    first.markFirstFrame(tick);
    tick = tick.add(const Duration(milliseconds: 40));
    first.markDataReady(tick);

    tick = tick.add(const Duration(milliseconds: 1));
    trace.start('reports', kind: 'tab');
    tick = tick.add(const Duration(milliseconds: 1));
    trace.start('offers', kind: 'tab');

    expect(trace.samples, hasLength(2));
    expect(trace.samples.first.screenId, 'reports');
    expect(trace.samples.last.screenId, 'offers');

    final again = ScreenOpenTrace(clock: () => DateTime(2026, 10, 9));
    again.start('customers', kind: 'route');
    again.markLatestDataReady(
      'customers',
      DateTime(2026, 10, 9).add(const Duration(milliseconds: 25)),
    );
    expect(again.samples.single.dataReady, const Duration(milliseconds: 25));
    again.markLatestDataReady(
      'customers',
      DateTime(2026, 10, 9).add(const Duration(milliseconds: 90)),
    );
    expect(again.samples.single.dataReady, const Duration(milliseconds: 25));
  });

  test('ورقة المخزون تُعلَّم مرة واحدة ولا تُمسح بإعادة التحميل', () {
    final opened = DateTime(2026, 10, 9, 13);
    final trace = ScreenOpenTrace(clock: () => opened);
    final handle = trace.beginSheet(ScreenOpenIds.cardStockSheet);
    expect(handle.sample.kind, 'sheet');
    expect(handle.sample.screenId, ScreenOpenIds.cardStockSheet);
    trace.markLatestFirstFrame(
      ScreenOpenIds.cardStockSheet,
      opened.add(const Duration(milliseconds: 12)),
    );
    trace.markLatestFirstFrame(
      ScreenOpenIds.cardStockSheet,
      opened.add(const Duration(milliseconds: 40)),
    );
    trace.markLatestDataReady(
      ScreenOpenIds.cardStockSheet,
      opened.add(const Duration(milliseconds: 30)),
    );
    trace.markLatestDataReady(
      ScreenOpenIds.cardStockSheet,
      opened.add(const Duration(milliseconds: 80)),
    );
    expect(trace.samples.single.firstFrame, const Duration(milliseconds: 12));
    expect(trace.samples.single.dataReady, const Duration(milliseconds: 30));
  });
}
