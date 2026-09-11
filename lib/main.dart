import 'package:flutter/material.dart';

import 'application/app_container.dart';
import 'domain/entities/message.dart';
import 'ui/app_scope.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const defaultTemplates = [
    TransferTemplate(
      id: 'tpl-default',
      name: 'تحويل افتراضي',
      pattern: 'تم تحويل {amount} ريال الى {phone} برقم العملية {ref}',
      isActive: true,
    ),
  ];

  final container = await AppContainer.bootstrap(templates: defaultTemplates);
  container.startBackgroundHandlers();

  runApp(NetApp(container: container));
}

class NetApp extends StatefulWidget {
  const NetApp({super.key, required this.container});

  final AppContainer container;

  @override
  State<NetApp> createState() => _NetAppState();
}

class _NetAppState extends State<NetApp> {
  @override
  void dispose() {
    widget.container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      container: widget.container,
      child: MaterialApp(
        title: 'NET',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0B5FFF),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const HomeShell(),
      ),
    );
  }
}
