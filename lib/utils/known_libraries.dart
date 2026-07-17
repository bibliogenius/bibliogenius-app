import '../models/contact.dart';

/// Selection logic for the "known libraries" section of the network screen
/// (ADR-054 Phase 1).
///
/// Account sync replicates the `contacts` table across a user's devices, but
/// P2P pairings (`peers` table) stay device-local by design (ADR-044). A
/// `type = 'Library'` contact replicated from another device therefore has no
/// matching peer here and would otherwise be rendered nowhere, which reads as
/// data loss. These helpers pick out those contacts so the UI can show them
/// honestly as "known, not paired on this device".
///
/// Matching is by name because name is the existing coupling convention
/// between `peers` and `contacts` (peer deletion deactivates Library contacts
/// by name match in the backend). A stable `library_uuid` link is ADR-054
/// Phase 3 work.
String normalizeLibraryName(String name) => name.trim().toLowerCase();

/// Builds the normalized-name set used as [selectUnpairedLibraryContacts]'s
/// `pairedNames` argument from the names already represented in the UI
/// (saved peers, hub follows, discovered mDNS peers).
Set<String> normalizedNameSet(Iterable<String> names) =>
    names.map(normalizeLibraryName).toSet();

/// Returns the active `Library` contacts whose name matches none of
/// [pairedNames], sorted by name. [pairedNames] must already be normalized
/// (see [normalizedNameSet]).
List<Contact> selectUnpairedLibraryContacts({
  required List<Contact> contacts,
  required Set<String> pairedNames,
}) {
  final result = contacts
      .where(
        (c) =>
            c.isActive &&
            c.type.toLowerCase() == 'library' &&
            !pairedNames.contains(normalizeLibraryName(c.name)),
      )
      .toList()
    ..sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  return result;
}
