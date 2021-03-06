// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:sysui_widgets/rk4_spring_simulation.dart';
import 'package:sysui_widgets/ticking_state.dart';

import 'now_manager.dart';
import 'now_minimized_info_fader.dart';

typedef void OnQuickSettingsProgressChange(double quickSettingsProgress);

/// Fraction of the minimization animation which should be used for falling away
/// and sliding in of the user context and battery icon.
const double _kFallAwayDurationFraction = 0.35;

/// The distance above the lowest point we can scroll down to when
/// [scrollOffset] is 0.0.
const double _kRestingDistanceAboveLowestPoint = 80.0;

/// When the recent list's scrollOffset exceeds this value we minimize [Now].
const _kNowMinimizationScrollOffsetThreshold = 120.0;

/// When the recent list's scrollOffset exceeds this value we hide quick
/// settings [Now].
const _kNowQuickSettingsHideScrollOffsetThreshold = 16.0;

const double _kQuickSettingsHorizontalPadding = 16.0;

const double _kMaxQuickSettingsBackgroundWidth = 600.0;

/// Shows the user, the user's context, and important settings.  When minimized
/// also shows an affordance for seeing missed interruptions.
class Now extends StatefulWidget {
  final double minHeight;
  final double maxHeight;

  final double quickSettingsHeightBump;
  final OnQuickSettingsProgressChange onQuickSettingsProgressChange;
  final VoidCallback onReturnToOriginButtonTap;
  final VoidCallback onMinimize;
  final VoidCallback onMaximize;
  final VoidCallback onQuickSettingsMaximized;

  /// [onBarVerticalDragUpdate] and [onBarVerticalDragEnd] will be called only
  /// when a vertical drag occurs on [Now] when in its fully minimized bar
  /// state.
  final GestureDragUpdateCallback onBarVerticalDragUpdate;
  final GestureDragEndCallback onBarVerticalDragEnd;

  Now({
    Key key,
    this.minHeight,
    this.maxHeight,
    this.quickSettingsHeightBump,
    this.onQuickSettingsProgressChange,
    this.onReturnToOriginButtonTap,
    this.onMinimize,
    this.onMaximize,
    this.onQuickSettingsMaximized,
    this.onBarVerticalDragUpdate,
    this.onBarVerticalDragEnd,
  })
      : super(key: key);

  @override
  NowState createState() => new NowState();
}

/// Spring description used by the minimization and quick settings reveal
/// simulations.
const RK4SpringDescription _kSimulationDesc =
    const RK4SpringDescription(tension: 600.0, friction: 50.0);

const double _kMinimizationSimulationTarget = 400.0;
const double _kQuickSettingsSimulationTarget = 100.0;

class NowState extends TickingState<Now> {
  /// The simulation for the minimization to a bar.
  final RK4SpringSimulation _minimizationSimulation =
      new RK4SpringSimulation(initValue: 0.0, desc: _kSimulationDesc);

  /// The simulation for the inline quick settings reveal.
  final RK4SpringSimulation _quickSettingsSimulation =
      new RK4SpringSimulation(initValue: 0.0, desc: _kSimulationDesc);

  /// The simulation for showing minimized info in the minimized bar.
  final RK4SpringSimulation _minimizedInfoSimulation = new RK4SpringSimulation(
      initValue: _kMinimizationSimulationTarget, desc: _kSimulationDesc);

  final GlobalKey _quickSettingsKey = new GlobalKey();
  final GlobalKey _importantInfoMaximizedKey = new GlobalKey();

  NowMinimizedInfoFader _nowMinimizedInfoFader;

  /// [scrolloffset] affects the bottom padding of the user and text elements
  /// as well as the overall height of [Now] while maximized.
  double _lastScrollOffset = 0.0;

  // initialized in showQuickSettings
  double _quickSettingsMaximizedHeight = 0.0;
  double _importantInfoMaximizedHeight = 0.0;

  // The width of the quick settings when fully maximized. Initialized in build().
  double _quickSettingsWidth;

