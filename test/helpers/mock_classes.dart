import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class MockAuthService extends AuthService {
  int? mockLibraryId = 1;
  bool shouldThrowOnGetLibraryId = false;

  @override
  Future<String?> getToken() async => 'mock_token';

  @override
  Future<int?> getLibraryId() async {
    if (shouldThrowOnGetLibraryId) {
      throw Exception('Mock AuthService error');
    }
    return mockLibraryId;
  }
}

class MockApiService extends ApiService {
  MockApiService() : super(MockAuthService(), baseUrl: 'http://mock');

  // Track calls
  final List<String> lookups = [];
  final List<Map<String, dynamic>> createdBooks = [];
  final List<Map<String, dynamic>> createdCopies = [];

  // Mock Data
  Book? existingBook;
  Map<String, dynamic>? lookupResult;
  List<Map<String, dynamic>> mockCopies = [];

  @override
  Future<Book?> findBookByIsbn(String isbn) async {
    lookups.add('findBookByIsbn:$isbn');
    return existingBook;
  }

  @override
  Future<Map<String, dynamic>?> lookupBook(
    String isbn, {
    Locale? locale,
  }) async {
    lookups.add('lookupBook:$isbn');
    return lookupResult;
  }

  @override
  Future<Response> createBook(Map<String, dynamic> bookData) async {
    createdBooks.add(Map<String, dynamic>.from(bookData));
    return Response(
      requestOptions: RequestOptions(path: '/api/books'),
      statusCode: 201,
      data: {'id': 123, 'title': bookData['title']},
    );
  }

  @override
  Future<void> addBookToCollection(String collectionId, int bookId) async {
    lookups.add('addBookToCollection:$collectionId:$bookId');
  }

  @override
  Future<Response> createCopy(Map<String, dynamic> copyData) async {
    createdCopies.add(Map<String, dynamic>.from(copyData));
    return Response(
      requestOptions: RequestOptions(path: '/api/copies'),
      statusCode: 201,
      data: {'copy': {'id': 456, ...copyData}, 'message': 'Copy created'},
    );
  }

  @override
  Future<Response> getBookCopies(int bookId) async {
    lookups.add('getBookCopies:$bookId');
    return Response(
      requestOptions: RequestOptions(path: '/api/books/$bookId/copies'),
      statusCode: 200,
      data: {'copies': mockCopies, 'total': mockCopies.length},
    );
  }
}

// Manual mock since we can't extend MobileScannerController easily (it involves ValueNotifiers etc)
// Actually we CAN extend it.
class MockMobileScannerController extends MobileScannerController {
  @override
  Future<void> toggleTorch() async {}

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> dispose() async {}
}
