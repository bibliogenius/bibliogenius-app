import 'dart:async';

import 'package:bibliogenius/services/online_services_consent.dart';

/// The provider suites in this directory drive the hub paths directly and
/// predate the online services consent (ADR-073). They run as an
/// installation that consented, so they keep testing what they tested; the
/// suites about the consent itself turn this back off in their setUp.
///
/// A new suite here therefore never meets the consent unless it sets
/// `debugAlwaysAllowed = false` itself.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  OnlineServicesConsent.debugAlwaysAllowed = true;
  await testMain();
}
