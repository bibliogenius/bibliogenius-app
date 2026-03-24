import 'package:flutter/foundation.dart';

import '../models/book_note.dart';
import '../services/ffi_service.dart';

/// Maximum length for note content (must match Rust MAX_CONTENT_LENGTH).
const int maxNoteContentLength = 2000;

/// Provider managing reading notes for a single book at a time.
class BookNoteProvider extends ChangeNotifier {
  final FfiService _ffi = FfiService();

  List<BookNote> _notes = [];
  int? _currentBookId;
  bool _isLoading = false;
  String? _error;

  List<BookNote> get notes => _notes;
  int? get currentBookId => _currentBookId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Load all notes for the given book.
  Future<void> loadNotes(int bookId) async {
    _currentBookId = bookId;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final frbNotes = await _ffi.getBookNotes(bookId);
      _notes = frbNotes.map(BookNote.fromFrb).toList();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new note for the current book.
  Future<bool> createNote({required String content, int? page}) async {
    if (_currentBookId == null) return false;
    try {
      final frbNote = await _ffi.createBookNote(
        bookId: _currentBookId!,
        content: content,
        page: page,
      );
      _notes.insert(0, BookNote.fromFrb(frbNote));
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update an existing note.
  Future<bool> updateNote({
    required int id,
    required String content,
    int? page,
  }) async {
    try {
      final frbNote = await _ffi.updateBookNote(
        id: id,
        content: content,
        page: page,
      );
      final updated = BookNote.fromFrb(frbNote);
      final idx = _notes.indexWhere((n) => n.id == id);
      if (idx >= 0) {
        _notes[idx] = updated;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Delete a note by ID.
  Future<bool> deleteNote(int id) async {
    try {
      await _ffi.deleteBookNote(id);
      _notes.removeWhere((n) => n.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Clear state when navigating away.
  void clear() {
    _notes = [];
    _currentBookId = null;
    _isLoading = false;
    _error = null;
  }
}
