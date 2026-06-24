import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hospi_dash/core/theme/app_breakpoints.dart';
import 'package:hospi_dash/core/theme/app_elevation.dart';
import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';

const double _sheetFloatingNavClearance = 104;

/// Editorial scaffold. Warm canvas, single hairline divider under the top bar,
/// content max-width clamp, and zero gratuitous chrome.
///
/// Use as the root of every screen instead of bare [Scaffold] so colors,
/// safe-area handling, and content clamps stay consistent.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    required this.body,
    super.key,
    this.topBar,
    this.bottomBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.clampContent = true,
    this.resizeToAvoidBottomInset,
  });

  final PreferredSizeWidget? topBar;
  final Widget body;
  final Widget? bottomBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final bool clampContent;
  final bool? resizeToAvoidBottomInset;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? EditorialColors.background;

    Widget content = body;
    if (clampContent) {
      content = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.contentMax),
          child: content,
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: bg,
        appBar: topBar,
        body: content,
        bottomNavigationBar: bottomBar,
        floatingActionButton: floatingActionButton,
        floatingActionButtonLocation: floatingActionButtonLocation ??
            (floatingActionButton == null
                ? null
                : FloatingActionButtonLocation.centerFloat),
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      ),
    );
  }
}

/// Editorial top bar. Title in Fraunces, optional eyebrow label above it,
/// quiet actions on the right. No drop shadow; a single hairline divides
/// it from content.
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title,
    this.eyebrow,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.dense = false,
  });

  final String? title;
  final String? eyebrow;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final bool dense;

  @override
  Size get preferredSize => Size.fromHeight(dense ? 52 : 60);

  @override
  Widget build(BuildContext context) {
    final titleText = title == null
        ? null
        : Column(
            crossAxisAlignment: centerTitle
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null)
                Text(
                  eyebrow!.toLowerCase(),
                  style: EditorialTypography.labelSmall.copyWith(
                    color: EditorialColors.onSurfaceVariant,
                    letterSpacing: 0.6,
                  ),
                ),
              Text(
                title!,
                style: EditorialTypography.titleLarge.copyWith(
                  color: EditorialColors.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          );

    return PreferredSize(
      preferredSize: preferredSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: EditorialColors.background,
          border: Border(bottom: AppElevation.hairlineSide),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: preferredSize.height,
            child: NavigationToolbar(
              leading: leading,
              middle: titleText,
              trailing: actions == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!,
                    ),
              centerMiddle: centerTitle,
              middleSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Standardised modal bottom sheet wrapper. Top hairline drag handle,
/// generous internal padding, square-ish corners (no balloon radius).
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fullHeight = false,
  bool dismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.32),
    isDismissible: dismissible,
    enableDrag: dismissible,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      final maxHeight = media.size.height * (fullHeight ? 0.92 : 0.86);
      return AnimatedPadding(
        duration: AppMotion.fast,
        curve: AppMotion.enter,
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: _AppSheet(child: builder(ctx)),
        ),
      );
    },
  );
}

class _AppSheet extends StatelessWidget {
  const _AppSheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: EditorialColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(EditorialRadius.lg),
        ),
        border: Border(top: AppElevation.hairlineSide),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: EditorialColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewPadding.bottom +
                      _sheetFloatingNavClearance,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet offline banner. Sits beneath the top bar; one line, hairline border.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    this.message = 'You are offline. Changes will sync when reconnected.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: EditorialColors.surfaceContainerLow,
        border: Border(bottom: AppElevation.hairlineSide),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: EditorialColors.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: EditorialTypography.labelMedium.copyWith(
                color: EditorialColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
