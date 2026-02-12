// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'frb.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FrbBook {

 int? get id; String get title; String? get author; String? get isbn; String? get summary; String? get publisher; int? get publicationYear; String? get coverUrl; String? get largeCoverUrl; String? get readingStatus; int? get shelfPosition; int? get userRating; String? get subjects; String? get createdAt; String? get updatedAt; String? get finishedReadingAt; String? get startedReadingAt; bool get owned; double? get price; List<String>? get digitalFormats;
/// Create a copy of FrbBook
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbBookCopyWith<FrbBook> get copyWith => _$FrbBookCopyWithImpl<FrbBook>(this as FrbBook, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbBook&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.isbn, isbn) || other.isbn == isbn)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.publisher, publisher) || other.publisher == publisher)&&(identical(other.publicationYear, publicationYear) || other.publicationYear == publicationYear)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.largeCoverUrl, largeCoverUrl) || other.largeCoverUrl == largeCoverUrl)&&(identical(other.readingStatus, readingStatus) || other.readingStatus == readingStatus)&&(identical(other.shelfPosition, shelfPosition) || other.shelfPosition == shelfPosition)&&(identical(other.userRating, userRating) || other.userRating == userRating)&&(identical(other.subjects, subjects) || other.subjects == subjects)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.finishedReadingAt, finishedReadingAt) || other.finishedReadingAt == finishedReadingAt)&&(identical(other.startedReadingAt, startedReadingAt) || other.startedReadingAt == startedReadingAt)&&(identical(other.owned, owned) || other.owned == owned)&&(identical(other.price, price) || other.price == price)&&const DeepCollectionEquality().equals(other.digitalFormats, digitalFormats));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,title,author,isbn,summary,publisher,publicationYear,coverUrl,largeCoverUrl,readingStatus,shelfPosition,userRating,subjects,createdAt,updatedAt,finishedReadingAt,startedReadingAt,owned,price,const DeepCollectionEquality().hash(digitalFormats)]);

@override
String toString() {
  return 'FrbBook(id: $id, title: $title, author: $author, isbn: $isbn, summary: $summary, publisher: $publisher, publicationYear: $publicationYear, coverUrl: $coverUrl, largeCoverUrl: $largeCoverUrl, readingStatus: $readingStatus, shelfPosition: $shelfPosition, userRating: $userRating, subjects: $subjects, createdAt: $createdAt, updatedAt: $updatedAt, finishedReadingAt: $finishedReadingAt, startedReadingAt: $startedReadingAt, owned: $owned, price: $price, digitalFormats: $digitalFormats)';
}


}

/// @nodoc
abstract mixin class $FrbBookCopyWith<$Res>  {
  factory $FrbBookCopyWith(FrbBook value, $Res Function(FrbBook) _then) = _$FrbBookCopyWithImpl;
@useResult
$Res call({
 int? id, String title, String? author, String? isbn, String? summary, String? publisher, int? publicationYear, String? coverUrl, String? largeCoverUrl, String? readingStatus, int? shelfPosition, int? userRating, String? subjects, String? createdAt, String? updatedAt, String? finishedReadingAt, String? startedReadingAt, bool owned, double? price, List<String>? digitalFormats
});




}
/// @nodoc
class _$FrbBookCopyWithImpl<$Res>
    implements $FrbBookCopyWith<$Res> {
  _$FrbBookCopyWithImpl(this._self, this._then);

  final FrbBook _self;
  final $Res Function(FrbBook) _then;

/// Create a copy of FrbBook
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? title = null,Object? author = freezed,Object? isbn = freezed,Object? summary = freezed,Object? publisher = freezed,Object? publicationYear = freezed,Object? coverUrl = freezed,Object? largeCoverUrl = freezed,Object? readingStatus = freezed,Object? shelfPosition = freezed,Object? userRating = freezed,Object? subjects = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,Object? finishedReadingAt = freezed,Object? startedReadingAt = freezed,Object? owned = null,Object? price = freezed,Object? digitalFormats = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,isbn: freezed == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,publisher: freezed == publisher ? _self.publisher : publisher // ignore: cast_nullable_to_non_nullable
as String?,publicationYear: freezed == publicationYear ? _self.publicationYear : publicationYear // ignore: cast_nullable_to_non_nullable
as int?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,largeCoverUrl: freezed == largeCoverUrl ? _self.largeCoverUrl : largeCoverUrl // ignore: cast_nullable_to_non_nullable
as String?,readingStatus: freezed == readingStatus ? _self.readingStatus : readingStatus // ignore: cast_nullable_to_non_nullable
as String?,shelfPosition: freezed == shelfPosition ? _self.shelfPosition : shelfPosition // ignore: cast_nullable_to_non_nullable
as int?,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,subjects: freezed == subjects ? _self.subjects : subjects // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,finishedReadingAt: freezed == finishedReadingAt ? _self.finishedReadingAt : finishedReadingAt // ignore: cast_nullable_to_non_nullable
as String?,startedReadingAt: freezed == startedReadingAt ? _self.startedReadingAt : startedReadingAt // ignore: cast_nullable_to_non_nullable
as String?,owned: null == owned ? _self.owned : owned // ignore: cast_nullable_to_non_nullable
as bool,price: freezed == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double?,digitalFormats: freezed == digitalFormats ? _self.digitalFormats : digitalFormats // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbBook].
extension FrbBookPatterns on FrbBook {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbBook value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbBook() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbBook value)  $default,){
final _that = this;
switch (_that) {
case _FrbBook():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbBook value)?  $default,){
final _that = this;
switch (_that) {
case _FrbBook() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String title,  String? author,  String? isbn,  String? summary,  String? publisher,  int? publicationYear,  String? coverUrl,  String? largeCoverUrl,  String? readingStatus,  int? shelfPosition,  int? userRating,  String? subjects,  String? createdAt,  String? updatedAt,  String? finishedReadingAt,  String? startedReadingAt,  bool owned,  double? price,  List<String>? digitalFormats)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbBook() when $default != null:
return $default(_that.id,_that.title,_that.author,_that.isbn,_that.summary,_that.publisher,_that.publicationYear,_that.coverUrl,_that.largeCoverUrl,_that.readingStatus,_that.shelfPosition,_that.userRating,_that.subjects,_that.createdAt,_that.updatedAt,_that.finishedReadingAt,_that.startedReadingAt,_that.owned,_that.price,_that.digitalFormats);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String title,  String? author,  String? isbn,  String? summary,  String? publisher,  int? publicationYear,  String? coverUrl,  String? largeCoverUrl,  String? readingStatus,  int? shelfPosition,  int? userRating,  String? subjects,  String? createdAt,  String? updatedAt,  String? finishedReadingAt,  String? startedReadingAt,  bool owned,  double? price,  List<String>? digitalFormats)  $default,) {final _that = this;
switch (_that) {
case _FrbBook():
return $default(_that.id,_that.title,_that.author,_that.isbn,_that.summary,_that.publisher,_that.publicationYear,_that.coverUrl,_that.largeCoverUrl,_that.readingStatus,_that.shelfPosition,_that.userRating,_that.subjects,_that.createdAt,_that.updatedAt,_that.finishedReadingAt,_that.startedReadingAt,_that.owned,_that.price,_that.digitalFormats);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String title,  String? author,  String? isbn,  String? summary,  String? publisher,  int? publicationYear,  String? coverUrl,  String? largeCoverUrl,  String? readingStatus,  int? shelfPosition,  int? userRating,  String? subjects,  String? createdAt,  String? updatedAt,  String? finishedReadingAt,  String? startedReadingAt,  bool owned,  double? price,  List<String>? digitalFormats)?  $default,) {final _that = this;
switch (_that) {
case _FrbBook() when $default != null:
return $default(_that.id,_that.title,_that.author,_that.isbn,_that.summary,_that.publisher,_that.publicationYear,_that.coverUrl,_that.largeCoverUrl,_that.readingStatus,_that.shelfPosition,_that.userRating,_that.subjects,_that.createdAt,_that.updatedAt,_that.finishedReadingAt,_that.startedReadingAt,_that.owned,_that.price,_that.digitalFormats);case _:
  return null;

}
}

}

