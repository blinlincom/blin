import 'package:flutter/material.dart';

import '../../design/breakpoints.dart';
import '../../design/tokens.dart';
import 'bim_top_bar.dart';

class BimShellDestination {
  const BimShellDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    this.badge = 0,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
}

class BimAdaptiveShell extends StatelessWidget {
  const BimAdaptiveShell({
    required this.title,
    required this.body,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.actions = const [],
    this.blocked = false,
    this.onBlockedInteraction,
    super.key,
  });

  final String title;
  final Widget body;
  final List<BimShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> actions;
  final bool blocked;
  final VoidCallback? onBlockedInteraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width < BimBreakpoints.medium) {
          return _CompactShell(
            title: title,
            body: body,
            actions: actions,
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: _select,
          );
        }
        final extended = width >= BimBreakpoints.desktop;
        return _WideShell(
          title: title,
          body: body,
          actions: actions,
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: _select,
          extended: extended,
        );
      },
    );
  }

  void _select(int value) {
    if (blocked) {
      onBlockedInteraction?.call();
      return;
    }
    onDestinationSelected(value);
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.title,
    required this.body,
    required this.actions,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final List<BimShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BimColors.background,
      appBar: BimTopBar(title: title, actions: actions),
      body: SafeArea(top: false, child: body),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: BimColors.surface,
          border: Border(top: BorderSide(color: BimColors.borderLight)),
        ),
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final destination in destinations)
              NavigationDestination(
                icon: _ShellIcon(
                  icon: destination.icon,
                  badge: destination.badge,
                ),
                selectedIcon: _ShellIcon(
                  icon: destination.selectedIcon,
                  badge: destination.badge,
                  selected: true,
                ),
                label: destination.label,
              ),
          ],
        ),
      ),
    );
  }
}

class _WideShell extends StatelessWidget {
  const _WideShell({
    required this.title,
    required this.body,
    required this.actions,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.extended,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final List<BimShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BimColors.background,
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: extended
                  ? BimDimensions.navigationSidebar
                  : BimDimensions.navigationRail,
              child: NavigationRail(
                extended: extended,
                minWidth: BimDimensions.navigationRail,
                minExtendedWidth: BimDimensions.navigationSidebar,
                selectedIndex: selectedIndex,
                onDestinationSelected: onDestinationSelected,
                labelType: extended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.all,
                leading: Padding(
                  padding: const EdgeInsets.only(
                    top: BimSpacing.x3,
                    bottom: BimSpacing.x6,
                  ),
                  child: _BimIdentityMark(extended: extended),
                ),
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                      icon: _ShellIcon(
                        icon: destination.icon,
                        badge: destination.badge,
                      ),
                      selectedIcon: _ShellIcon(
                        icon: destination.selectedIcon,
                        badge: destination.badge,
                        selected: true,
                      ),
                      label: Text(destination.label),
                    ),
                ],
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Column(
                children: [
                  _WorkspaceHeader(title: title, actions: actions),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: BimDimensions.workspaceMax,
                        ),
                        child: body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: EdgeInsets.symmetric(
        horizontal: BimBreakpoints.horizontalPadding(context),
      ),
      decoration: const BoxDecoration(
        color: BimColors.surface,
        border: Border(bottom: BorderSide(color: BimColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Text(
                title,
                key: ValueKey(title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BimColors.textDark,
                  fontSize: BimTypography.profile,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

class _BimIdentityMark extends StatelessWidget {
  const _BimIdentityMark({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: BimDimensions.touchTarget,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            color: BimColors.primary,
            child: const Text(
              'B',
              style: TextStyle(
                color: BimColors.surface,
                fontSize: BimTypography.title,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (extended) ...[
            const SizedBox(width: BimSpacing.x3),
            const Text(
              'BIM',
              style: TextStyle(
                color: BimColors.textDark,
                fontSize: BimTypography.title,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ShellIcon extends StatelessWidget {
  const _ShellIcon({
    required this.icon,
    required this.badge,
    this.selected = false,
  });

  final IconData icon;
  final int badge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 30,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(icon, color: selected ? BimColors.primary : null),
          if (badge > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: BimColors.danger,
                  borderRadius: BorderRadius.circular(BimRadius.pill),
                  border: Border.all(color: BimColors.surface, width: 1.5),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: BimColors.surface,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
