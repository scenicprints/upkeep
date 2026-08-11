import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════════════════════════
// UPKEEP — instrument-cluster palette
//
// The app reads like a dashboard: near-black panel, machined dials, one
// luminous state colour at a time. Colours are semantic, not decorative —
// a gauge's colour IS its state, so nothing else in the UI is allowed to
// borrow amber, green or red.
// ═══════════════════════════════════════════════════════════════════════

// Surfaces
const Color kBg = Color(0xFF0A0C0F); // page
const Color kPanel = Color(0xFF12161B); // card
const Color kPanelEdge = Color(0xFF1E252D); // hairline border
const Color kTrack = Color(0xFF1B2128); // unfilled part of a gauge arc
const Color kHairline = Color(0xFF171C22); // list dividers
const Color kNavBg = Color(0xFF0C0F13);

// Text
const Color kText = Color(0xFFE8EDF3);
const Color kTextDim = Color(0xFF8E9AA8);
const Color kTextFaint = Color(0xFF5D6773);

// Gauge states — the only place these colours appear.
const Color kHealthy = Color(0xFF3DD68C); // under interval
const Color kReady = Color(0xFFFFB020); // 90%+ — do it now
const Color kOverdue = Color(0xFFFF4E4E); // past due
const Color kReadyDim = Color(0xFF8E7238); // label under a ready gauge
const Color kReadyEdge = Color(0xFF3A2E14); // border of a ready card

/// The state a tracked item is in. Drives colour everywhere.
enum GaugeState { healthy, ready, overdue }

Color gaugeColor(GaugeState s) => switch (s) {
      GaugeState.healthy => kHealthy,
      GaugeState.ready => kReady,
      GaugeState.overdue => kOverdue,
    };

/// Numerals are monospaced everywhere they represent a reading — mileage,
/// percentages, dates. Tabular figures stop the cluster from twitching as
/// values change.
const String kMonoFamily = 'monospace';

TextStyle mono({
  double size = 12,
  Color color = kText,
  FontWeight weight = FontWeight.w500,
  double spacing = 0,
}) =>
    TextStyle(
      fontFamily: kMonoFamily,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: spacing,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Small all-caps label, e.g. "EVERYTHING ELSE" or an asset name.
TextStyle eyebrow({double size = 9.5, Color color = kTextFaint}) => TextStyle(
      fontSize: size,
      color: color,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w500,
    );

ThemeData buildTheme() {
  final ThemeData base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      surface: kBg,
      primary: kReady,
      onPrimary: const Color(0xFF171004),
      secondary: kHealthy,
      error: kOverdue,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: kText,
      displayColor: kText,
    ),
    dividerColor: kHairline,
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kPanel,
      contentTextStyle: TextStyle(color: kText, fontSize: 13),
      behavior: SnackBarBehavior.floating,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: kPanel),
  );
}

/// Standard panel decoration. [ready] swaps the hairline for the amber edge
/// used on items that need attention.
BoxDecoration panelBox({bool ready = false, double radius = 18}) =>
    BoxDecoration(
      color: kPanel,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: ready ? kReadyEdge : kPanelEdge, width: 0.5),
    );