/// @nodoc


class _FrbBook implements FrbBook {
  const _FrbBook({this.id, required this.title, this.author, this.isbn, this.summary, this.publisher, this.publicationYear, this.coverUrl, this.largeCoverUrl, this.readingStatus, this.shelfPosition, this.userRating, this.subjects, this.createdAt, this.updatedAt, this.finishedReadingAt, this.startedReadingAt, required this.owned, this.price, final  List<String>? digitalFormats}): _digitalFormats = digitalFormats;
  

@override final  int? id;
@override final  String title;
@override final  String? author;
@override final  String? isbn;
@override final  String? summary;
@override final  String? publisher;
@override final  int? publicationYear;
@override final  String? coverUrl;
@override final  String? largeCoverUrl;
@override final  String? readingStatus;
@override final  int? shelfPosition;
@override final  int? userRating;
@override final  String? subjects;
@override final  String? createdAt;
@override final  String? updatedAt;
@override final  String? finishedReadingAt;
@override final  String? startedReadingAt;
@override final  bool owned;
@override final  double? price;
 final  List<String>? _digitalFormats;
@override List<String>? get digitalFormats {
  final value = _digitalFormats;
  if (value == null) return null;
  if (_digitalFormats is EqualUnmodifiableListView) return _digitalFormats;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of FrbBook
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbBookCopyWith<_FrbBook> get copyWith => __$FrbBookCopyWithImpl<_FrbBook>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbBook&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.isbn, isbn) || other.isbn == isbn)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.publisher, publisher) || other.publisher == publisher)&&(identical(other.publicationYear, publicationYear) || other.publicationYear == publicationYear)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.largeCoverUrl, largeCoverUrl) || other.largeCoverUrl == largeCoverUrl)&&(identical(other.readingStatus, readingStatus) || other.readingStatus == readingStatus)&&(identical(other.shelfPosition, shelfPosition) || other.shelfPosition == shelfPosition)&&(identical(other.userRating, userRating) || other.userRating == userRating)&&(identical(other.subjects, subjects) || other.subjects == subjects)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.finishedReadingAt, finishedReadingAt) || other.finishedReadingAt == finishedReadingAt)&&(identical(other.startedReadingAt, startedReadingAt) || other.startedReadingAt == startedReadingAt)&&(identical(other.owned, owned) || other.owned == owned)&&(identical(other.price, price) || other.price == price)&&const DeepCollectionEquality().equals(other._digitalFormats, _digitalFormats));
}


@override
int get hashCode => Object.hashAll([runtimeType,id,title,author,isbn,summary,publisher,publicationYear,coverUrl,largeCoverUrl,readingStatus,shelfPosition,userRating,subjects,createdAt,updatedAt,finishedReadingAt,startedReadingAt,owned,price,const DeepCollectionEquality().hash(_digitalFormats)]);

@override
String toString() {
  return 'FrbBook(id: $id, title: $title, author: $author, isbn: $isbn, summary: $summary, publisher: $publisher, publicationYear: $publicationYear, coverUrl: $coverUrl, largeCoverUrl: $largeCoverUrl, readingStatus: $readingStatus, shelfPosition: $shelfPosition, userRating: $userRating, subjects: $subjects, createdAt: $createdAt, updatedAt: $updatedAt, finishedReadingAt: $finishedReadingAt, startedReadingAt: $startedReadingAt, owned: $owned, price: $price, digitalFormats: $digitalFormats)';
}


}

