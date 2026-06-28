import '../../models/contact.dart';

abstract class ContactRepository {
  Future<List<Contact>> getContacts({
    int? libraryId,
    String? type,
    String? bookIsbn,
  });

  /// Fetch a contact by its uuid (cross-device identity). [localId] feeds the
  /// dormant web HTTP leg only.
  Future<Contact> getContact(String uuid, {int? localId});

  /// Fetch a contact by its transitional integer local id. Bridges callers
  /// (loan references) that do not yet carry the uuid.
  Future<Contact> getContactByLocalId(int localId);

  Future<Contact> createContact(Map<String, dynamic> contactData);

  /// Update a contact by its integer local id (the FFI update is struct-based,
  /// addressed by the integer id until the wire flip adds a uuid variant).
  Future<Contact> updateContact(int localId, Map<String, dynamic> contactData);

  /// Delete a contact by its uuid (cross-device identity). [localId] feeds the
  /// dormant web HTTP leg only.
  Future<void> deleteContact(String uuid, {int? localId});
}
