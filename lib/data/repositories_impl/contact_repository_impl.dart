import '../../models/contact.dart';
import '../../services/api_service.dart';
import '../repositories/contact_repository.dart';

class ContactRepositoryImpl implements ContactRepository {
  final ApiService _apiService;

  ContactRepositoryImpl(this._apiService);

  @override
  Future<List<Contact>> getContacts({int? libraryId, String? type}) async {
    final response = await _apiService.getContacts(
      libraryId: libraryId,
      type: type,
    );
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      if (data is Map && data['contacts'] is List) {
        return (data['contacts'] as List)
            .map((json) => Contact.fromJson(json as Map<String, dynamic>))
            .toList();
      }
    }
    return [];
  }

  @override
  Future<Contact> getContact(int id) async {
    final response = await _apiService.getContact(id);
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      if (data is Map && data['contact'] is Map) {
        return Contact.fromJson(data['contact'] as Map<String, dynamic>);
      }
    }
    throw Exception('Contact not found');
  }

  @override
  Future<Contact> createContact(Map<String, dynamic> contactData) async {
    final response = await _apiService.createContact(contactData);
    if (response.statusCode == 201 || response.statusCode == 200) {
      final data = response.data;
      if (data is Map && data['contact'] is Map) {
        return Contact.fromJson(data['contact'] as Map<String, dynamic>);
      }
    }
    throw Exception(
      'Failed to create contact (status: ${response.statusCode})',
    );
  }

  @override
  Future<Contact> updateContact(
    int id,
    Map<String, dynamic> contactData,
  ) async {
    final response = await _apiService.updateContact(id, contactData);
    if (response.statusCode == 200 && response.data != null) {
      final data = response.data;
      if (data is Map && data['contact'] is Map) {
        return Contact.fromJson(data['contact'] as Map<String, dynamic>);
      }
    }
    throw Exception(
      'Failed to update contact (status: ${response.statusCode})',
    );
  }

  @override
  Future<void> deleteContact(int id) async {
    final response = await _apiService.deleteContact(id);
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to delete contact (status: ${response.statusCode})',
      );
    }
  }
}
