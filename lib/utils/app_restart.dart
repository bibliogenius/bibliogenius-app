import 'dart:io' as io;

import 'package:flutter/foundation.dart';

/// Whether a change on disk needs the app closed before it takes effect. The
/// engine keeps global state in memory (database pool, identity, crypto
/// service) that cannot be swapped while it runs. The web build talks to a
/// server that keeps its own state, so there is nothing to close there.
bool get appRestartRequired => !kIsWeb;

/// Close the app so the next launch starts from what is on disk. This does not
/// relaunch the app: the user reopens it from its icon.
void closeAppForRestart() {
  if (kIsWeb) return;
  io.exit(0);
}
