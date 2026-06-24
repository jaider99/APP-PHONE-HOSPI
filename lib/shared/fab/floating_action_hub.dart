import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:hospi_dash/core/theme/app_motion.dart';
import 'package:hospi_dash/core/theme/editorial_theme.dart';
import 'package:hospi_dash/core/navigation/route_ui_config.dart';
import 'package:hospi_dash/shared/ui/premium_fab.dart';

import 'app_fab_action.dart';
import 'fab_action_registry.dart';
import 'scanner_fab_actions.dart';

class FloatingActionHub extends StatelessWidget {
  const FloatingActionHub._({
    required this.ref,
    required this.rootActions,
    required this.scannerActions,
    required _FabMenuLevel initialLevel,
    this.title = 'Actions',
    this.subtitle,
  }) : _initialLevel = initialLevel;

  factory FloatingActionHub.dashboard({required WidgetRef ref}) {
    return FloatingActionHub._(
      ref: ref,
      rootActions: dashboardFabActions(),
      scannerActions: scannerFabActions(ref: ref),
      initialLevel: _FabMenuLevel.root,
      title: 'Quick actions',
      subtitle: 'Choose what you want to do next.',
    );
  }

  factory FloatingActionHub.route({
    required WidgetRef ref,
    required ShellFabActionSet actionSet,
  }) {
    return switch (actionSet) {
      ShellFabActionSet.documents => FloatingActionHub.documents(ref: ref),
      ShellFabActionSet.sales => FloatingActionHub._(
          ref: ref,
          rootActions: salesFabActions(),
          scannerActions: scannerFabActions(ref: ref),
          initialLevel: _FabMenuLevel.root,
          title: 'Sales actions',
          subtitle: 'Import reports or connect a POS system.',
        ),
      ShellFabActionSet.reviewCenter => FloatingActionHub._(
          ref: ref,
          rootActions: reviewFabActions(),
          scannerActions: scannerFabActions(ref: ref),
          initialLevel: _FabMenuLevel.root,
          title: 'Review actions',
          subtitle: 'Jump to the work that clears exceptions.',
        ),
      ShellFabActionSet.dashboard => FloatingActionHub.dashboard(ref: ref),
      ShellFabActionSet.orders ||
      ShellFabActionSet.products ||
      ShellFabActionSet.providers ||
      ShellFabActionSet.expenses ||
      ShellFabActionSet.global => FloatingActionHub._(
          ref: ref,
          rootActions: globalFabActions(),
          scannerActions: scannerFabActions(ref: ref),
          initialLevel: _FabMenuLevel.root,
          title: 'Quick actions',
          subtitle: 'Choose what you want to do next.',
        ),
    };
  }

  factory FloatingActionHub.documents({
    required WidgetRef ref,
    VoidCallback? onManual,
  }) {
    return FloatingActionHub._(
      ref: ref,
      rootActions: const [],
      scannerActions: scannerFabActions(ref: ref, onManual: onManual),
      initialLevel: _FabMenuLevel.scanner,
      title: 'Upload expense',
      subtitle: 'Create a document for extraction.',
    );
  }

  final WidgetRef ref;
  final List<AppFabAction> rootActions;
  final List<AppFabAction> scannerActions;
  final _FabMenuLevel _initialLevel;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return PremiumFAB(
      label: 'Add',
      icon: Icons.add_rounded,
      heroTag: 'shell_premium_fab',
      onPressed: () => _openActions(context),
    );
  }

  Future<void> _openActions(BuildContext context) async {
    final route = ModalRoute.of(context)?.settings.name ?? 'unknown';
    debugPrint('[FAB] Opened on route: $route');
    HapticFeedback.mediumImpact();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close quick actions',
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, _, __) => _FabActionSheet(
        screenContext: context,
        title: title,
        subtitle: subtitle,
        rootActions: rootActions,
        scannerActions: scannerActions,
        initialLevel: _initialLevel,
      ),
      transitionBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: AppMotion.enter),
          child: child,
        );
      },
    );
  }
}

enum _FabMenuLevel { root, scanner }

class _FabActionSheet extends StatefulWidget {
  const _FabActionSheet({
    required this.screenContext,
    required this.title,
    required this.rootActions,
    required this.scannerActions,
    required this.initialLevel,
    this.subtitle,
  });

  final BuildContext screenContext;
  final String title;
  final String? subtitle;
  final List<AppFabAction> rootActions;
  final List<AppFabAction> scannerActions;
  final _FabMenuLevel initialLevel;

  @override
  State<_FabActionSheet> createState() => _FabActionSheetState();
}

class _FabActionSheetState extends State<_FabActionSheet> {
  late _FabMenuLevel _level = widget.initialLevel;

  List<AppFabAction> get _actions => switch (_level) {
        _FabMenuLevel.root => widget.rootActions,
        _FabMenuLevel.scanner => widget.scannerActions,
      };

  String get _title => switch (_level) {
        _FabMenuLevel.root => widget.title,
        _FabMenuLevel.scanner => 'Upload expense',
      };

  String? get _subtitle => switch (_level) {
        _FabMenuLevel.root => widget.subtitle,
        _FabMenuLevel.scanner => 'Pick the fastest capture method.',
      };