  @override
  void initState() {
    super.initState();
    _nowMinimizedInfoFader = new NowMinimizedInfoFader(
      onChange: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void dispose() {
    _nowMinimizedInfoFader.reset();
    super.dispose();
  }

  set scrollOffset(double scrollOffset) {
    if (scrollOffset > _kNowMinimizationScrollOffsetThreshold &&
        _lastScrollOffset < scrollOffset) {
      minimize();
      hideQuickSettings();
    } else if (scrollOffset < _kNowMinimizationScrollOffsetThreshold &&
        _lastScrollOffset > scrollOffset) {
      maximize();
    }
    // When we're past the quick settings threshold and are
    // scrolling further, hide quick settings.
    if (scrollOffset > _kNowQuickSettingsHideScrollOffsetThreshold &&
        _lastScrollOffset < scrollOffset) {
      hideQuickSettings();
    }
    setState(() {
      _lastScrollOffset = scrollOffset;
    });
  }

  @override
  Widget build(BuildContext context) => new LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _quickSettingsWidth =
              math.min(_kMaxQuickSettingsBackgroundWidth, constraints.maxWidth);
          Widget now = new Container(
            margin: new EdgeInsets.only(
              top: math.max(0.0, constraints.maxHeight - _nowHeight),
            ),
            child: new Stack(
              children: [
                // Quick Settings Background.
                new Positioned(
                  left: _kQuickSettingsHorizontalPadding,
                  right: _kQuickSettingsHorizontalPadding,
                  top: _quickSettingsBackgroundTopOffset,
                  child: new Center(
                    child: new Container(
                      height: _quickSettingsBackgroundHeight,
                      width: _quickSettingsBackgroundWidth,
                      decoration: new BoxDecoration(
                        backgroundColor: new Color(0xFFFFFFFF),
                        borderRadius: new BorderRadius.circular(
                          _quickSettingsBackgroundBorderRadius,
                        ),
                      ),
                    ),
                  ),
                ),
                // User Image, User Context Text, and Important Information when maximized.
                new Positioned(
                  left: _kQuickSettingsHorizontalPadding,
                  right: _kQuickSettingsHorizontalPadding,
                  top: _userImageTopOffset,
                  child: new Center(
                    child: new Column(
                      children: [
                        // User Profile image
                        _buildUserImage(),
                        // User Context Text when maximized.
                        new Padding(
                          padding: const EdgeInsets.only(top: 24.0),
                          child: new Opacity(
                            opacity: _fallAwayOpacity,
                            child: _nowManager(context).userContextMaximized,
                          ),
                        ),
                        // Important Information when maximized.
                        new Container(
                            width: _importantInfoMaximizedWidth,
                            key: _importantInfoMaximizedKey,
                            child: new Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: new Opacity(
                                opacity: _fallAwayOpacity,
                                child: _nowManager(context)
                                    .importantInfoMaximized(
                                        _quickSettingsBackgroundMaximizedWidth),
                              ),
                            )),
                        // Quick Settings
                        _buildQuickSettings(),
                      ],
                    ),
                  ),
                ),

                // User Context Text and Important Information when minimized.
                _buildMinimizedUserContextTextAndImportantInformation(),

                // Minimized button bar gesture detector. Only enabled when
                // we're nearly fully minimized.
                _buildMinimizedButtonBarGestureDetector(),
              ],
            ),
          );
          return now;
        },
      );

  Widget _buildUserImage() => new Stack(children: [
        // Shadow.
        new Opacity(
          opacity: _quickSettingsProgress,
          child: new Container(
            width: _userImageSize,
            height: _userImageSize,
            decoration: new BoxDecoration(
              boxShadow: kElevationToShadow[12],
              shape: BoxShape.circle,
            ),
          ),
        ),
        // The actual user image.
        new ClipOval(
          child: new GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (!_revealingQuickSettings) {
                showQuickSettings();
              } else {
                hideQuickSettings();
              }
            },
            child: new Container(
              width: _userImageSize,
              height: _userImageSize,
              foregroundDecoration: new BoxDecoration(
                border: new Border.all(
                  color: new Color(0xFFFFFFFF),
                  width: _userImageBorderWidth,
                ),
                shape: BoxShape.circle,
              ),
              child: _nowManager(context).user,
            ),
          ),
        ),
      ]);

  Widget _buildQuickSettings() => new Padding(
        padding: const EdgeInsets.symmetric(horizontal: 0.0, vertical: 8.0),
        child: new Container(
          height: _quickSettingsHeight,
          width: _quickSettingsBackgroundWidth,
          child: new ClipRect(
            child: new OverflowBox(
              // don't use parent height as constraint
              maxHeight: double.INFINITY,
              minHeight: 0.0,
              maxWidth: _quickSettingsBackgroundMaximizedWidth,
              minWidth: 0.0,
              child: new Opacity(
                opacity: _quickSettingsSlideUpProgress,
                child: new Center(
                  child: new Container(
                      key: _quickSettingsKey,
                      child: _nowManager(context).quickSettings),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _buildMinimizedUserContextTextAndImportantInformation() => new Align(
        alignment: FractionalOffset.bottomCenter,
        child: new Container(
          height: config.minHeight,
          padding: new EdgeInsets.symmetric(horizontal: 8.0 + _slideInDistance),
          child: new Opacity(
            opacity: 0.6 * _slideInProgress * _nowMinimizedInfoFader.opacity,
            child: new Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _nowManager(context).userContextMinimized,
                _nowManager(context).importantInfoMinimized,
              ],
            ),
          ),
        ),
      );

  Widget _buildMinimizedButtonBarGestureDetector() => new Offstage(
        offstage: _buttonTapDisabled,
        child: new GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: config.onBarVerticalDragUpdate,
          onVerticalDragEnd: config.onBarVerticalDragEnd,
          child: new Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              new Flexible(
                  child: new GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) {
                  _nowMinimizedInfoFader.fadeIn();
                },
              )),
              new GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: config.onReturnToOriginButtonTap,
                child: new Container(width: config.minHeight),
              ),
              new Flexible(
                  child: new GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) {
                  _nowMinimizedInfoFader.fadeIn();
                },
              )),
            ],
          ),
        ),
      );

  @override
  bool handleTick(double elapsedSeconds) {
    bool continueTicking = false;

    // Tick the minimized info simulation.
    _minimizedInfoSimulation.elapseTime(elapsedSeconds);
    if (!_minimizedInfoSimulation.isDone) {
      continueTicking = true;
    }

    // Tick the minimization simulation.
    if (!_minimizationSimulation.isDone) {
      _minimizationSimulation.elapseTime(elapsedSeconds);
      if (!_minimizationSimulation.isDone) {
        continueTicking = true;
      }
    }

    // Tick the quick settings simulation.
    if (!_quickSettingsSimulation.isDone) {
      _quickSettingsSimulation.elapseTime(elapsedSeconds);
      if (!_quickSettingsSimulation.isDone) {
        continueTicking = true;
      }
      if (config.onQuickSettingsProgressChange != null) {
        config.onQuickSettingsProgressChange(_quickSettingsProgress);
      }
      _nowManager(context, rebuildOnChange: false).quickSettingsProgress =
          _quickSettingsProgress;
      _nowManager(context, rebuildOnChange: false)
          .quickSettingsSlideUpProgress = _quickSettingsSlideUpProgress;
    }

    return continueTicking;
  }

  void minimize() {
    if (!_minimizing) {
      _minimizationSimulation.target = _kMinimizationSimulationTarget;
      _showMinimizedInfo();
      startTicking();
      config.onMinimize?.call();
    }
  }

  void maximize() {
    if (_minimizing) {
      _minimizationSimulation.target = 0.0;
      startTicking();
      config.onMaximize?.call();
    }
  }

  void showQuickSettings() {
    RenderBox renderBoxQuickSettings =
        _quickSettingsKey.currentContext.findRenderObject();
    _quickSettingsMaximizedHeight = renderBoxQuickSettings.size.height;
    RenderBox renderBoxImportantInfoMaximized =
        _importantInfoMaximizedKey.currentContext.findRenderObject();
    _importantInfoMaximizedHeight = renderBoxImportantInfoMaximized.size.height;

    if (!_revealingQuickSettings) {
      _quickSettingsSimulation.target = _kQuickSettingsSimulationTarget;
      startTicking();
      config.onQuickSettingsMaximized?.call();
    }
  }

  void hideQuickSettings() {
    if (_revealingQuickSettings) {
      _quickSettingsSimulation.target = 0.0;
      startTicking();
    }
  }

  void _showMinimizedInfo() {
    _nowMinimizedInfoFader.fadeIn(force: true);
    _minimizedInfoSimulation.target = _kMinimizationSimulationTarget;
    startTicking();
  }

  double get _quickSettingsProgress =>
      _quickSettingsSimulation.value / _kQuickSettingsSimulationTarget;

  double get _minimizationProgress =>
      _minimizationSimulation.value / _kMinimizationSimulationTarget;

  double get _minimizedInfoProgress =>
      _minimizedInfoSimulation.value / _kMinimizationSimulationTarget;

  bool get _minimizing =>
      _minimizationSimulation.target == _kMinimizationSimulationTarget;

  bool get _revealingQuickSettings =>
      _quickSettingsSimulation.target == _kQuickSettingsSimulationTarget;

  bool get _buttonTapDisabled =>
      _minimizationProgress < (1.0 - _kFallAwayDurationFraction);

  double get _nowHeight => math.max(
      config.minHeight,
      config.minHeight +
          ((config.maxHeight - config.minHeight) *
              (1.0 - _minimizationProgress)) +
          _quickSettingsRaiseDistance +
          _scrollOffsetDelta);

  double get _userImageSize => lerpDouble(56.0, 12.0, _minimizationProgress);

  double get _userImageBorderWidth =>
      lerpDouble(2.0, 6.0, _minimizationProgress);

  double get _userImageTopOffset =>
      lerpDouble(100.0, 20.0, _quickSettingsProgress) *
          (1.0 - _minimizationProgress) +
      ((config.minHeight - _userImageSize) / 2.0) * _minimizationProgress;

  double get _quickSettingsBackgroundTopOffset =>
      _userImageTopOffset + ((_userImageSize / 2.0) * _quickSettingsProgress);

  double get _quickSettingsBackgroundBorderRadius =>
      lerpDouble(50.0, 4.0, _quickSettingsProgress);

  double get _quickSettingsBackgroundMaximizedWidth =>
      _quickSettingsWidth - 2 * _kQuickSettingsHorizontalPadding;

  double get _quickSettingsBackgroundWidth =>
      _quickSettingsBackgroundMaximizedWidth *
      _quickSettingsProgress *
      (1.0 - _minimizationProgress);

  double get _quickSettingsBackgroundHeight {
    return lerpDouble(
        0.0,
        98.0 + // padding and space for user info
            _importantInfoMaximizedHeight +
            _quickSettingsHeight,
        _quickSettingsProgress * (1.0 - _minimizationProgress));
  }

  double get _quickSettingsHeight =>
      _quickSettingsProgress * _quickSettingsMaximizedHeight;

  double get _fallAwayOpacity => (1.0 - _fallAwayProgress).clamp(0.0, 1.0);

  double get _slideInDistance => lerpDouble(10.0, 0.0, _slideInProgress);

  double get _quickSettingsRaiseDistance =>
      config.quickSettingsHeightBump * _quickSettingsProgress;

  double get _scrollOffsetDelta =>
      (math.max(
                  -_kRestingDistanceAboveLowestPoint,
                  (-1.0 * _lastScrollOffset / 3.0) *
                      (1.0 - _minimizationProgress) *
                      (1.0 - _quickSettingsProgress)) *
              1000.0)
          .truncateToDouble() /
      1000.0;

  /// We fall away the context text and important information for the initial
  /// portion of the minimization animation as determined by
  /// [_kFallAwayDurationFraction].
  double get _fallAwayProgress =>
      math.min(1.0, (_minimizationProgress / _kFallAwayDurationFraction));

  /// We slide in the context text and important information for the final
  /// portion of the minimization animation as determined by
  /// [_kFallAwayDurationFraction].
  double get _slideInProgress =>
      ((((_minimizationProgress - (1.0 - _kFallAwayDurationFraction)) /
                  _kFallAwayDurationFraction)) *
              _minimizedInfoProgress)
          .clamp(0.0, 1.0);

  /// We slide up and fade in the quick settings for the final portion of the
  /// quick settings animation as determined by [_kFallAwayDurationFraction].
  double get _quickSettingsSlideUpProgress => math.max(
      0.0,
      ((_quickSettingsProgress - (1.0 - _kFallAwayDurationFraction)) /
          _kFallAwayDurationFraction));

  // Width of quick settings maximized info
  // (ie battery icon/desc | wifi icon/desc | network icon/desc)
  double get _importantInfoMaximizedWidth {
    double t = _quickSettingsProgress * (1.0 - _minimizationProgress);
    double minWidth = _nowManager(context).importantInfoMinWidth;
    return lerpDouble(minWidth, _quickSettingsBackgroundMaximizedWidth, t);
  }

  NowManager _nowManager(BuildContext context, {bool rebuildOnChange: true}) =>
      InheritedNowManager.of(context, rebuildOnChange: rebuildOnChange);
}
