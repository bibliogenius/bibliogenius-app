import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Re-bases a stored local cover path onto the CURRENT application-support
/// covers directory, keyed by the book's id.
///
/// iOS reassigns the app's data-container UUID across some updates, so an
/// absolute cover path persisted in the database
/// (e.g. `/var/mobile/Containers/Data/Application/<old-uuid>/.../covers/42.jpg`)
/// becomes unreadable after an update even though the file itself survives
/// under the new container. The database path is recomputed from
/// `getApplicationSupportDirectory()` every launch, which is why the library
/// survives an update while custom covers vanish: only the cover path was
/// frozen as an absolute string.
///
/// A device's own custom covers are always named `<bookId>.jpg` in `covers/`,
/// where `bookId` is the book's cross-device-stable uuid (see
/// `CoverCameraHelper`). We therefore re-base using the book's uuid, not the
/// stored basename. Guarding on `basename == '<bookId>.jpg'` rebases only this
/// device's own canonical cover; any foreign path is returned untouched (its
/// file is absent locally, so the caller shows a placeholder — never a wrong
/// cover). Because the uuid is globally unique, a cover synced from another
/// device can never be mapped onto an unrelated local cover.
///
/// On macOS/Android the support directory is keyed by a fixed bundle id, so
/// re-basing yields the identical path: no behavior change there.
///
/// Unlike [CoverUrlResolver] (intentionally stateless), this resolver caches
/// the covers directory because resolving it is async and must not run inside
/// a synchronous `build`. Call [init] once during platform startup.
class LocalCoverResolver {
  LocalCoverResolver._();

  static String? _coversDirPath;

  /// Resolves and caches the covers directory from the current
  /// application-support directory. Call once during platform initialization;
  /// idempotent and safe to call again.
  static Future<void> init() async {
    final appSupportDir = await getApplicationSupportDirectory();
    _coversDirPath = p.join(appSupportDir.path, 'covers');
  }

  @visibleForTesting
  static set coversDirPathForTest(String? value) => _coversDirPath = value;

  @visibleForTesting
  static void resetForTest() => _coversDirPath = null;

  /// Returns the effective on-disk path for a stored cover value.
  ///
  /// Non-local values (http(s) URLs, `/api/...` relative paths) and empty
  /// values are returned unchanged. A local cover path is re-based onto the
  /// current covers directory only when [bookId] is known, the covers
  /// directory is known, and the stored basename is exactly `<bookId>.jpg`
  /// (this device's own canonical cover). Every other value is returned
  /// untouched so a foreign device's path is never mapped onto a local cover.
  static String resolve(String storedPath, {String? bookId}) {
    if (storedPath.isEmpty) return storedPath;
    if (storedPath.startsWith('http') || storedPath.startsWith('/api')) {
      return storedPath;
    }

    final coversDir = _coversDirPath;
    if (coversDir == null || bookId == null) return storedPath;

    if (p.basename(storedPath) != '$bookId.jpg') return storedPath;

    return p.join(coversDir, '$bookId.jpg');
  }

  /// Returns the value to PERSIST in `books.cover_url` for [value].
  ///
  /// The counterpart of [resolve]. A cover the user has just captured is
  /// written to `{AppSupport}/covers/<bookId>.jpg`, and the capture helper
  /// hands the screen the absolute path it needs for its own preview and image
  /// cache eviction. That absolute prefix is device-specific and vestigial:
  /// every reader (this resolver, and `cover_url::rebase_local_cover_path` on
  /// the Rust side) rebuilds the directory from the current app-support path
  /// and keeps only the basename. Persisting the prefix therefore stores a
  /// device-specific string for a device-independent fact, which two devices
  /// holding the same book then overwrite in turn through field-level LWW, and
  /// which invites any consumer reading the column raw to treat it as a live
  /// filesystem path (ADR-044 Addendum A.4).
  ///
  /// The reduction is deliberately narrower than "keep the basename": a value
  /// is shortened ONLY when its basename is exactly `<bookId>.jpg`, which is
  /// precisely the set [resolve] knows how to rebuild. Everything else is
  /// returned untouched - remote URLs, `/api/...` peer paths, the
  /// `temp_<uuid>.jpg` file the add flow writes before the book has an id, and
  /// any path carried over from another device. Normalising can therefore
  /// never turn a resolvable reference into an unresolvable one.
  static String? normalizeForStorage(String? value, {required String? bookId}) {
    if (value == null || value.isEmpty) return value;
    if (bookId == null || bookId.isEmpty) return value;
    if (value.startsWith('http') || value.startsWith('/api')) return value;

    final canonical = '$bookId.jpg';
    if (p.basename(value) != canonical) return value;

    return canonical;
  }
}
