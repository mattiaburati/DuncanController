import 'package:flutter/material.dart';

class BrandEnvironmentStyle {
  const BrandEnvironmentStyle({
    required this.accentColor,
    required this.surfaceTint,
    required this.icon,
    required this.assetPath,
  });

  final Color accentColor;
  final Color surfaceTint;
  final IconData icon;
  final String assetPath;

  static const BrandEnvironmentStyle duncan = BrandEnvironmentStyle(
    accentColor: Color(0xFF9A5A28),
    surfaceTint: Color(0x1F9A5A28),
    icon: Icons.local_dining_rounded,
    assetPath: 'assets/images/duncan.jpeg',
  );

  static BrandEnvironmentStyle forEnvironmentName(String environmentName) {
    return duncan;
  }
}

class BrandVisualPlaceholder extends StatelessWidget {
  const BrandVisualPlaceholder({
    super.key,
    this.height,
    this.borderRadius = 30,
    this.showOverlayFrame = true,
    this.showInfoPanel = true,
    this.eyebrow = 'Duncan',
    this.title = 'Duncan',
    this.subtitle = 'Controllo relè',
    this.trailingIcon = Icons.light_mode_rounded,
    this.statusLabel,
    this.accentColor = const Color(0xFF9A5A28),
    this.assetPath = 'assets/images/duncan.jpeg',
  });

  static const String heroAssetPath = 'assets/images/duncan.jpeg';

  final double? height;
  final double borderRadius;
  final bool showOverlayFrame;
  final bool showInfoPanel;
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final IconData? trailingIcon;
  final String? statusLabel;
  final Color accentColor;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ?? 320;

    return SizedBox(
      height: resolvedHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              assetPath,
              fit: BoxFit.cover,
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0x30000000),
                    Color(0x12000000),
                    Color(0x660D1715),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accentColor.withValues(alpha: 0.14),
                    accentColor.withValues(alpha: 0.08),
                    accentColor.withValues(alpha: 0.34),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            if (eyebrow != null || trailingIcon != null)
              Positioned(
                top: 24,
                left: 24,
                right: 24,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (eyebrow != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.44),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          eyebrow!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    const Spacer(),
                    if (trailingIcon != null)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.34),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          trailingIcon,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            if (showInfoPanel)
              Positioned(
                left: 24,
                right: 24,
                bottom: 24,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (statusLabel != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              statusLabel!,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xE6FFFFFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            if (showOverlayFrame)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.42),
                      width: 1.4,
                    ),
                    borderRadius: BorderRadius.circular(borderRadius),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
