import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  final String level;
  final double size;

  const StatusBadge({super.key, required this.level, this.size = 24.0});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;

    switch (level) {
      case 'Pro':
        icon = Icons.workspace_premium;
        color = Colors.purple;
        label = 'Pro';
        break;
      case 'BiblioGenius':
        icon = Icons.verified;
        color = Colors.amber;
        label = 'BiblioGenius';
        break;
      case 'Member':
      default:
        icon = Icons.verified_user_outlined;
        color = Colors.grey;
        label = 'Member';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: size),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: size * 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