  Future<void> _runAction(AppFabAction action) async {
    if (action.type == FabActionType.uploadExpense) {
      debugPrint('[FAB] Selected action: upload_expense');
      HapticFeedback.selectionClick();
      setState(() => _level = _FabMenuLevel.scanner);
      return;
    }

    debugPrint('[FAB] Selected action: ${action.type.name}');
    debugPrint('[NAV] Closing action sheet');
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();

    await Future<void>.delayed(AppMotion.fast);
    if (!widget.screenContext.mounted) return;

    await action.onTap(widget.screenContext);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final fabBottomOffset = media.viewPadding.bottom > 18
        ? media.viewPadding.bottom
        : 18.0;
    final panelBottomOffset = fabBottomOffset + 96;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              onVerticalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 260) Navigator.of(context).pop();
              },
              child: RepaintBoundary(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.12),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: panelBottomOffset,
            child: Align(
              alignment: Alignment.bottomRight,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: media.size.height -
                      media.viewPadding.top -
                      panelBottomOffset -
                      112,
                ),
                child: RepaintBoundary(
                  child: _FabActionPanel(
                    level: _level,
                    title: _title,
                    subtitle: _subtitle,
                    rootActions: widget.rootActions,
                    actions: _actions,
                    onBack: () => setState(() => _level = _FabMenuLevel.root),
                    onAction: _runAction,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: fabBottomOffset,
            child: Center(
              child: _OverlayCloseFab(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FabActionPanel extends StatelessWidget {
  const _FabActionPanel({
    required this.level,
    required this.title,
    required this.rootActions,
    required this.actions,
    required this.onBack,
    required this.onAction,
    this.subtitle,
  });

  final _FabMenuLevel level;
  final String title;
  final String? subtitle;
  final List<AppFabAction> rootActions;
  final List<AppFabAction> actions;
  final VoidCallback onBack;
  final Future<void> Function(AppFabAction action) onAction;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 200),
      curve: AppMotion.enter,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 16),
            child: child,
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: EditorialColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(30),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24000000),
              blurRadius: 34,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (level == _FabMenuLevel.scanner &&
                        rootActions.isNotEmpty) ...[
                      _BackButton(onPressed: onBack),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.plusJakartaSans(
                              color: EditorialColors.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle!,
                              style: GoogleFonts.plusJakartaSans(
                                color: EditorialColors.onSurfaceVariant,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: AppMotion.standard,
                  reverseDuration: AppMotion.fast,
                  switchInCurve: AppMotion.enter,
                  switchOutCurve: AppMotion.exit,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.04),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    key: ValueKey(level),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < actions.length; i++) ...[
                        _StaggeredActionRow(
                          index: i,
                          action: actions[i],
                          onTap: () => onAction(actions[i]),
                        ),
                        if (i != actions.length - 1) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back to quick actions',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: EditorialColors.surfaceContainerLow,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.arrow_back_rounded,
            color: EditorialColors.onSurface,
            size: 21,
          ),
        ),
      ),
    );
  }
}

class _StaggeredActionRow extends StatelessWidget {
  const _StaggeredActionRow({
    required this.index,
    required this.action,
    required this.onTap,
  });

  final int index;
  final AppFabAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final delay = (index * 30).clamp(0, 150);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 180 + delay),
      curve: AppMotion.enter,
      builder: (context, value, child) {
        final delayFraction = delay / (180 + delay);
        final progress = delayFraction >= 1
            ? 1.0
            : ((value - delayFraction) / (1 - delayFraction)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, (1 - progress) * 16),
            child: child,
          ),
        );
      },
      child: _FabActionRow(action: action, onTap: onTap),
    );
  }
}

class _FabActionRow extends StatefulWidget {
  const _FabActionRow({required this.action, required this.onTap});

  final AppFabAction action;
  final VoidCallback onTap;

  @override
  State<_FabActionRow> createState() => _FabActionRowState();
}

class _FabActionRowState extends State<_FabActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final isPrimary = action.isPrimary;
    final fill = isPrimary
        ? EditorialColors.primary
        : EditorialColors.surfaceContainerLow;
    final ink =
        isPrimary ? EditorialColors.onPrimary : EditorialColors.onSurface;
    final secondaryInk = isPrimary
        ? EditorialColors.onPrimary.withValues(alpha: 0.68)
        : EditorialColors.onSurfaceVariant;

    return Semantics(
      button: true,
      label: action.caption == null
          ? action.label
          : '${action.label}. ${action.caption}',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 140),
          curve: AppMotion.enter,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isPrimary
                        ? Colors.white.withValues(alpha: 0.12)
                        : EditorialColors.surfaceContainerLowest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(action.icon, color: ink, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          color: ink,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      if (action.caption != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          action.caption!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            color: secondaryInk,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  action.type == FabActionType.uploadExpense
                      ? Icons.keyboard_arrow_right_rounded
                      : Icons.arrow_forward_ios_rounded,
                  color: secondaryInk,
                  size: action.type == FabActionType.uploadExpense ? 24 : 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayCloseFab extends StatefulWidget {
  const _OverlayCloseFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_OverlayCloseFab> createState() => _OverlayCloseFabState();
}

class _OverlayCloseFabState extends State<_OverlayCloseFab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final disableAnimations = MediaQuery.of(context).disableAnimations;
    final size = width >= 600 ? 64.0 : 60.0;
    final iconSize = width >= 600 ? 30.0 : 28.0;

    return Semantics(
      button: true,
      label: 'Close quick actions',
      child: GestureDetector(
        onTapDown: (_) {
          HapticFeedback.lightImpact();
          setState(() => _pressed = true);
        },
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.96 : 1,
          duration: _pressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 140),
          curve: AppMotion.enter,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 0.125),
            duration: disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: AppMotion.enter,
            builder: (context, turns, child) {
              return Transform.rotate(
                angle: turns * 6.283185307179586,
                child: child,
              );
            },
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: Color(0xFF151515),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x2E000000),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: iconSize,
                weight: 800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
