import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/account_session.dart';
import '../../core/app_brand.dart';
import '../home_shell.dart';
import '../theme/kayan_colors.dart';
import '../theme/net_tokens.dart';
import 'account_auth_screen.dart';
import 'account_blocked_screen.dart';

/// بوابة الحساب: تقرر ما يُعرض بعد شاشة الإقلاع —
/// تسجيل الدخول، أو التطبيق، أو شاشة الإيقاف — وتزامن الحالة مع الإدارة.
class AccountRootScreen extends StatefulWidget {
  const AccountRootScreen({super.key});

  @override
  State<AccountRootScreen> createState() => _AccountRootScreenState();
}

class _AccountRootScreenState extends State<AccountRootScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final session = AccountSession.maybeInstance;
    if (session == null) return;
    session.state.addListener(_handleStateChange);
    unawaited(session.initialize());
  }

  @override
  void dispose() {
    AccountSession.maybeInstance?.state.removeListener(_handleStateChange);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // عند العودة للتطبيق: تُطبَّق فوراً أي حالة إيقاف أو تفعيل من الإدارة.
      unawaited(AccountSession.maybeInstance?.sync());
    }
  }

  /// عند خروج الحساب أو إيقافه نُغلق أي شاشة مفتوحة حتى تظهر البوابة مباشرة.
  void _handleStateChange() {
    final phase = AccountSession.maybeInstance?.state.value.phase;
    if (phase != AccountPhase.blocked && phase != AccountPhase.signedOut) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = AccountSession.maybeInstance;
    if (session == null) {
      // بعض مضيفي الواجهة (مثل اختبارات NetApp) يبنون التطبيق مباشرة
      // من دون استدعاء main()، وبالتالي لا تكون جلسة السحابة مسجلة. في
      // هذه الحالة نحافظ على سلوك التطبيق المحلي القديم بدلاً من عرض
      // مؤشر انتظار دائم. التشغيل الحقيقي يهيئ AccountSession في main().
      return const HomeShell();
    }
    return ValueListenableBuilder<AccountState>(
      valueListenable: session.state,
      builder: (context, state, _) {
        switch (state.phase) {
          case AccountPhase.loading:
            return const _AccountBootView();
          case AccountPhase.unconfigured:
          case AccountPhase.signedOut:
            return const AccountAuthScreen();
          case AccountPhase.blocked:
            return const AccountBlockedScreen();
          case AccountPhase.ready:
            return const HomeShell();
        }
      },
    );
  }
}

/// شاشة انتظار قصيرة أثناء التحقق من الجلسة المحفوظة.
class _AccountBootView extends StatelessWidget {
  const _AccountBootView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              KayanColors.logoGradient1,
              KayanColors.logoGradient2,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(26),
                ),
                padding: const EdgeInsets.all(16),
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.sim_card_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: NetSpacing.lg),
              Text(
                AppBrand.name,
                style: const TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: NetSpacing.lg),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: NetSpacing.md),
              Text(
                'جارٍ التحقق من حساب الشبكة…',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