/// @nodoc
abstract mixin class _$FrbBookCopyWith<$Res> implements $FrbBookCopyWith<$Res> {
  factory _$FrbBookCopyWith(_FrbBook value, $Res Function(_FrbBook) _then) = __$FrbBookCopyWithImpl;
@override @useResult
$Res call({
 int? id, String title, String? author, String? isbn, String? summary, String? publisher, int? publicationYear, String? coverUrl, String? largeCoverUrl, String? readingStatus, int? shelfPosition, int? userRating, String? subjects, String? createdAt, String? updatedAt, String? finishedReadingAt, String? startedReadingAt, bool owned, double? price, List<String>? digitalFormats
});




}
/// @nodoc
class __$FrbBookCopyWithImpl<$Res>
    implements _$FrbBookCopyWith<$Res> {
  __$FrbBookCopyWithImpl(this._self, this._then);

  final _FrbBook _self;
  final $Res Function(_FrbBook) _then;

/// Create a copy of FrbBook
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? title = null,Object? author = freezed,Object? isbn = freezed,Object? summary = freezed,Object? publisher = freezed,Object? publicationYear = freezed,Object? coverUrl = freezed,Object? largeCoverUrl = freezed,Object? readingStatus = freezed,Object? shelfPosition = freezed,Object? userRating = freezed,Object? subjects = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,Object? finishedReadingAt = freezed,Object? startedReadingAt = freezed,Object? owned = null,Object? price = freezed,Object? digitalFormats = freezed,}) {
  return _then(_FrbBook(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,isbn: freezed == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,publisher: freezed == publisher ? _self.publisher : publisher // ignore: cast_nullable_to_non_nullable
as String?,publicationYear: freezed == publicationYear ? _self.publicationYear : publicationYear // ignore: cast_nullable_to_non_nullable
as int?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,largeCoverUrl: freezed == largeCoverUrl ? _self.largeCoverUrl : largeCoverUrl // ignore: cast_nullable_to_non_nullable
as String?,readingStatus: freezed == readingStatus ? _self.readingStatus : readingStatus // ignore: cast_nullable_to_non_nullable
as String?,shelfPosition: freezed == shelfPosition ? _self.shelfPosition : shelfPosition // ignore: cast_nullable_to_non_nullable
as int?,userRating: freezed == userRating ? _self.userRating : userRating // ignore: cast_nullable_to_non_nullable
as int?,subjects: freezed == subjects ? _self.subjects : subjects // ignore: cast_nullable_to_non_nullable
as String?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String?,finishedReadingAt: freezed == finishedReadingAt ? _self.finishedReadingAt : finishedReadingAt // ignore: cast_nullable_to_non_nullable
as String?,startedReadingAt: freezed == startedReadingAt ? _self.startedReadingAt : startedReadingAt // ignore: cast_nullable_to_non_nullable
as String?,owned: null == owned ? _self.owned : owned // ignore: cast_nullable_to_non_nullable
as bool,price: freezed == price ? _self.price : price // ignore: cast_nullable_to_non_nullable
as double?,digitalFormats: freezed == digitalFormats ? _self._digitalFormats : digitalFormats // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}


}

/// @nodoc
mixin _$FrbBookMetadata {

 String? get title; String? get author; String? get publisher; String? get publicationYear; String? get coverUrl; String? get summary;
/// Create a copy of FrbBookMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbBookMetadataCopyWith<FrbBookMetadata> get copyWith => _$FrbBookMetadataCopyWithImpl<FrbBookMetadata>(this as FrbBookMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbBookMetadata&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.publisher, publisher) || other.publisher == publisher)&&(identical(other.publicationYear, publicationYear) || other.publicationYear == publicationYear)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode => Object.hash(runtimeType,title,author,publisher,publicationYear,coverUrl,summary);

@override
String toString() {
  return 'FrbBookMetadata(title: $title, author: $author, publisher: $publisher, publicationYear: $publicationYear, coverUrl: $coverUrl, summary: $summary)';
}


}

/// @nodoc
abstract mixin class $FrbBookMetadataCopyWith<$Res>  {
  factory $FrbBookMetadataCopyWith(FrbBookMetadata value, $Res Function(FrbBookMetadata) _then) = _$FrbBookMetadataCopyWithImpl;
@useResult
$Res call({
 String? title, String? author, String? publisher, String? publicationYear, String? coverUrl, String? summary
});




}
/// @nodoc
class _$FrbBookMetadataCopyWithImpl<$Res>
    implements $FrbBookMetadataCopyWith<$Res> {
  _$FrbBookMetadataCopyWithImpl(this._self, this._then);

  final FrbBookMetadata _self;
  final $Res Function(FrbBookMetadata) _then;

/// Create a copy of FrbBookMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? title = freezed,Object? author = freezed,Object? publisher = freezed,Object? publicationYear = freezed,Object? coverUrl = freezed,Object? summary = freezed,}) {
  return _then(_self.copyWith(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,publisher: freezed == publisher ? _self.publisher : publisher // ignore: cast_nullable_to_non_nullable
as String?,publicationYear: freezed == publicationYear ? _self.publicationYear : publicationYear // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbBookMetadata].
extension FrbBookMetadataPatterns on FrbBookMetadata {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbBookMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbBookMetadata() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbBookMetadata value)  $default,){
final _that = this;
switch (_that) {
case _FrbBookMetadata():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbBookMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _FrbBookMetadata() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String? title,  String? author,  String? publisher,  String? publicationYear,  String? coverUrl,  String? summary)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbBookMetadata() when $default != null:
return $default(_that.title,_that.author,_that.publisher,_that.publicationYear,_that.coverUrl,_that.summary);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String? title,  String? author,  String? publisher,  String? publicationYear,  String? coverUrl,  String? summary)  $default,) {final _that = this;
switch (_that) {
case _FrbBookMetadata():
return $default(_that.title,_that.author,_that.publisher,_that.publicationYear,_that.coverUrl,_that.summary);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String? title,  String? author,  String? publisher,  String? publicationYear,  String? coverUrl,  String? summary)?  $default,) {final _that = this;
switch (_that) {
case _FrbBookMetadata() when $default != null:
return $default(_that.title,_that.author,_that.publisher,_that.publicationYear,_that.coverUrl,_that.summary);case _:
  return null;

}
}

}

/// @nodoc


class _FrbBookMetadata implements FrbBookMetadata {
  const _FrbBookMetadata({this.title, this.author, this.publisher, this.publicationYear, this.coverUrl, this.summary});
  

@override final  String? title;
@override final  String? author;
@override final  String? publisher;
@override final  String? publicationYear;
@override final  String? coverUrl;
@override final  String? summary;

/// Create a copy of FrbBookMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbBookMetadataCopyWith<_FrbBookMetadata> get copyWith => __$FrbBookMetadataCopyWithImpl<_FrbBookMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbBookMetadata&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.publisher, publisher) || other.publisher == publisher)&&(identical(other.publicationYear, publicationYear) || other.publicationYear == publicationYear)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode => Object.hash(runtimeType,title,author,publisher,publicationYear,coverUrl,summary);

@override
String toString() {
  return 'FrbBookMetadata(title: $title, author: $author, publisher: $publisher, publicationYear: $publicationYear, coverUrl: $coverUrl, summary: $summary)';
}


}

/// @nodoc
abstract mixin class _$FrbBookMetadataCopyWith<$Res> implements $FrbBookMetadataCopyWith<$Res> {
  factory _$FrbBookMetadataCopyWith(_FrbBookMetadata value, $Res Function(_FrbBookMetadata) _then) = __$FrbBookMetadataCopyWithImpl;
@override @useResult
$Res call({
 String? title, String? author, String? publisher, String? publicationYear, String? coverUrl, String? summary
});




}
/// @nodoc
class __$FrbBookMetadataCopyWithImpl<$Res>
    implements _$FrbBookMetadataCopyWith<$Res> {
  __$FrbBookMetadataCopyWithImpl(this._self, this._then);

  final _FrbBookMetadata _self;
  final $Res Function(_FrbBookMetadata) _then;

/// Create a copy of FrbBookMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? title = freezed,Object? author = freezed,Object? publisher = freezed,Object? publicationYear = freezed,Object? coverUrl = freezed,Object? summary = freezed,}) {
  return _then(_FrbBookMetadata(
title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,publisher: freezed == publisher ? _self.publisher : publisher // ignore: cast_nullable_to_non_nullable
as String?,publicationYear: freezed == publicationYear ? _self.publicationYear : publicationYear // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$FrbContact {

 int? get id; String get contactType; String get name; String? get firstName; String? get email; String? get phone; String? get address; String? get streetAddress; String? get postalCode; String? get city; String? get country; double? get latitude; double? get longitude; String? get notes; int? get userId; int? get libraryOwnerId; bool get isActive;
/// Create a copy of FrbContact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbContactCopyWith<FrbContact> get copyWith => _$FrbContactCopyWithImpl<FrbContact>(this as FrbContact, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbContact&&(identical(other.id, id) || other.id == id)&&(identical(other.contactType, contactType) || other.contactType == contactType)&&(identical(other.name, name) || other.name == name)&&(identical(other.firstName, firstName) || other.firstName == firstName)&&(identical(other.email, email) || other.email == email)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.address, address) || other.address == address)&&(identical(other.streetAddress, streetAddress) || other.streetAddress == streetAddress)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode)&&(identical(other.city, city) || other.city == city)&&(identical(other.country, country) || other.country == country)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.libraryOwnerId, libraryOwnerId) || other.libraryOwnerId == libraryOwnerId)&&(identical(other.isActive, isActive) || other.isActive == isActive));
}


@override
int get hashCode => Object.hash(runtimeType,id,contactType,name,firstName,email,phone,address,streetAddress,postalCode,city,country,latitude,longitude,notes,userId,libraryOwnerId,isActive);

@override
String toString() {
  return 'FrbContact(id: $id, contactType: $contactType, name: $name, firstName: $firstName, email: $email, phone: $phone, address: $address, streetAddress: $streetAddress, postalCode: $postalCode, city: $city, country: $country, latitude: $latitude, longitude: $longitude, notes: $notes, userId: $userId, libraryOwnerId: $libraryOwnerId, isActive: $isActive)';
}


}

/// @nodoc
abstract mixin class $FrbContactCopyWith<$Res>  {
  factory $FrbContactCopyWith(FrbContact value, $Res Function(FrbContact) _then) = _$FrbContactCopyWithImpl;
@useResult
$Res call({
 int? id, String contactType, String name, String? firstName, String? email, String? phone, String? address, String? streetAddress, String? postalCode, String? city, String? country, double? latitude, double? longitude, String? notes, int? userId, int? libraryOwnerId, bool isActive
});




}
/// @nodoc
class _$FrbContactCopyWithImpl<$Res>
    implements $FrbContactCopyWith<$Res> {
  _$FrbContactCopyWithImpl(this._self, this._then);

  final FrbContact _self;
  final $Res Function(FrbContact) _then;

/// Create a copy of FrbContact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? contactType = null,Object? name = null,Object? firstName = freezed,Object? email = freezed,Object? phone = freezed,Object? address = freezed,Object? streetAddress = freezed,Object? postalCode = freezed,Object? city = freezed,Object? country = freezed,Object? latitude = freezed,Object? longitude = freezed,Object? notes = freezed,Object? userId = freezed,Object? libraryOwnerId = freezed,Object? isActive = null,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,contactType: null == contactType ? _self.contactType : contactType // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,firstName: freezed == firstName ? _self.firstName : firstName // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,streetAddress: freezed == streetAddress ? _self.streetAddress : streetAddress // ignore: cast_nullable_to_non_nullable
as String?,postalCode: freezed == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String?,city: freezed == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String?,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,latitude: freezed == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double?,longitude: freezed == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int?,libraryOwnerId: freezed == libraryOwnerId ? _self.libraryOwnerId : libraryOwnerId // ignore: cast_nullable_to_non_nullable
as int?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbContact].
extension FrbContactPatterns on FrbContact {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbContact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbContact() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbContact value)  $default,){
final _that = this;
switch (_that) {
case _FrbContact():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbContact value)?  $default,){
final _that = this;
switch (_that) {
case _FrbContact() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String contactType,  String name,  String? firstName,  String? email,  String? phone,  String? address,  String? streetAddress,  String? postalCode,  String? city,  String? country,  double? latitude,  double? longitude,  String? notes,  int? userId,  int? libraryOwnerId,  bool isActive)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbContact() when $default != null:
return $default(_that.id,_that.contactType,_that.name,_that.firstName,_that.email,_that.phone,_that.address,_that.streetAddress,_that.postalCode,_that.city,_that.country,_that.latitude,_that.longitude,_that.notes,_that.userId,_that.libraryOwnerId,_that.isActive);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String contactType,  String name,  String? firstName,  String? email,  String? phone,  String? address,  String? streetAddress,  String? postalCode,  String? city,  String? country,  double? latitude,  double? longitude,  String? notes,  int? userId,  int? libraryOwnerId,  bool isActive)  $default,) {final _that = this;
switch (_that) {
case _FrbContact():
return $default(_that.id,_that.contactType,_that.name,_that.firstName,_that.email,_that.phone,_that.address,_that.streetAddress,_that.postalCode,_that.city,_that.country,_that.latitude,_that.longitude,_that.notes,_that.userId,_that.libraryOwnerId,_that.isActive);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String contactType,  String name,  String? firstName,  String? email,  String? phone,  String? address,  String? streetAddress,  String? postalCode,  String? city,  String? country,  double? latitude,  double? longitude,  String? notes,  int? userId,  int? libraryOwnerId,  bool isActive)?  $default,) {final _that = this;
switch (_that) {
case _FrbContact() when $default != null:
return $default(_that.id,_that.contactType,_that.name,_that.firstName,_that.email,_that.phone,_that.address,_that.streetAddress,_that.postalCode,_that.city,_that.country,_that.latitude,_that.longitude,_that.notes,_that.userId,_that.libraryOwnerId,_that.isActive);case _:
  return null;

}
}

}

