import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/account_session.dart';
import '../../core/app_brand.dart';
import '../../core/cloud_config.dart';
import '../../core/contact_admin.dart';
import '../../data/cloud/cloud_http.dart';
import '../../domain/services/cloud_account_service.dart';
import '../theme/kayan_colors.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/net/net_surface_card.dart';

enum _AuthMode { register, login }

/// شاشة حساب الشبكة: إنشاء حساب دائم أو الدخول بحساب قائم.
///
/// بنفس هوية التطبيق: تدرّج العلامة، خط Tajawal، البطاقات والحواف الموحّدة،
/// ودعم الوضعين الفاتح والداكن.
class AccountAuthScreen extends StatefulWidget {
  const AccountAuthScreen({super.key});

  @override
  State<AccountAuthScreen> createState() => _AccountAuthScreenState();
}

class _AccountAuthScreenState extends State<AccountAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _networkController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  _AuthMode _mode = _AuthMode.register;
  bool _busy = false;
  bool _obscurePassword = true;
  String _error = '';

  bool get _isRegister => _mode == _AuthMode.register;

  @override
  void dispose() {
    _networkController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _switchMode(_AuthMode mode) {
    if (_mode == mode) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = mode;
      _error = '';
      _confirmController.clear();
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final session = AccountSession.maybeInstance;
    if (session == null) {
      setState(() => _error = 'لم تكتمل تهيئة التطبيق بعد. أعد فتح التطبيق.');
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
    });

    try {
      if (_isRegister) {
        await session.register(
          networkName: _networkController.text.trim(),
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
        );
      } else {
        await session.signIn(
          phone: _phoneController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on CloudHttpException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'تعذر إكمال العملية. تحقق من الاتصال بالإنترنت وأعد المحاولة.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final configured = CloudConfig.isConfigured;

    return Scaffold(
      backgroundColor: palette.appBackground,
      body: ListView(
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _hero(context),
          Transform.translate(
            offset: const Offset(0, -48),
            child: Padding(
              padding: NetSpacing.pageH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _modeSwitch(context),
                  const SizedBox(height: NetSpacing.md),
                  if (!configured)
                    _unconfiguredCard(context)
                  else
                    _formCard(context),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: NetSpacing.md),
                    _errorNotice(context),
                  ],
                  const SizedBox(height: NetSpacing.xl),
                  _footer(context),
                  const SizedBox(height: NetSpacing.lg),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── الترويسة ────────────────────────────────────────────────────────

  Widget _hero(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            KayanColors.logoGradient1,
            KayanColors.logoGradient2,
            KayanColors.logoGradient3,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(NetRadii.sheet)),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -30,
            left: -20,
            child: _blurCircle(120, Colors.white.withValues(alpha: 0.10)),
          ),
          Positioned(
            bottom: 12,
            right: -30,
            child: _blurCircle(150, Colors.white.withValues(alpha: 0.08)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              NetSpacing.xl,
              54,
              NetSpacing.xl,
              104,
            ),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                    boxShadow: NetElevation.glow(KayanColors.primaryVariant, opacity: 0.35),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.sim_card_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
                const SizedBox(height: NetSpacing.lg),
                Text(
                  AppBrand.name,
                  style: const TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: NetSpacing.xs),
                Text(
                  _isRegister
                      ? 'أنشئ حساب شبكتك وابدأ خلال دقيقة'
                      : 'سجّل الدخول لمتابعة شبكتك',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurCircle(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  // ── مبدّل الوضع ─────────────────────────────────────────────────────

  Widget _modeSwitch(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(NetSpacing.xs),
      decoration: BoxDecoration(
        color: palette.surfaceVariant,
        borderRadius: NetRadii.pillAll,
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _segment(
              context,
              label: 'إنشاء حساب',
              selected: _isRegister,
              onTap: () => _switchMode(_AuthMode.register),
            ),
          ),
          Expanded(
            child: _segment(
              context,
              label: 'تسجيل الدخول',
              selected: !_isRegister,
              onTap: () => _switchMode(_AuthMode.login),
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final palette = KayanPalette.of(context);
    return AnimatedContainer(
      duration: NetMotion.scale(context, NetDurations.fast),
      curve: NetMotion.standard,
      decoration: BoxDecoration(
        color: selected ? palette.primary : Colors.transparent,
        borderRadius: NetRadii.pillAll,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: NetRadii.pillAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? palette.onPrimary : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── نموذج التسجيل/الدخول ────────────────────────────────────────────

  Widget _formCard(BuildContext context) {
    final net = context.netColors;
    return NetSurfaceCard(
      radius: NetRadii.lg,
      elevated: true,
      padding: const EdgeInsets.fromLTRB(
        NetSpacing.lg,
        NetSpacing.xl,
        NetSpacing.lg,
        NetSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isRegister ? 'بيانات الشبكة' : 'بيانات الدخول',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: KayanPalette.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: NetSpacing.xs),
            Text(
              _isRegister
                  ? 'اسم الشبكة هو ما يظهر في ترويسة التطبيق وتقاريرك ورسائل عملائك.'
                  : 'استخدم رقم الهاتف وكلمة المرور التي سجّلت بها.',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12.5,
                height: 1.45,
                color: KayanPalette.of(context).textSecondary,
              ),
            ),
            const SizedBox(height: NetSpacing.lg),
            if (_isRegister) ...[
              TextFormField(
                controller: _networkController,
                textInputAction: TextInputAction.next,
                style: _inputStyle(context),
                decoration: _decoration(
                  context,
                  label: 'اسم الشبكة',
                  hint: 'مثال: شبكة النور',
                  icon: Icons.storefront_rounded,
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) return 'اسم الشبكة مطلوب';
                  if (text.length < 2) return 'اسم الشبكة قصير جداً';
                  return null;
                },
              ),
              const SizedBox(height: NetSpacing.md),
            ],
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              textDirection: TextDirection.ltr,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
                LengthLimitingTextInputFormatter(13),
              ],
              style: _inputStyle(context),
              decoration: _decoration(
                context,
                label: 'رقم الهاتف',
                hint: '77xxxxxxx',
                icon: Icons.phone_iphone_rounded,
              ),
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'رقم الهاتف مطلوب';
                if (!CloudAccountService.isValidPhone(text)) {
                  return 'أدخل رقم هاتف صحيح (مثال: 77xxxxxxx)';
                }
                return null;
              },
            ),
            const SizedBox(height: NetSpacing.md),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction:
                  _isRegister ? TextInputAction.next : TextInputAction.done,
              style: _inputStyle(context),
              decoration: _decoration(
                context,
                label: 'كلمة المرور',
                hint: '6 أحرف على الأقل',
                icon: Icons.lock_outline_rounded,
                suffix: IconButton(
                  tooltip: _obscurePassword ? 'إظهار' : 'إخفاء',
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: NetSizes.iconSm,
                    color: KayanPalette.of(context).textTertiary,
                  ),
                ),
              ),
              validator: (value) {
                final text = value ?? '';
                if (text.isEmpty) return 'كلمة المرور مطلوبة';
                if (text.length < 6) return 'كلمة المرور 6 أحرف على الأقل';
                return null;
              },
            ),
            if (_isRegister) ...[
              const SizedBox(height: NetSpacing.md),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                style: _inputStyle(context),
                decoration: _decoration(
                  context,
                  label: 'تأكيد كلمة المرور',
                  hint: 'أعد كتابة كلمة المرور',
                  icon: Icons.lock_reset_rounded,
                ),
                validator: (value) {
                  if (!_isRegister) return null;
                  if ((value ?? '').isEmpty) return 'تأكيد كلمة المرور مطلوب';
                  if (value != _passwordController.text) {
                    return 'كلمتا المرور غير متطابقتين';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: NetSpacing.lg),
            if (_isRegister) ...[
              _trialCard(context, net),
              const SizedBox(height: NetSpacing.lg),
            ],
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isRegister ? 'إنشاء الحساب والبدء' : 'دخول'),
              ),
            ),
            const SizedBox(height: NetSpacing.sm),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _switchMode(
                        _isRegister ? _AuthMode.login : _AuthMode.register,
                      ),
              child: Text(
                _isRegister
                    ? 'لدي حساب بالفعل — تسجيل الدخول'
                    : 'لا أملك حساباً — إنشاء حساب جديد',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => AdminContact.openWhatsApp(context),
              icon: const Icon(Icons.chat_rounded),
              label: Text('التواصل مع الإدارة عبر واتساب\n${AdminContact.displayPhone}', textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trialCard(BuildContext context, NetSemanticColors net) {
    final palette = KayanPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(NetSpacing.md),
      decoration: BoxDecoration(
        color: net.premiumContainer.withValues(alpha: palette.isDark ? 0.55 : 0.85),
        borderRadius: NetRadii.smAll,
        border: Border.all(color: net.premium.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 20, color: net.premium),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'حساب دائم — بدون فترة تجريبية',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: NetSpacing.xxs),
                Text(
                  'يظهر الحساب فوراً في لوحة الإدارة، وتستطيع الإدارة تفعيله أو إيقافه أو إرسال إشعارات إليه.',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 11.5,
                    height: 1.45,
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorNotice(BuildContext context) {
    final net = context.netColors;
    final palette = KayanPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.md,
        vertical: NetSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: net.errorContainer.withValues(alpha: palette.isDark ? 0.55 : 1),
        borderRadius: NetRadii.smAll,
        border: Border.all(color: net.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: NetSizes.iconSm, color: net.error),
          const SizedBox(width: NetSpacing.sm),
          Expanded(
            child: Text(
              _error,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unconfiguredCard(BuildContext context) {
    final palette = KayanPalette.of(context);
    return NetSurfaceCard(
      radius: NetRadii.lg,
      elevated: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: palette.primary, size: NetSizes.iconMd),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  'خدمة الحساب غير مربوطة',
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: NetSpacing.md),
          Text(
            'لتشغيل تسجيل الحسابات وظهورها في لوحة الإدارة، يجب تعبئة بيانات مشروع '
            'Firebase المشترك في ملف الإعداد ثم إعادة بناء التطبيق:',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13,
              height: 1.6,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: NetSpacing.md),
          Container(
            padding: const EdgeInsets.all(NetSpacing.md),
            decoration: BoxDecoration(
              color: palette.surfaceVariant,
              borderRadius: NetRadii.smAll,
              border: Border.all(color: palette.border),
            ),
            child: Text(
              'lib/core/cloud_config.dart\n'
              '  fileApiKey   = «Web API Key»\n'
              '  fileProjectId = «Project ID»',
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 12,
                height: 1.7,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: NetSpacing.md),
          Text(
            'المشروع نفسه المستخدم في لوحة الإدارة — نفس Project ID ونفس قاعدة Firestore.',
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 12,
              height: 1.5,
              color: palette.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    final palette = KayanPalette.of(context);
    return Column(
      children: [
        Text(
          'الإصدار ${AppBrand.version} · ${AppBrand.company}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.textTertiary,
          ),
        ),
        const SizedBox(height: NetSpacing.xxs),
        Text(
          AppBrand.website,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: NetTypography.family,
            fontSize: 11.5,
            color: palette.textTertiary,
          ),
        ),
      ],
    );
  }

  TextStyle _inputStyle(BuildContext context) => TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 14.5,
        fontWeight: FontWeight.w600,
        color: KayanPalette.of(context).textPrimary,
      );

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffix,
  }) {
    final palette = KayanPalette.of(context);
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: NetRadii.smAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, size: NetSizes.iconSm, color: palette.textTertiary),
      suffixIcon: suffix,
      filled: true,
      fillColor: palette.isDark
          ? palette.surfaceVariant.withValues(alpha: 0.4)
          : palette.appBackground,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: NetSpacing.md,
        vertical: NetSpacing.md,
      ),
      border: border(palette.border, 1),
      enabledBorder: border(palette.border, 1),
      focusedBorder: border(palette.primary, 1.4),
      errorBorder: border(KayanColors.error, 1),
      focusedErrorBorder: border(KayanColors.error, 1.4),
      labelStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.textSecondary,
      ),
      floatingLabelStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: palette.primary,
      ),
      hintStyle: TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 13,
        color: palette.textTertiary,
      ),
      errorStyle: const TextStyle(
        fontFamily: NetTypography.family,
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
