import 'package:flutter/material.dart';

/// BiblioGenius Design System
/// Centralized design tokens for consistent styling across the app

class AppDesign {
  AppDesign._();

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENT PALETTES
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary brand gradient - Purple/Indigo
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  /// Discrete page background gradient - Light Blue Grey
  static const pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)], // Slate-50 -> Slate-200
    stops: [0.0, 1.0],
  );

  /// Theme-aware page gradient - use this for Sorbonne compatibility
  static LinearGradient pageGradientForTheme(String themeStyle) {
    if (themeStyle == 'sorbonne') {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0D0705), Color(0xFF1A0F0A), Color(0xFF2D1810)],
      );
    }
    return pageGradient;
  }

  /// Sorbonne dark wood page gradient
  static const sorbonnePageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0D0705), Color(0xFF1A0F0A), Color(0xFF2D1810)],
  );

  /// Success gradient - Green tones
  static const successGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF10B981), Color(0xFF059669)],
  );

  /// Warning gradient - Orange/Amber
  static const warningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
  );

  /// Accent gradient - Pink/Rose
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEC4899), Color(0xFFDB2777)],
  );

  /// Dark gradient - Slate tones
  static const darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
  );

  /// Ocean gradient - Blue/Cyan
  static const oceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0EA5E9), Color(0xFF0284C7)],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // PASTEL GRADIENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pastel Primary (Soft Purple/Indigo)
  static const pastelPrimaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF818CF8), Color(0xFFA78BFA)],
  );

  /// Pastel Success (Soft Green)
  static const pastelSuccessGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF34D399), Color(0xFF10B981)],
  );

  /// Pastel Accent (Soft Pink)
  static const pastelAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF472B6), Color(0xFFEC4899)],
  );

  /// Pastel Warning (Soft Orange)
  static const pastelWarningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
  );

  /// Pastel Ocean (Soft Blue)
  static const pastelOceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    colors: [Color(0xFF38BDF8), Color(0xFF0EA5E9)],
  );

  // ═══════════════════════════════════════════════════════════════════════════
  // STAT CARD GRADIENTS (Harmonized with app teal/indigo palette)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Primary stat (Indigo — matches app primary brand)
  static const refinedPrimaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF818CF8)],
  );

  /// Success stat (Teal — matches app bar / sidebar)
  static const refinedSuccessGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF5C8C9F), Color(0xFF6BB0A9)],
  );

  /// Accent stat (Muted rose — warm complement to teal)
  static const refinedAccentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFB07D8E), Color(0xFFC9939F)],
  );

  /// Warning stat (Warm amber — complements the cream background)
  static const refinedWarningGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFC4956A), Color(0xFFD4A574)],
  );

  /// Ocean stat (Slate blue — muted complement to indigo)
  static const refinedOceanGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF7189A8), Color(0xFF8DA0B8)],
  );

  /// Anthracite gradient (Stone — matches app text color family)
  static const anthraciteGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF57534E), Color(0xFF78716C)], // Stone-600 -> Stone-500
  );
  // ═══════════════════════════════════════════════════════════════════════════
  // PASTEL COLORS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pastel Blue - 0xFF81D4FA
  static const pastelBlue = Color(0xFF81D4FA);

  /// Pastel Green - 0xFFA5D6A7
  static const pastelGreen = Color(0xFFA5D6A7);

  /// Pastel Purple - 0xFFCE93D8
  static const pastelPurple = Color(0xFFCE93D8);

  /// Pastel Orange - 0xFFFFCC80
  static const pastelOrange = Color(0xFFFFCC80);

  /// Pastel Cyan - 0xFF80DEEA
  static const pastelCyan = Color(0xFF80DEEA);

  /// Pastel Blue Grey - 0xFFB0BEC5
  static const pastelBlueGrey = Color(0xFFB0BEC5);
  // ═══════════════════════════════════════════════════════════════════════════
  // SHADOW PRESETS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Subtle shadow for flat cards
  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  /// Standard card shadow
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  /// Elevated shadow for modals and floating elements
  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.12),
      blurRadius: 24,
      spreadRadius: 4,
      offset: const Offset(0, 8),
    ),
  ];

  /// Glow shadow for interactive elements
  static List<BoxShadow> glowShadow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.4),
      blurRadius: 16,
      spreadRadius: 2,
      offset: const Offset(0, 4),
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // ANIMATION CONSTANTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Quick micro-interactions
  static const Duration quickDuration = Duration(milliseconds: 150);

  /// Standard transitions
  static const Duration standardDuration = Duration(milliseconds: 300);

  /// Emphasis animations
  static const Duration emphasisDuration = Duration(milliseconds: 500);

  /// Page transitions
  static const Duration pageDuration = Duration(milliseconds: 400);

  /// Standard easing curve
  static const Curve standardCurve = Curves.easeInOut;

  /// Bounce effect curve
  static const Curve bounceCurve = Curves.elasticOut;

  /// Smooth deceleration
  static const Curve decelerateCurve = Curves.decelerate;

  // ═══════════════════════════════════════════════════════════════════════════
  // BORDER RADIUS
  // ═══════════════════════════════════════════════════════════════════════════

  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusRound = 100.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // SPACING
  // ═══════════════════════════════════════════════════════════════════════════

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;
  static const double spacingXxl = 48.0;

  // ═══════════════════════════════════════════════════════════════════════════
  // GLASSMORPHISM DECORATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Frosted glass effect for light backgrounds
  static BoxDecoration glassDecoration({
    double opacity = 0.1,
    double borderRadius = radiusLarge,
    Color baseColor = Colors.white,
  }) {
    return BoxDecoration(
      color: baseColor.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: baseColor.withValues(alpha: opacity * 2),
        width: 1.5,
      ),
    );
  }

  /// Gradient card decoration
  static BoxDecoration gradientCardDecoration({
    required Gradient gradient,
    double borderRadius = radiusLarge,
  }) {
    return BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: cardShadow,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // GRADIENT HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Create a shimmer/overlay gradient for images
  static LinearGradient imageOverlay({bool fromTop = true}) {
    return LinearGradient(
      begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
      end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
      colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // THEME-AWARE HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Theme-aware AppBar gradient
  static LinearGradient appBarGradientForTheme(String themeStyle) {
    switch (themeStyle) {
      case 'sorbonne':
        return const LinearGradient(
          colors: [Color(0xFF1A0F0A), Color(0xFF2D1810)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case 'minimal':
        return const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      default:
        return const LinearGradient(
          colors: [Color(0xFF6BB0A9), Color(0xFF5C8C9F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  /// Theme-aware section accent gradient (for decorative bars / icons)
  static LinearGradient sectionAccentGradient(String themeStyle) {
    switch (themeStyle) {
      case 'sorbonne':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8B4513), Color(0xFF5D3A1A)],
        );
      case 'minimal':
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
        );
      default:
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        );
    }
  }

  /// Feature gradient based on index (for lists)
  static LinearGradient featureGradient(int index) {
    final gradients = [
      primaryGradient,
      successGradient,
      warningGradient,
      accentGradient,
      oceanGradient,
    ];
    return gradients[index % gradients.length];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ANIMATED GRADIENT CONTAINER
// ═══════════════════════════════════════════════════════════════════════════

/// A container that animates between gradient backgrounds
class AnimatedGradientContainer extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final Duration duration;

  const AnimatedGradientContainer({
    super.key,
    required this.child,
    required this.gradient,
    this.duration = AppDesign.standardDuration,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duration,
      decoration: BoxDecoration(gradient: gradient),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SCALE ON TAP WIDGET
// ═══════════════════════════════════════════════════════════════════════════

/// Widget that scales down slightly when tapped for tactile feedback
class ScaleOnTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleAmount;

  const ScaleOnTap({
    super.key,
    required this.child,
    this.onTap,
    this.scaleAmount = 0.95,
  });

  @override
  State<ScaleOnTap> createState() => _ScaleOnTapState();
}

class _ScaleOnTapState extends State<ScaleOnTap> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? widget.scaleAmount : 1.0,
        duration: AppDesign.quickDuration,
        curve: AppDesign.standardCurve,
        child: widget.child,
      ),
    );

    // Show pointer cursor on hover when clickable
    if (widget.onTap != null) {
      return MouseRegion(cursor: SystemMouseCursors.click, child: child);
    }
    return child;
  }
}