/// @nodoc


class _FrbContact implements FrbContact {
  const _FrbContact({this.id, required this.contactType, required this.name, this.firstName, this.email, this.phone, this.address, this.streetAddress, this.postalCode, this.city, this.country, this.latitude, this.longitude, this.notes, this.userId, this.libraryOwnerId, required this.isActive});
  

@override final  int? id;
@override final  String contactType;
@override final  String name;
@override final  String? firstName;
@override final  String? email;
@override final  String? phone;
@override final  String? address;
@override final  String? streetAddress;
@override final  String? postalCode;
@override final  String? city;
@override final  String? country;
@override final  double? latitude;
@override final  double? longitude;
@override final  String? notes;
@override final  int? userId;
@override final  int? libraryOwnerId;
@override final  bool isActive;

/// Create a copy of FrbContact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbContactCopyWith<_FrbContact> get copyWith => __$FrbContactCopyWithImpl<_FrbContact>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbContact&&(identical(other.id, id) || other.id == id)&&(identical(other.contactType, contactType) || other.contactType == contactType)&&(identical(other.name, name) || other.name == name)&&(identical(other.firstName, firstName) || other.firstName == firstName)&&(identical(other.email, email) || other.email == email)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.address, address) || other.address == address)&&(identical(other.streetAddress, streetAddress) || other.streetAddress == streetAddress)&&(identical(other.postalCode, postalCode) || other.postalCode == postalCode)&&(identical(other.city, city) || other.city == city)&&(identical(other.country, country) || other.country == country)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.libraryOwnerId, libraryOwnerId) || other.libraryOwnerId == libraryOwnerId)&&(identical(other.isActive, isActive) || other.isActive == isActive));
}


