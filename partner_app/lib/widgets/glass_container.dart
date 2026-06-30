import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final BorderRadiusGeometry? borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final BoxBorder? border;
  final Gradient? gradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 24,
    this.borderRadius,
    this.blur = 30,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
    this.border,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(radius);

    final effectiveBlur = isDark ? 28.0 : 18.0;

    final effectiveBorder = border ?? Border.all(
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.65),
      width: 1.0,
    );

    final effectiveGradient = gradient ?? LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ]
          : [
              Colors.white.withOpacity(0.70),
              Colors.white.withOpacity(0.45),
            ],
    );

    final effectiveShadows = isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.04),
              blurRadius: 40,
              offset: const Offset(0, 15),
            ),
          ]
        : [
            const BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              spreadRadius: 0,
              offset: Offset(0, 8),
            ),
          ];

    return Container(
      margin: margin,
      width: width,
      height: height,
      alignment: alignment,
      decoration: BoxDecoration(
        borderRadius: effectiveBorderRadius,
        boxShadow: effectiveShadows,
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: effectiveBorderRadius,
              border: effectiveBorder,
              gradient: effectiveGradient,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
