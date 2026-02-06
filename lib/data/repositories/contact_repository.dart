import '../../models/contact.dart';

abstract class ContactRepository {
  Future<List<Contact>> getContacts({int? libraryId, String? type});

  Future<Contact> getContact(int id);

  Future<Contact> createContact(Map<String, dynamic> contactData);

  Future<Contact> updateContact(int id, Map<String, dynamic> contactData);

  Future<void> deleteContact(int id);
}
