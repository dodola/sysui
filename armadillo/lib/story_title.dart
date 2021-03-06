// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

/// The title of a story.
class StoryTitle extends StatelessWidget {
  final String title;

  StoryTitle({this.title});

  @override
  Widget build(BuildContext context) => new Text(
        title.toUpperCase(),
        style: new TextStyle(
          fontSize: 11.0,
          color: new Color.fromARGB(160, 255, 255, 255),
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );
}