@override
int get hashCode => Object.hash(runtimeType,id,contactType,name,firstName,email,phone,address,streetAddress,postalCode,city,country,latitude,longitude,notes,userId,libraryOwnerId,isActive);

@override
String toString() {
  return 'FrbContact(id: $id, contactType: $contactType, name: $name, firstName: $firstName, email: $email, phone: $phone, address: $address, streetAddress: $streetAddress, postalCode: $postalCode, city: $city, country: $country, latitude: $latitude, longitude: $longitude, notes: $notes, userId: $userId, libraryOwnerId: $libraryOwnerId, isActive: $isActive)';
}


}

/// @nodoc
abstract mixin class _$FrbContactCopyWith<$Res> implements $FrbContactCopyWith<$Res> {
  factory _$FrbContactCopyWith(_FrbContact value, $Res Function(_FrbContact) _then) = __$FrbContactCopyWithImpl;
@override @useResult
$Res call({
 int? id, String contactType, String name, String? firstName, String? email, String? phone, String? address, String? streetAddress, String? postalCode, String? city, String? country, double? latitude, double? longitude, String? notes, int? userId, int? libraryOwnerId, bool isActive
});




}
/// @nodoc
class __$FrbContactCopyWithImpl<$Res>
    implements _$FrbContactCopyWith<$Res> {
  __$FrbContactCopyWithImpl(this._self, this._then);

  final _FrbContact _self;
  final $Res Function(_FrbContact) _then;

/// Create a copy of FrbContact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? contactType = null,Object? name = null,Object? firstName = freezed,Object? email = freezed,Object? phone = freezed,Object? address = freezed,Object? streetAddress = freezed,Object? postalCode = freezed,Object? city = freezed,Object? country = freezed,Object? latitude = freezed,Object? longitude = freezed,Object? notes = freezed,Object? userId = freezed,Object? libraryOwnerId = freezed,Object? isActive = null,}) {
  return _then(_FrbContact(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,contactType: null == contactType ? _self.contactType : contactType // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,firstName: freezed == firstName ? _self.firstName : firstName // ignore: cast_nullable_to_non_nullable
as String?,email: freezed == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String?,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,address: freezed == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String?,streetAddress: freezed == streetAddress ? _self.streetAddress : streetAddress // ignore: cast_nullable_to_non_nullable
as String?,postalCode: freezed == postalCode ? _self.postalCode : postalCode // ignore: cast_nullable_to_non_nullable
as String?,city: freezed == city ? _self.city : city // ignore: cast_nullable_to_non_nullable
as String?,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,latitude: freezed == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double?,longitude: freezed == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double?,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,userId: freezed == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as int?,libraryOwnerId: freezed == libraryOwnerId ? _self.libraryOwnerId : libraryOwnerId // ignore: cast_nullable_to_non_nullable
as int?,isActive: null == isActive ? _self.isActive : isActive // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$FrbCoverCandidate {

 String get url; String get source;
/// Create a copy of FrbCoverCandidate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbCoverCandidateCopyWith<FrbCoverCandidate> get copyWith => _$FrbCoverCandidateCopyWithImpl<FrbCoverCandidate>(this as FrbCoverCandidate, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbCoverCandidate&&(identical(other.url, url) || other.url == url)&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode => Object.hash(runtimeType,url,source);

@override
String toString() {
  return 'FrbCoverCandidate(url: $url, source: $source)';
}


}

/// @nodoc
abstract mixin class $FrbCoverCandidateCopyWith<$Res>  {
  factory $FrbCoverCandidateCopyWith(FrbCoverCandidate value, $Res Function(FrbCoverCandidate) _then) = _$FrbCoverCandidateCopyWithImpl;
@useResult
$Res call({
 String url, String source
});




}
/// @nodoc
class _$FrbCoverCandidateCopyWithImpl<$Res>
    implements $FrbCoverCandidateCopyWith<$Res> {
  _$FrbCoverCandidateCopyWithImpl(this._self, this._then);

  final FrbCoverCandidate _self;
  final $Res Function(FrbCoverCandidate) _then;

/// Create a copy of FrbCoverCandidate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? source = null,}) {
  return _then(_self.copyWith(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbCoverCandidate].
extension FrbCoverCandidatePatterns on FrbCoverCandidate {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbCoverCandidate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbCoverCandidate() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbCoverCandidate value)  $default,){
final _that = this;
switch (_that) {
case _FrbCoverCandidate():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbCoverCandidate value)?  $default,){
final _that = this;
switch (_that) {
case _FrbCoverCandidate() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String url,  String source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbCoverCandidate() when $default != null:
return $default(_that.url,_that.source);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String url,  String source)  $default,) {final _that = this;
switch (_that) {
case _FrbCoverCandidate():
return $default(_that.url,_that.source);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String url,  String source)?  $default,) {final _that = this;
switch (_that) {
case _FrbCoverCandidate() when $default != null:
return $default(_that.url,_that.source);case _:
  return null;

}
}

}

/// @nodoc


class _FrbCoverCandidate implements FrbCoverCandidate {
  const _FrbCoverCandidate({required this.url, required this.source});
  

@override final  String url;
@override final  String source;

/// Create a copy of FrbCoverCandidate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbCoverCandidateCopyWith<_FrbCoverCandidate> get copyWith => __$FrbCoverCandidateCopyWithImpl<_FrbCoverCandidate>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbCoverCandidate&&(identical(other.url, url) || other.url == url)&&(identical(other.source, source) || other.source == source));
}


@override
int get hashCode => Object.hash(runtimeType,url,source);

@override
String toString() {
  return 'FrbCoverCandidate(url: $url, source: $source)';
}


}

/// @nodoc
abstract mixin class _$FrbCoverCandidateCopyWith<$Res> implements $FrbCoverCandidateCopyWith<$Res> {
  factory _$FrbCoverCandidateCopyWith(_FrbCoverCandidate value, $Res Function(_FrbCoverCandidate) _then) = __$FrbCoverCandidateCopyWithImpl;
@override @useResult
$Res call({
 String url, String source
});




}
/// @nodoc
class __$FrbCoverCandidateCopyWithImpl<$Res>
    implements _$FrbCoverCandidateCopyWith<$Res> {
  __$FrbCoverCandidateCopyWithImpl(this._self, this._then);

  final _FrbCoverCandidate _self;
  final $Res Function(_FrbCoverCandidate) _then;

/// Create a copy of FrbCoverCandidate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? source = null,}) {
  return _then(_FrbCoverCandidate(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FrbDiscoveredPeer {

 String get name; String get host; int get port; List<String> get addresses; String? get libraryId; String get discoveredAt;
/// Create a copy of FrbDiscoveredPeer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbDiscoveredPeerCopyWith<FrbDiscoveredPeer> get copyWith => _$FrbDiscoveredPeerCopyWithImpl<FrbDiscoveredPeer>(this as FrbDiscoveredPeer, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbDiscoveredPeer&&(identical(other.name, name) || other.name == name)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&const DeepCollectionEquality().equals(other.addresses, addresses)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.discoveredAt, discoveredAt) || other.discoveredAt == discoveredAt));
}


@override
int get hashCode => Object.hash(runtimeType,name,host,port,const DeepCollectionEquality().hash(addresses),libraryId,discoveredAt);

@override
String toString() {
  return 'FrbDiscoveredPeer(name: $name, host: $host, port: $port, addresses: $addresses, libraryId: $libraryId, discoveredAt: $discoveredAt)';
}


}

/// @nodoc
abstract mixin class $FrbDiscoveredPeerCopyWith<$Res>  {
  factory $FrbDiscoveredPeerCopyWith(FrbDiscoveredPeer value, $Res Function(FrbDiscoveredPeer) _then) = _$FrbDiscoveredPeerCopyWithImpl;
@useResult
$Res call({
 String name, String host, int port, List<String> addresses, String? libraryId, String discoveredAt
});




}
/// @nodoc
class _$FrbDiscoveredPeerCopyWithImpl<$Res>
    implements $FrbDiscoveredPeerCopyWith<$Res> {
  _$FrbDiscoveredPeerCopyWithImpl(this._self, this._then);

  final FrbDiscoveredPeer _self;
  final $Res Function(FrbDiscoveredPeer) _then;

/// Create a copy of FrbDiscoveredPeer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? host = null,Object? port = null,Object? addresses = null,Object? libraryId = freezed,Object? discoveredAt = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,addresses: null == addresses ? _self.addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<String>,libraryId: freezed == libraryId ? _self.libraryId : libraryId // ignore: cast_nullable_to_non_nullable
as String?,discoveredAt: null == discoveredAt ? _self.discoveredAt : discoveredAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbDiscoveredPeer].
extension FrbDiscoveredPeerPatterns on FrbDiscoveredPeer {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbDiscoveredPeer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbDiscoveredPeer() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbDiscoveredPeer value)  $default,){
final _that = this;
switch (_that) {
case _FrbDiscoveredPeer():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbDiscoveredPeer value)?  $default,){
final _that = this;
switch (_that) {
case _FrbDiscoveredPeer() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String host,  int port,  List<String> addresses,  String? libraryId,  String discoveredAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbDiscoveredPeer() when $default != null:
return $default(_that.name,_that.host,_that.port,_that.addresses,_that.libraryId,_that.discoveredAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String host,  int port,  List<String> addresses,  String? libraryId,  String discoveredAt)  $default,) {final _that = this;
switch (_that) {
case _FrbDiscoveredPeer():
return $default(_that.name,_that.host,_that.port,_that.addresses,_that.libraryId,_that.discoveredAt);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String host,  int port,  List<String> addresses,  String? libraryId,  String discoveredAt)?  $default,) {final _that = this;
switch (_that) {
case _FrbDiscoveredPeer() when $default != null:
return $default(_that.name,_that.host,_that.port,_that.addresses,_that.libraryId,_that.discoveredAt);case _:
  return null;

}
}

}

/// @nodoc


class _FrbDiscoveredPeer implements FrbDiscoveredPeer {
  const _FrbDiscoveredPeer({required this.name, required this.host, required this.port, required final  List<String> addresses, this.libraryId, required this.discoveredAt}): _addresses = addresses;
  

@override final  String name;
@override final  String host;
@override final  int port;
 final  List<String> _addresses;
@override List<String> get addresses {
  if (_addresses is EqualUnmodifiableListView) return _addresses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_addresses);
}

@override final  String? libraryId;
@override final  String discoveredAt;

/// Create a copy of FrbDiscoveredPeer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbDiscoveredPeerCopyWith<_FrbDiscoveredPeer> get copyWith => __$FrbDiscoveredPeerCopyWithImpl<_FrbDiscoveredPeer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbDiscoveredPeer&&(identical(other.name, name) || other.name == name)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&const DeepCollectionEquality().equals(other._addresses, _addresses)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.discoveredAt, discoveredAt) || other.discoveredAt == discoveredAt));
}


@override
int get hashCode => Object.hash(runtimeType,name,host,port,const DeepCollectionEquality().hash(_addresses),libraryId,discoveredAt);

@override
String toString() {
  return 'FrbDiscoveredPeer(name: $name, host: $host, port: $port, addresses: $addresses, libraryId: $libraryId, discoveredAt: $discoveredAt)';
}


}

