import 'package:flutter/material.dart';

import '../../theme/kayan_palette.dart';
import '../../theme/net_tokens.dart';

/// Unified bottom sheet shell: handle, header, scrollable body, optional footer.
///
/// Every sheet in the app uses this so radius, background, drag handle and
/// keyboard insets stay identical (and follow light/dark theme).
class NetSheet extends StatelessWidget {
  const NetSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.children = const <Widget>[],
    this.body,
    this.footer,
    this.maxHeightFactor = 0.9,
    this.showHandle = true,
    this.showClose = true,
    this.headerActions = const <Widget>[],
    this.padding = const EdgeInsets.fromLTRB(
      NetSpacing.xl,
      NetSpacing.xs,
      NetSpacing.xl,
      NetSpacing.xxl,
    ),
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> children;
  final Widget? body;
  final Widget? footer;
  final double maxHeightFactor;
  final bool showHandle;
  final bool showClose;
  final List<Widget> headerActions;
  final EdgeInsetsGeometry padding;

  /// Opens [builder] inside the standard modal configuration.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool isDismissible = true,
    bool enableDrag = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = KayanPalette.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;

    final bodyContent = body ??
        ListView(
          shrinkWrap: true,
          padding: padding,
          children: children,
        );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: palette.surface,
            borderRadius: NetRadii.sheetTop,
            boxShadow: NetElevation.raised(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHandle)
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(top: NetSpacing.md),
                    decoration: BoxDecoration(
                      color: palette.border,
                      borderRadius: NetRadii.pillAll,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  NetSpacing.xl,
                  NetSpacing.lg,
                  NetSpacing.sm,
                  NetSpacing.sm,
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: NetSizes.badge,
                        height: NetSizes.badge,
                        decoration: BoxDecoration(
                          color: palette.iconBadgeBackground,
                          borderRadius: NetRadii.smAll,
                        ),
                        child: Icon(icon, size: 20, color: palette.primary),
                      ),
                      const SizedBox(width: NetSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: NetTypography.family,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              color: palette.textPrimary,
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: NetTypography.family,
                                fontSize: 12,
                                height: 1.35,
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ...headerActions,
                    if (showClose)
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.close_rounded, color: palette.textSecondary),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.border),
              Flexible(child: bodyContent),
              if (footer != null) ...[
                Divider(height: 1, color: palette.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    NetSpacing.xl,
                    NetSpacing.md,
                    NetSpacing.xl,
                    NetSpacing.md,
                  ),
                  child: footer,
                ),
              ],
              SizedBox(height: bottomPadding > 0 ? bottomPadding : NetSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
