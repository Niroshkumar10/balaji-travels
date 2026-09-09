import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// App bar with a back button that ALWAYS works.
///
/// The Material auto-implied leading depends on `Navigator.canPop`, which with
/// go_router's redirect + refreshListenable can be false even on a pushed
/// screen. This checks `context.canPop()` first and otherwise navigates to a
/// sensible fallback (the role's home), so "back" is never a dead button.
class RtAppBar extends StatelessWidget implements PreferredSizeWidget {
  const RtAppBar({
    super.key,
    required this.title,
    this.actions,
    this.fallbackRoute = '/c/home',
    this.showBack = true,
    this.bottom,
  });

  final String title;
  final List<Widget>? actions;
  final String fallbackRoute;
  final bool showBack;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      automaticallyImplyLeading: false,
      leading: showBack
          ? IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go(fallbackRoute);
                }
              },
            )
          : null,
      actions: actions,
      bottom: bottom,
    );
  }
}

/// A circular icon "chip" — used as the leading of list tiles for a cleaner,
/// more app-like look (tinted circle + icon).
class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.color = AppColors.primary,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}
