import 'package:flutter/widgets.dart';

import 'screen_open_trace.dart';

/// يعلّم أول إطار بعد تركيب الصفحة المدفوعة، دون تغيير محتوى الشاشة.
class ScreenOpenProbe extends StatefulWidget {
  const ScreenOpenProbe({super.key, required this.handle, required this.child});

  final ScreenOpenHandle handle;
  final Widget child;

  @override
  State<ScreenOpenProbe> createState() => _ScreenOpenProbeState();
}

class _ScreenOpenProbeState extends State<ScreenOpenProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.handle.markFirstFrame();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
