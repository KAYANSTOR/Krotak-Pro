import 'package:flutter/material.dart';

import '../../application/account_session.dart';
import '../../domain/entities/cloud_account.dart';
import '../theme/kayan_palette.dart';
import '../theme/net_semantic_colors.dart';
import '../theme/net_tokens.dart';
import '../widgets/async_views.dart';
import '../widgets/net/net_app_bar_title.dart';
import '../widgets/net/net_surface_card.dart';

/// إشعارات الإدارة: الإشعارات الموجهة لهذا الحساب + الإشعارات العامة.
class AccountNotificationsScreen extends StatefulWidget {
  const AccountNotificationsScreen({super.key});

  @override
  State<AccountNotificationsScreen> createState() =>
      _AccountNotificationsScreenState();
}

class _AccountNotificationsScreenState
    extends State<AccountNotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AccountSession.maybeInstance?.refreshNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final session = AccountSession.maybeInstance;

    return Scaffold(
      appBar: AppBar(
        title: const NetAppBarTitle(
          icon: Icons.notifications_none_rounded,
          title: 'إشعارات الإدارة',
        ),
      ),
      body: session == null
          ? const SizedBox.shrink()
          : ValueListenableBuilder<AccountState>(
              valueListenable: session.state,
              builder: (context, state, _) {
                final notifications = state.notifications;
                if (notifications.isEmpty) {
                  return const AsyncEmptyView(
                    message: 'لا توجد إشعارات',
                    icon: Icons.notifications_off_outlined,
                    hint: 'ستظهر هنا الإشعارات التي ترسلها الإدارة إلى حسابك.',
                  );
                }
                return RefreshIndicator(
                  color: palette.primary,
                  onRefresh: () async {
                    await session.refreshNotifications();
                  },
                  child: ListView.separated(
                    padding: NetSpacing.screen,
                    itemCount: notifications.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: NetSpacing.md),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return _header(context, state);
                      }
                      final notification = notifications[index - 1];
                      return _notificationCard(context, session, notification);
                    },
                  ),
                );
              },
            ),
    );
  }

  Widget _header(BuildContext context, AccountState state) {
    final palette = KayanPalette.of(context);
    final unread = state.unreadCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: NetSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              unread == 0
                  ? 'كل الإشعارات مقروءة'
                  : '$unread إشعار غير مقروء',
              style: TextStyle(
                fontFamily: NetTypography.family,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.textSecondary,
              ),
            ),
          ),
          if (unread > 0)
            TextButton(
              onPressed: () =>
                  AccountSession.maybeInstance?.markAllNotificationsRead(),
              child: const Text('تعليم الكل كمقروء'),
            ),
        ],
      ),
    );
  }

  Widget _notificationCard(
    BuildContext context,
    AccountSession session,
    CloudNotification notification,
  ) {
    final palette = KayanPalette.of(context);
    final net = context.netColors;
    final accent = notification.isGlobal ? net.info : palette.primary;

    return NetSurfaceCard(
      onTap: notification.isRead
          ? null
          : () => session.markNotificationRead(notification),
      borderColor: notification.isRead
          ? palette.border
          : accent.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: palette.isDark ? 0.22 : 0.10),
                  borderRadius: NetRadii.smAll,
                ),
                child: Icon(
                  notification.isGlobal
                      ? Icons.campaign_outlined
                      : Icons.mark_email_unread_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: NetSpacing.sm),
              Expanded(
                child: Text(
                  notification.title.isEmpty ? 'إشعار' : notification.title,
                  style: TextStyle(
                    fontFamily: NetTypography.family,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              if (!notification.isRead)
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
            ],
          ),
          const SizedBox(height: NetSpacing.sm),
          Text(
            notification.message,
            style: TextStyle(
              fontFamily: NetTypography.family,
              fontSize: 13,
              height: 1.55,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(height: NetSpacing.sm),
          Row(
            children: [
              Text(
                _formatDate(notification.createdAt),
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 11.5,
                  color: palette.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                notification.isGlobal ? 'للجميع' : 'لحسابك',
                style: TextStyle(
                  fontFamily: NetTypography.family,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: palette.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} · $hour:$minute';
  }
}