/// @nodoc
abstract mixin class _$FrbDiscoveredPeerCopyWith<$Res> implements $FrbDiscoveredPeerCopyWith<$Res> {
  factory _$FrbDiscoveredPeerCopyWith(_FrbDiscoveredPeer value, $Res Function(_FrbDiscoveredPeer) _then) = __$FrbDiscoveredPeerCopyWithImpl;
@override @useResult
$Res call({
 String name, String host, int port, List<String> addresses, String? libraryId, String discoveredAt
});




}
/// @nodoc
class __$FrbDiscoveredPeerCopyWithImpl<$Res>
    implements _$FrbDiscoveredPeerCopyWith<$Res> {
  __$FrbDiscoveredPeerCopyWithImpl(this._self, this._then);

  final _FrbDiscoveredPeer _self;
  final $Res Function(_FrbDiscoveredPeer) _then;

/// Create a copy of FrbDiscoveredPeer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? host = null,Object? port = null,Object? addresses = null,Object? libraryId = freezed,Object? discoveredAt = null,}) {
  return _then(_FrbDiscoveredPeer(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,addresses: null == addresses ? _self._addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<String>,libraryId: freezed == libraryId ? _self.libraryId : libraryId // ignore: cast_nullable_to_non_nullable
as String?,discoveredAt: null == discoveredAt ? _self.discoveredAt : discoveredAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FrbLoan {

 int get id; int get copyId; int get contactId; int get libraryId; String get loanDate; String get dueDate; String? get returnDate; String get status; String? get notes; String get contactName; String get bookTitle;
/// Create a copy of FrbLoan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbLoanCopyWith<FrbLoan> get copyWith => _$FrbLoanCopyWithImpl<FrbLoan>(this as FrbLoan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbLoan&&(identical(other.id, id) || other.id == id)&&(identical(other.copyId, copyId) || other.copyId == copyId)&&(identical(other.contactId, contactId) || other.contactId == contactId)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.loanDate, loanDate) || other.loanDate == loanDate)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.returnDate, returnDate) || other.returnDate == returnDate)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.contactName, contactName) || other.contactName == contactName)&&(identical(other.bookTitle, bookTitle) || other.bookTitle == bookTitle));
}


@override
int get hashCode => Object.hash(runtimeType,id,copyId,contactId,libraryId,loanDate,dueDate,returnDate,status,notes,contactName,bookTitle);

@override
String toString() {
  return 'FrbLoan(id: $id, copyId: $copyId, contactId: $contactId, libraryId: $libraryId, loanDate: $loanDate, dueDate: $dueDate, returnDate: $returnDate, status: $status, notes: $notes, contactName: $contactName, bookTitle: $bookTitle)';
}


}

/// @nodoc
abstract mixin class $FrbLoanCopyWith<$Res>  {
  factory $FrbLoanCopyWith(FrbLoan value, $Res Function(FrbLoan) _then) = _$FrbLoanCopyWithImpl;
@useResult
$Res call({
 int id, int copyId, int contactId, int libraryId, String loanDate, String dueDate, String? returnDate, String status, String? notes, String contactName, String bookTitle
});




}
/// @nodoc
class _$FrbLoanCopyWithImpl<$Res>
    implements $FrbLoanCopyWith<$Res> {
  _$FrbLoanCopyWithImpl(this._self, this._then);

  final FrbLoan _self;
  final $Res Function(FrbLoan) _then;

/// Create a copy of FrbLoan
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? copyId = null,Object? contactId = null,Object? libraryId = null,Object? loanDate = null,Object? dueDate = null,Object? returnDate = freezed,Object? status = null,Object? notes = freezed,Object? contactName = null,Object? bookTitle = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,copyId: null == copyId ? _self.copyId : copyId // ignore: cast_nullable_to_non_nullable
as int,contactId: null == contactId ? _self.contactId : contactId // ignore: cast_nullable_to_non_nullable
as int,libraryId: null == libraryId ? _self.libraryId : libraryId // ignore: cast_nullable_to_non_nullable
as int,loanDate: null == loanDate ? _self.loanDate : loanDate // ignore: cast_nullable_to_non_nullable
as String,dueDate: null == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String,returnDate: freezed == returnDate ? _self.returnDate : returnDate // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,contactName: null == contactName ? _self.contactName : contactName // ignore: cast_nullable_to_non_nullable
as String,bookTitle: null == bookTitle ? _self.bookTitle : bookTitle // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbLoan].
extension FrbLoanPatterns on FrbLoan {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbLoan value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbLoan() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbLoan value)  $default,){
final _that = this;
switch (_that) {
case _FrbLoan():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbLoan value)?  $default,){
final _that = this;
switch (_that) {
case _FrbLoan() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int copyId,  int contactId,  int libraryId,  String loanDate,  String dueDate,  String? returnDate,  String status,  String? notes,  String contactName,  String bookTitle)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbLoan() when $default != null:
return $default(_that.id,_that.copyId,_that.contactId,_that.libraryId,_that.loanDate,_that.dueDate,_that.returnDate,_that.status,_that.notes,_that.contactName,_that.bookTitle);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int copyId,  int contactId,  int libraryId,  String loanDate,  String dueDate,  String? returnDate,  String status,  String? notes,  String contactName,  String bookTitle)  $default,) {final _that = this;
switch (_that) {
case _FrbLoan():
return $default(_that.id,_that.copyId,_that.contactId,_that.libraryId,_that.loanDate,_that.dueDate,_that.returnDate,_that.status,_that.notes,_that.contactName,_that.bookTitle);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int copyId,  int contactId,  int libraryId,  String loanDate,  String dueDate,  String? returnDate,  String status,  String? notes,  String contactName,  String bookTitle)?  $default,) {final _that = this;
switch (_that) {
case _FrbLoan() when $default != null:
return $default(_that.id,_that.copyId,_that.contactId,_that.libraryId,_that.loanDate,_that.dueDate,_that.returnDate,_that.status,_that.notes,_that.contactName,_that.bookTitle);case _:
  return null;

}
}

}

