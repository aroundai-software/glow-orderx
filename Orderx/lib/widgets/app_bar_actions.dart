// lib/widgets/app_bar_actions.dart
// Reusable AppBar action components for consistent UI/UX

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:Orderx/core/theme/app_theme.dart';
import 'package:Orderx/providers/cart_provider.dart';

/// Refresh button with loading state support
class AppBarRefreshButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isLoading;

  const AppBarRefreshButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.refresh),
      tooltip: 'Refresh',
      onPressed: isLoading ? null : onPressed,
    );
  }
}

/// Cart icon with badge showing item count
class AppBarCartButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AppBarCartButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<CartProvider>(
      builder: (context, cartProvider, child) {
        return Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.shopping_cart),
              tooltip: 'View cart',
              onPressed: onPressed,
            ),
            if (cartProvider.itemCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: AppTheme.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    cartProvider.itemCount > 99
                        ? '99+'
                        : '${cartProvider.itemCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Settings/tune button
class AppBarSettingsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;

  const AppBarSettingsButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Settings',
    this.icon = Icons.tune,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }
}

/// Overflow menu for secondary actions (reduces AppBar clutter)
class AppBarOverflowMenu extends StatelessWidget {
  final List<AppBarMenuItem> items;

  const AppBarOverflowMenu({
    super.key,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More options',
      onSelected: (value) {
        final item = items.firstWhere((i) => i.value == value);
        item.onTap();
      },
      itemBuilder: (context) => items
          .map((item) => PopupMenuItem<String>(
                value: item.value,
                child: Row(
                  children: [
                    if (item.icon != null) ...[
                      Icon(item.icon, size: 20, color: AppTheme.darkGrey),
                      const SizedBox(width: 12),
                    ],
                    Text(item.label),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

/// Menu item for AppBarOverflowMenu
class AppBarMenuItem {
  final String value;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const AppBarMenuItem({
    required this.value,
    required this.label,
    this.icon,
    required this.onTap,
  });
}

/// Notification badge button (for pending approvals, stock alerts, etc.)
class AppBarBadgeButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onPressed;
  final String tooltip;

  const AppBarBadgeButton({
    super.key,
    required this.icon,
    required this.count,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: AppTheme.error,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}


/// Interactive company switcher that handles its own name loading and switching logic
class GlobalCompanySwitcher extends StatelessWidget {
  final VoidCallback? onCompanyChanged;

  const GlobalCompanySwitcher({super.key, this.onCompanyChanged});

  @override
  Widget build(BuildContext context) {
    // Company switching is locked, so we hide the UI completely.
    return const SizedBox.shrink();
  }
}

/// Company switcher chip for AppBar (Stateless presentation)
class AppBarCompanyChip extends StatelessWidget {
  final String? companyName;
  final VoidCallback onTap;

  const AppBarCompanyChip({
    super.key,
    required this.companyName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(51), // 0.2 opacity = 51/255
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.business, size: 16),
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(
                    companyName ?? 'Select Company',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logout button
class AppBarLogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const AppBarLogoutButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout),
      tooltip: 'Logout',
      onPressed: onPressed,
    );
  }
}

/// Title with optional subtitle (for company name, etc.)
class AppBarTitleWithSubtitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const AppBarTitleWithSubtitle({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Colors.white.withAlpha(204), // 0.8 opacity
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}
