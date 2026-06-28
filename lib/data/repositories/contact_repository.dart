import '../../models/contact.dart';

abstract class ContactRepository {
  Future<List<Contact>> getContacts({
    int? libraryId,
    String? type,
    String? bookIsbn,
  });

  /// Fetch a contact by its uuid (cross-device identity).
  Future<Contact> getContact(String uuid);

  Future<Contact> createContact(Map<String, dynamic> contactData);

  /// Update a contact by its uuid (cross-device identity).
  Future<Contact> updateContact(String uuid, Map<String, dynamic> contactData);

  /// Delete a contact by its uuid (cross-device identity).
  Future<void> deleteContact(String uuid);
}
