/// Development guard for a build whose `.env` names another hub than the
/// one the Rust core actually calls (the persisted relay URL wins, see
/// `set_hub_url_ffi`). While the two differ, every launch purges the hub
/// directory registration and retires the catalog key (ADR-072), so the
/// developer must hear about it in the Flutter console, not only in the
/// Rust log file.
library;

/// The warning to print, or null when `.env` and the effective hub agree.
/// Mirrors the Rust comparator: only a trailing slash is ignored.
String? hubUrlMismatchWarning({
  required String envHubUrl,
  required String? effectiveHubUrl,
}) {
  if (effectiveHubUrl == null) return null;
  String trimmed(String url) => url.replaceAll(RegExp(r'/+$'), '');
  if (trimmed(envHubUrl) == trimmed(effectiveHubUrl)) return null;
  return 'WARNING hub mismatch: .env HUB_URL is $envHubUrl but the app '
      'talks to $effectiveHubUrl (persisted relay). Each launch purges the '
      'directory registration and rotates the catalog key until both agree: '
      'set HUB_URL in .env to $effectiveHubUrl and rebuild, or switch the '
      'relay in Settings first.';
}

/// Print [hubUrlMismatchWarning] through [log]. A diagnostic must never
/// fail the startup path it runs in, so a failing read prints nothing.
void logHubUrlMismatch({
  required String envHubUrl,
  required String? Function() readEffectiveHubUrl,
  required void Function(String) log,
}) {
  try {
    final warning = hubUrlMismatchWarning(
      envHubUrl: envHubUrl,
      effectiveHubUrl: readEffectiveHubUrl(),
    );
    if (warning != null) log(warning);
  } catch (_) {}
}
