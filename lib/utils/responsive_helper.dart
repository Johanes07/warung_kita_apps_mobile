import 'package:flutter/material.dart';

class ResponsiveHelper {
  static bool isSmallScreen(BuildContext context) {
    return MediaQuery.of(context).size.width < 600;
  }

  static bool isMediumScreen(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return width >= 600 && width < 900;
  }

  static bool isLargeScreen(BuildContext context) {
    return MediaQuery.of(context).size.width >= 900;
  }

  static double getPadding(BuildContext context) {
    if (isSmallScreen(context)) return 12.0;
    if (isMediumScreen(context)) return 16.0;
    return 24.0;
  }

  static double getCardPadding(BuildContext context) {
    return isSmallScreen(context) ? 12.0 : 16.0;
  }

  static double getFontSize(
    BuildContext context, {
    double small = 12,
    double medium = 14,
    double large = 16,
  }) {
    if (isSmallScreen(context)) return small;
    if (isMediumScreen(context)) return medium;
    return large;
  }

  static double getIconSize(
    BuildContext context, {
    double small = 18,
    double medium = 20,
    double large = 24,
  }) {
    if (isSmallScreen(context)) return small;
    if (isMediumScreen(context)) return medium;
    return large;
  }

  static EdgeInsets getButtonPadding(BuildContext context) {
    return EdgeInsets.symmetric(
      horizontal: isSmallScreen(context) ? 12 : 16,
      vertical: isSmallScreen(context) ? 10 : 12,
    );
  }

  static double getSpacing(
    BuildContext context, {
    double small = 8,
    double medium = 12,
    double large = 16,
  }) {
    if (isSmallScreen(context)) return small;
    if (isMediumScreen(context)) return medium;
    return large;
  }

  static int getGridCrossAxisCount(BuildContext context) {
    if (isSmallScreen(context)) return 2;
    if (isMediumScreen(context)) return 3;
    return 4;
  }

  static double getImageSize(
    BuildContext context, {
    double small = 100,
    double medium = 120,
    double large = 150,
  }) {
    if (isSmallScreen(context)) return small;
    if (isMediumScreen(context)) return medium;
    return large;
  }
}
