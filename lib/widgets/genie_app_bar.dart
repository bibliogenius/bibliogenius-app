import 'package:flutter/material.dart';

class GenieAppBar extends StatelessWidget implements PreferredSizeWidget {
  final dynamic title;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Widget? leading;
  final bool automaticallyImplyLeading;

  const GenieAppBar({
    super.key,
    required this.title,
    this.actions,
    this.bottom,
    this.leading,
    this.automaticallyImplyLeading = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: automaticallyImplyLeading,
      leading: leading,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF667eea), Color(0xFF764ba2)], // Blue to Purple (matches dashboard)
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      elevation: 0,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.auto_awesome, // "Spark" / Magic
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: title is Widget
                ? title
                : Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      ),
      actions: actions,
      bottom: bottom,
      centerTitle: false,
      backgroundColor: Colors.transparent, // Required for flexibleSpace to show
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );
}