/// @nodoc


class _FrbLoan implements FrbLoan {
  const _FrbLoan({required this.id, required this.copyId, required this.contactId, required this.libraryId, required this.loanDate, required this.dueDate, this.returnDate, required this.status, this.notes, required this.contactName, required this.bookTitle});
  

@override final  int id;
@override final  int copyId;
@override final  int contactId;
@override final  int libraryId;
@override final  String loanDate;
@override final  String dueDate;
@override final  String? returnDate;
@override final  String status;
@override final  String? notes;
@override final  String contactName;
@override final  String bookTitle;

/// Create a copy of FrbLoan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbLoanCopyWith<_FrbLoan> get copyWith => __$FrbLoanCopyWithImpl<_FrbLoan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbLoan&&(identical(other.id, id) || other.id == id)&&(identical(other.copyId, copyId) || other.copyId == copyId)&&(identical(other.contactId, contactId) || other.contactId == contactId)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.loanDate, loanDate) || other.loanDate == loanDate)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.returnDate, returnDate) || other.returnDate == returnDate)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.contactName, contactName) || other.contactName == contactName)&&(identical(other.bookTitle, bookTitle) || other.bookTitle == bookTitle));
}


@override
int get hashCode => Object.hash(runtimeType,id,copyId,contactId,libraryId,loanDate,dueDate,returnDate,status,notes,contactName,bookTitle);

