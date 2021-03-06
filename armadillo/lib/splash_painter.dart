// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Paints a 'splash' of [splashColor] by drawing a ring around [splashOrigin]
/// with an outer radius of [splashRadius] * [outerSplashProgress] and an
/// inner radius of [splashRadius] * [innerSplashProgress].
/// [innerSplashProgress] and [outerSplashProgress] are expected to go from 0.0
/// to 1.0 and [innerSplashProgress] <= [outerSplashProgress].
class SplashPainter extends CustomPainter {
  final double innerSplashProgress;
  final double outerSplashProgress;
  final Point splashOrigin;
  final Color splashColor;
  final double splashRadius;

  SplashPainter(
      {this.innerSplashProgress,
      this.outerSplashProgress,
      this.splashOrigin,
      this.splashColor,
      this.splashRadius});

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = new Paint()
      ..color = splashColor
      ..style = PaintingStyle.fill;
    double innerRadius = innerSplashProgress * splashRadius * math.sqrt(2.0);
    double outerRadius = outerSplashProgress * splashRadius * math.sqrt(2.0);
    Path path = new Path()
      ..arcTo(
        new Rect.fromCircle(center: splashOrigin, radius: outerRadius),
        0.0,
        math.PI,
        true,
      )
      ..arcTo(
        new Rect.fromCircle(center: splashOrigin, radius: outerRadius),
        math.PI,
        math.PI,
        false,
      )
      ..arcTo(
        new Rect.fromCircle(center: splashOrigin, radius: innerRadius),
        0.0,
        -math.PI,
        true,
      )
      ..arcTo(
        new Rect.fromCircle(center: splashOrigin, radius: innerRadius),
        -math.PI,
        -math.PI,
        false,
      );
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(SplashPainter oldDelegate) =>
      (oldDelegate.innerSplashProgress != innerSplashProgress) ||
      (oldDelegate.outerSplashProgress != outerSplashProgress) ||
      (oldDelegate.splashOrigin != splashOrigin) ||
      (oldDelegate.splashColor != splashColor) ||
      (oldDelegate.splashRadius != splashRadius);
}