@override
String toString() {
  return 'FrbLoan(id: $id, copyId: $copyId, contactId: $contactId, libraryId: $libraryId, loanDate: $loanDate, dueDate: $dueDate, returnDate: $returnDate, status: $status, notes: $notes, contactName: $contactName, bookTitle: $bookTitle)';
}


}

/// @nodoc
abstract mixin class _$FrbLoanCopyWith<$Res> implements $FrbLoanCopyWith<$Res> {
  factory _$FrbLoanCopyWith(_FrbLoan value, $Res Function(_FrbLoan) _then) = __$FrbLoanCopyWithImpl;
@override @useResult
$Res call({
 int id, int copyId, int contactId, int libraryId, String loanDate, String dueDate, String? returnDate, String status, String? notes, String contactName, String bookTitle
});




}
/// @nodoc
class __$FrbLoanCopyWithImpl<$Res>
    implements _$FrbLoanCopyWith<$Res> {
  __$FrbLoanCopyWithImpl(this._self, this._then);

  final _FrbLoan _self;
  final $Res Function(_FrbLoan) _then;

/// Create a copy of FrbLoan
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? copyId = null,Object? contactId = null,Object? libraryId = null,Object? loanDate = null,Object? dueDate = null,Object? returnDate = freezed,Object? status = null,Object? notes = freezed,Object? contactName = null,Object? bookTitle = null,}) {
  return _then(_FrbLoan(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,copyId: null == copyId ? _self.copyId : copyId // ignore: cast_nullable_to_non_nullable
as int,contactId: null == contactId ? _self.contactId : contactId // ignore: cast_nullable_to_non_nullable
as int,libraryId: null == libraryId ? _self.libraryId : libraryId // ignore: cast_nullable_to_non_nullable
as int,loanDate: null == loanDate ? _self.loanDate : loanDate // ignore: cast_nullable_to_non_nullable
as String,dueDate: null == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as String,returnDate: freezed == returnDate ? _self.returnDate : returnDate // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,notes: freezed == notes ? _self.notes : notes // ignore: cast_nullable_to_non_nullable
as String?,contactName: null == contactName ? _self.contactName : contactName // ignore: cast_nullable_to_non_nullable
as String,bookTitle: null == bookTitle ? _self.bookTitle : bookTitle // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FrbTag {

 int get id; String get name; int? get parentId; PlatformInt64 get count;
/// Create a copy of FrbTag
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbTagCopyWith<FrbTag> get copyWith => _$FrbTagCopyWithImpl<FrbTag>(this as FrbTag, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbTag&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,parentId,count);

@override
String toString() {
  return 'FrbTag(id: $id, name: $name, parentId: $parentId, count: $count)';
}


}

/// @nodoc
abstract mixin class $FrbTagCopyWith<$Res>  {
  factory $FrbTagCopyWith(FrbTag value, $Res Function(FrbTag) _then) = _$FrbTagCopyWithImpl;
@useResult
$Res call({
 int id, String name, int? parentId, PlatformInt64 count
});




}
/// @nodoc
class _$FrbTagCopyWithImpl<$Res>
    implements $FrbTagCopyWith<$Res> {
  _$FrbTagCopyWithImpl(this._self, this._then);

  final FrbTag _self;
  final $Res Function(FrbTag) _then;

/// Create a copy of FrbTag
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? parentId = freezed,Object? count = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as int?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbTag].
extension FrbTagPatterns on FrbTag {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbTag value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbTag() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbTag value)  $default,){
final _that = this;
switch (_that) {
case _FrbTag():
return $default(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbTag value)?  $default,){
final _that = this;
switch (_that) {
case _FrbTag() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String name,  int? parentId,  PlatformInt64 count)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbTag() when $default != null:
return $default(_that.id,_that.name,_that.parentId,_that.count);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String name,  int? parentId,  PlatformInt64 count)  $default,) {final _that = this;
switch (_that) {
case _FrbTag():
return $default(_that.id,_that.name,_that.parentId,_that.count);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String name,  int? parentId,  PlatformInt64 count)?  $default,) {final _that = this;
switch (_that) {
case _FrbTag() when $default != null:
return $default(_that.id,_that.name,_that.parentId,_that.count);case _:
  return null;

}
}

}

/// @nodoc


class _FrbTag implements FrbTag {
  const _FrbTag({required this.id, required this.name, this.parentId, required this.count});
  

@override final  int id;
@override final  String name;
@override final  int? parentId;
@override final  PlatformInt64 count;

/// Create a copy of FrbTag
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbTagCopyWith<_FrbTag> get copyWith => __$FrbTagCopyWithImpl<_FrbTag>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbTag&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode => Object.hash(runtimeType,id,name,parentId,count);

@override
String toString() {
  return 'FrbTag(id: $id, name: $name, parentId: $parentId, count: $count)';
}


}

/// @nodoc
abstract mixin class _$FrbTagCopyWith<$Res> implements $FrbTagCopyWith<$Res> {
  factory _$FrbTagCopyWith(_FrbTag value, $Res Function(_FrbTag) _then) = __$FrbTagCopyWithImpl;
@override @useResult
$Res call({
 int id, String name, int? parentId, PlatformInt64 count
});




}
/// @nodoc
class __$FrbTagCopyWithImpl<$Res>
    implements _$FrbTagCopyWith<$Res> {
  __$FrbTagCopyWithImpl(this._self, this._then);

  final _FrbTag _self;
  final $Res Function(_FrbTag) _then;

/// Create a copy of FrbTag
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? parentId = freezed,Object? count = null,}) {
  return _then(_FrbTag(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as int?,count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as PlatformInt64,
  ));
}


}

// dart format on
