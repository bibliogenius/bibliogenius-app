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
mixin _$FrbCatalogEntry {

 String get isbn; String get title; String? get author; String? get coverUrl; String? get firstSeenAt;
/// Create a copy of FrbCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbCatalogEntryCopyWith<FrbCatalogEntry> get copyWith => _$FrbCatalogEntryCopyWithImpl<FrbCatalogEntry>(this as FrbCatalogEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbCatalogEntry&&(identical(other.isbn, isbn) || other.isbn == isbn)&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.firstSeenAt, firstSeenAt) || other.firstSeenAt == firstSeenAt));
}


@override
int get hashCode => Object.hash(runtimeType,isbn,title,author,coverUrl,firstSeenAt);

@override
String toString() {
  return 'FrbCatalogEntry(isbn: $isbn, title: $title, author: $author, coverUrl: $coverUrl, firstSeenAt: $firstSeenAt)';
}


}

/// @nodoc
abstract mixin class $FrbCatalogEntryCopyWith<$Res>  {
  factory $FrbCatalogEntryCopyWith(FrbCatalogEntry value, $Res Function(FrbCatalogEntry) _then) = _$FrbCatalogEntryCopyWithImpl;
@useResult
$Res call({
 String isbn, String title, String? author, String? coverUrl, String? firstSeenAt
});




}
/// @nodoc
class _$FrbCatalogEntryCopyWithImpl<$Res>
    implements $FrbCatalogEntryCopyWith<$Res> {
  _$FrbCatalogEntryCopyWithImpl(this._self, this._then);

  final FrbCatalogEntry _self;
  final $Res Function(FrbCatalogEntry) _then;

/// Create a copy of FrbCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isbn = null,Object? title = null,Object? author = freezed,Object? coverUrl = freezed,Object? firstSeenAt = freezed,}) {
  return _then(_self.copyWith(
isbn: null == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,firstSeenAt: freezed == firstSeenAt ? _self.firstSeenAt : firstSeenAt // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbCatalogEntry].
extension FrbCatalogEntryPatterns on FrbCatalogEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbCatalogEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbCatalogEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbCatalogEntry value)  $default,){
final _that = this;
switch (_that) {
case _FrbCatalogEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbCatalogEntry value)?  $default,){
final _that = this;
switch (_that) {
case _FrbCatalogEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String isbn,  String title,  String? author,  String? coverUrl,  String? firstSeenAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbCatalogEntry() when $default != null:
return $default(_that.isbn,_that.title,_that.author,_that.coverUrl,_that.firstSeenAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String isbn,  String title,  String? author,  String? coverUrl,  String? firstSeenAt)  $default,) {final _that = this;
switch (_that) {
case _FrbCatalogEntry():
return $default(_that.isbn,_that.title,_that.author,_that.coverUrl,_that.firstSeenAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String isbn,  String title,  String? author,  String? coverUrl,  String? firstSeenAt)?  $default,) {final _that = this;
switch (_that) {
case _FrbCatalogEntry() when $default != null:
return $default(_that.isbn,_that.title,_that.author,_that.coverUrl,_that.firstSeenAt);case _:
  return null;

}
}

}

/// @nodoc


class _FrbCatalogEntry implements FrbCatalogEntry {
  const _FrbCatalogEntry({required this.isbn, required this.title, this.author, this.coverUrl, this.firstSeenAt});
  

@override final  String isbn;
@override final  String title;
@override final  String? author;
@override final  String? coverUrl;
@override final  String? firstSeenAt;

/// Create a copy of FrbCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbCatalogEntryCopyWith<_FrbCatalogEntry> get copyWith => __$FrbCatalogEntryCopyWithImpl<_FrbCatalogEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbCatalogEntry&&(identical(other.isbn, isbn) || other.isbn == isbn)&&(identical(other.title, title) || other.title == title)&&(identical(other.author, author) || other.author == author)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.firstSeenAt, firstSeenAt) || other.firstSeenAt == firstSeenAt));
}


@override
int get hashCode => Object.hash(runtimeType,isbn,title,author,coverUrl,firstSeenAt);

@override
String toString() {
  return 'FrbCatalogEntry(isbn: $isbn, title: $title, author: $author, coverUrl: $coverUrl, firstSeenAt: $firstSeenAt)';
}


}

/// @nodoc
abstract mixin class _$FrbCatalogEntryCopyWith<$Res> implements $FrbCatalogEntryCopyWith<$Res> {
  factory _$FrbCatalogEntryCopyWith(_FrbCatalogEntry value, $Res Function(_FrbCatalogEntry) _then) = __$FrbCatalogEntryCopyWithImpl;
@override @useResult
$Res call({
 String isbn, String title, String? author, String? coverUrl, String? firstSeenAt
});




}
/// @nodoc
class __$FrbCatalogEntryCopyWithImpl<$Res>
    implements _$FrbCatalogEntryCopyWith<$Res> {
  __$FrbCatalogEntryCopyWithImpl(this._self, this._then);

  final _FrbCatalogEntry _self;
  final $Res Function(_FrbCatalogEntry) _then;

/// Create a copy of FrbCatalogEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isbn = null,Object? title = null,Object? author = freezed,Object? coverUrl = freezed,Object? firstSeenAt = freezed,}) {
  return _then(_FrbCatalogEntry(
isbn: null == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,author: freezed == author ? _self.author : author // ignore: cast_nullable_to_non_nullable
as String?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,firstSeenAt: freezed == firstSeenAt ? _self.firstSeenAt : firstSeenAt // ignore: cast_nullable_to_non_nullable
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
mixin _$FrbDirectoryConfig {

 String get nodeId; bool get isListed; bool get requiresApproval; String get acceptFrom; bool get allowBorrowing;
/// Create a copy of FrbDirectoryConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbDirectoryConfigCopyWith<FrbDirectoryConfig> get copyWith => _$FrbDirectoryConfigCopyWithImpl<FrbDirectoryConfig>(this as FrbDirectoryConfig, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbDirectoryConfig&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.isListed, isListed) || other.isListed == isListed)&&(identical(other.requiresApproval, requiresApproval) || other.requiresApproval == requiresApproval)&&(identical(other.acceptFrom, acceptFrom) || other.acceptFrom == acceptFrom)&&(identical(other.allowBorrowing, allowBorrowing) || other.allowBorrowing == allowBorrowing));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,isListed,requiresApproval,acceptFrom,allowBorrowing);

@override
String toString() {
  return 'FrbDirectoryConfig(nodeId: $nodeId, isListed: $isListed, requiresApproval: $requiresApproval, acceptFrom: $acceptFrom, allowBorrowing: $allowBorrowing)';
}


}

/// @nodoc
abstract mixin class $FrbDirectoryConfigCopyWith<$Res>  {
  factory $FrbDirectoryConfigCopyWith(FrbDirectoryConfig value, $Res Function(FrbDirectoryConfig) _then) = _$FrbDirectoryConfigCopyWithImpl;
@useResult
$Res call({
 String nodeId, bool isListed, bool requiresApproval, String acceptFrom, bool allowBorrowing
});




}
/// @nodoc
class _$FrbDirectoryConfigCopyWithImpl<$Res>
    implements $FrbDirectoryConfigCopyWith<$Res> {
  _$FrbDirectoryConfigCopyWithImpl(this._self, this._then);

  final FrbDirectoryConfig _self;
  final $Res Function(FrbDirectoryConfig) _then;

/// Create a copy of FrbDirectoryConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? isListed = null,Object? requiresApproval = null,Object? acceptFrom = null,Object? allowBorrowing = null,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,isListed: null == isListed ? _self.isListed : isListed // ignore: cast_nullable_to_non_nullable
as bool,requiresApproval: null == requiresApproval ? _self.requiresApproval : requiresApproval // ignore: cast_nullable_to_non_nullable
as bool,acceptFrom: null == acceptFrom ? _self.acceptFrom : acceptFrom // ignore: cast_nullable_to_non_nullable
as String,allowBorrowing: null == allowBorrowing ? _self.allowBorrowing : allowBorrowing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbDirectoryConfig].
extension FrbDirectoryConfigPatterns on FrbDirectoryConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbDirectoryConfig value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbDirectoryConfig() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbDirectoryConfig value)  $default,){
final _that = this;
switch (_that) {
case _FrbDirectoryConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbDirectoryConfig value)?  $default,){
final _that = this;
switch (_that) {
case _FrbDirectoryConfig() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  bool isListed,  bool requiresApproval,  String acceptFrom,  bool allowBorrowing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbDirectoryConfig() when $default != null:
return $default(_that.nodeId,_that.isListed,_that.requiresApproval,_that.acceptFrom,_that.allowBorrowing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  bool isListed,  bool requiresApproval,  String acceptFrom,  bool allowBorrowing)  $default,) {final _that = this;
switch (_that) {
case _FrbDirectoryConfig():
return $default(_that.nodeId,_that.isListed,_that.requiresApproval,_that.acceptFrom,_that.allowBorrowing);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  bool isListed,  bool requiresApproval,  String acceptFrom,  bool allowBorrowing)?  $default,) {final _that = this;
switch (_that) {
case _FrbDirectoryConfig() when $default != null:
return $default(_that.nodeId,_that.isListed,_that.requiresApproval,_that.acceptFrom,_that.allowBorrowing);case _:
  return null;

}
}

}

/// @nodoc


class _FrbDirectoryConfig implements FrbDirectoryConfig {
  const _FrbDirectoryConfig({required this.nodeId, required this.isListed, required this.requiresApproval, required this.acceptFrom, required this.allowBorrowing});
  

@override final  String nodeId;
@override final  bool isListed;
@override final  bool requiresApproval;
@override final  String acceptFrom;
@override final  bool allowBorrowing;

/// Create a copy of FrbDirectoryConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbDirectoryConfigCopyWith<_FrbDirectoryConfig> get copyWith => __$FrbDirectoryConfigCopyWithImpl<_FrbDirectoryConfig>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbDirectoryConfig&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.isListed, isListed) || other.isListed == isListed)&&(identical(other.requiresApproval, requiresApproval) || other.requiresApproval == requiresApproval)&&(identical(other.acceptFrom, acceptFrom) || other.acceptFrom == acceptFrom)&&(identical(other.allowBorrowing, allowBorrowing) || other.allowBorrowing == allowBorrowing));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,isListed,requiresApproval,acceptFrom,allowBorrowing);

@override
String toString() {
  return 'FrbDirectoryConfig(nodeId: $nodeId, isListed: $isListed, requiresApproval: $requiresApproval, acceptFrom: $acceptFrom, allowBorrowing: $allowBorrowing)';
}


}

/// @nodoc
abstract mixin class _$FrbDirectoryConfigCopyWith<$Res> implements $FrbDirectoryConfigCopyWith<$Res> {
  factory _$FrbDirectoryConfigCopyWith(_FrbDirectoryConfig value, $Res Function(_FrbDirectoryConfig) _then) = __$FrbDirectoryConfigCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, bool isListed, bool requiresApproval, String acceptFrom, bool allowBorrowing
});




}
/// @nodoc
class __$FrbDirectoryConfigCopyWithImpl<$Res>
    implements _$FrbDirectoryConfigCopyWith<$Res> {
  __$FrbDirectoryConfigCopyWithImpl(this._self, this._then);

  final _FrbDirectoryConfig _self;
  final $Res Function(_FrbDirectoryConfig) _then;

/// Create a copy of FrbDirectoryConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? isListed = null,Object? requiresApproval = null,Object? acceptFrom = null,Object? allowBorrowing = null,}) {
  return _then(_FrbDirectoryConfig(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,isListed: null == isListed ? _self.isListed : isListed // ignore: cast_nullable_to_non_nullable
as bool,requiresApproval: null == requiresApproval ? _self.requiresApproval : requiresApproval // ignore: cast_nullable_to_non_nullable
as bool,acceptFrom: null == acceptFrom ? _self.acceptFrom : acceptFrom // ignore: cast_nullable_to_non_nullable
as String,allowBorrowing: null == allowBorrowing ? _self.allowBorrowing : allowBorrowing // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$FrbDiscoveredPeer {

 String get name; String get host; int get port; List<String> get addresses; String? get libraryId; String? get ed25519PublicKey; String? get x25519PublicKey; String get discoveredAt;
/// Create a copy of FrbDiscoveredPeer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbDiscoveredPeerCopyWith<FrbDiscoveredPeer> get copyWith => _$FrbDiscoveredPeerCopyWithImpl<FrbDiscoveredPeer>(this as FrbDiscoveredPeer, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbDiscoveredPeer&&(identical(other.name, name) || other.name == name)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&const DeepCollectionEquality().equals(other.addresses, addresses)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.ed25519PublicKey, ed25519PublicKey) || other.ed25519PublicKey == ed25519PublicKey)&&(identical(other.x25519PublicKey, x25519PublicKey) || other.x25519PublicKey == x25519PublicKey)&&(identical(other.discoveredAt, discoveredAt) || other.discoveredAt == discoveredAt));
}


@override
int get hashCode => Object.hash(runtimeType,name,host,port,const DeepCollectionEquality().hash(addresses),libraryId,ed25519PublicKey,x25519PublicKey,discoveredAt);

@override
String toString() {
  return 'FrbDiscoveredPeer(name: $name, host: $host, port: $port, addresses: $addresses, libraryId: $libraryId, ed25519PublicKey: $ed25519PublicKey, x25519PublicKey: $x25519PublicKey, discoveredAt: $discoveredAt)';
}


}

/// @nodoc
abstract mixin class $FrbDiscoveredPeerCopyWith<$Res>  {
  factory $FrbDiscoveredPeerCopyWith(FrbDiscoveredPeer value, $Res Function(FrbDiscoveredPeer) _then) = _$FrbDiscoveredPeerCopyWithImpl;
@useResult
$Res call({
 String name, String host, int port, List<String> addresses, String? libraryId, String? ed25519PublicKey, String? x25519PublicKey, String discoveredAt
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
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? host = null,Object? port = null,Object? addresses = null,Object? libraryId = freezed,Object? ed25519PublicKey = freezed,Object? x25519PublicKey = freezed,Object? discoveredAt = null,}) {
  return _then(_self.copyWith(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,addresses: null == addresses ? _self.addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<String>,libraryId: freezed == libraryId ? _self.libraryId : libraryId // ignore: cast_nullable_to_non_nullable
as String?,ed25519PublicKey: freezed == ed25519PublicKey ? _self.ed25519PublicKey : ed25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,x25519PublicKey: freezed == x25519PublicKey ? _self.x25519PublicKey : x25519PublicKey // ignore: cast_nullable_to_non_nullable
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String host,  int port,  List<String> addresses,  String? libraryId,  String? ed25519PublicKey,  String? x25519PublicKey,  String discoveredAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbDiscoveredPeer() when $default != null:
return $default(_that.name,_that.host,_that.port,_that.addresses,_that.libraryId,_that.ed25519PublicKey,_that.x25519PublicKey,_that.discoveredAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String host,  int port,  List<String> addresses,  String? libraryId,  String? ed25519PublicKey,  String? x25519PublicKey,  String discoveredAt)  $default,) {final _that = this;
switch (_that) {
case _FrbDiscoveredPeer():
return $default(_that.name,_that.host,_that.port,_that.addresses,_that.libraryId,_that.ed25519PublicKey,_that.x25519PublicKey,_that.discoveredAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String host,  int port,  List<String> addresses,  String? libraryId,  String? ed25519PublicKey,  String? x25519PublicKey,  String discoveredAt)?  $default,) {final _that = this;
switch (_that) {
case _FrbDiscoveredPeer() when $default != null:
return $default(_that.name,_that.host,_that.port,_that.addresses,_that.libraryId,_that.ed25519PublicKey,_that.x25519PublicKey,_that.discoveredAt);case _:
  return null;

}
}

}

/// @nodoc


class _FrbDiscoveredPeer implements FrbDiscoveredPeer {
  const _FrbDiscoveredPeer({required this.name, required this.host, required this.port, required final  List<String> addresses, this.libraryId, this.ed25519PublicKey, this.x25519PublicKey, required this.discoveredAt}): _addresses = addresses;
  

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
@override final  String? ed25519PublicKey;
@override final  String? x25519PublicKey;
@override final  String discoveredAt;

/// Create a copy of FrbDiscoveredPeer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbDiscoveredPeerCopyWith<_FrbDiscoveredPeer> get copyWith => __$FrbDiscoveredPeerCopyWithImpl<_FrbDiscoveredPeer>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbDiscoveredPeer&&(identical(other.name, name) || other.name == name)&&(identical(other.host, host) || other.host == host)&&(identical(other.port, port) || other.port == port)&&const DeepCollectionEquality().equals(other._addresses, _addresses)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.ed25519PublicKey, ed25519PublicKey) || other.ed25519PublicKey == ed25519PublicKey)&&(identical(other.x25519PublicKey, x25519PublicKey) || other.x25519PublicKey == x25519PublicKey)&&(identical(other.discoveredAt, discoveredAt) || other.discoveredAt == discoveredAt));
}


@override
int get hashCode => Object.hash(runtimeType,name,host,port,const DeepCollectionEquality().hash(_addresses),libraryId,ed25519PublicKey,x25519PublicKey,discoveredAt);

@override
String toString() {
  return 'FrbDiscoveredPeer(name: $name, host: $host, port: $port, addresses: $addresses, libraryId: $libraryId, ed25519PublicKey: $ed25519PublicKey, x25519PublicKey: $x25519PublicKey, discoveredAt: $discoveredAt)';
}


}

/// @nodoc
abstract mixin class _$FrbDiscoveredPeerCopyWith<$Res> implements $FrbDiscoveredPeerCopyWith<$Res> {
  factory _$FrbDiscoveredPeerCopyWith(_FrbDiscoveredPeer value, $Res Function(_FrbDiscoveredPeer) _then) = __$FrbDiscoveredPeerCopyWithImpl;
@override @useResult
$Res call({
 String name, String host, int port, List<String> addresses, String? libraryId, String? ed25519PublicKey, String? x25519PublicKey, String discoveredAt
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
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? host = null,Object? port = null,Object? addresses = null,Object? libraryId = freezed,Object? ed25519PublicKey = freezed,Object? x25519PublicKey = freezed,Object? discoveredAt = null,}) {
  return _then(_FrbDiscoveredPeer(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as int,addresses: null == addresses ? _self._addresses : addresses // ignore: cast_nullable_to_non_nullable
as List<String>,libraryId: freezed == libraryId ? _self.libraryId : libraryId // ignore: cast_nullable_to_non_nullable
as String?,ed25519PublicKey: freezed == ed25519PublicKey ? _self.ed25519PublicKey : ed25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,x25519PublicKey: freezed == x25519PublicKey ? _self.x25519PublicKey : x25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,discoveredAt: null == discoveredAt ? _self.discoveredAt : discoveredAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FrbHubBorrowRequest {

 PlatformInt64 get id; String get requesterNodeId; String get lenderNodeId; String get isbn; String get bookTitle; String get status; String get createdAt; String? get resolvedAt; String? get requesterDisplayName; String? get lenderDisplayName;
/// Create a copy of FrbHubBorrowRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbHubBorrowRequestCopyWith<FrbHubBorrowRequest> get copyWith => _$FrbHubBorrowRequestCopyWithImpl<FrbHubBorrowRequest>(this as FrbHubBorrowRequest, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbHubBorrowRequest&&(identical(other.id, id) || other.id == id)&&(identical(other.requesterNodeId, requesterNodeId) || other.requesterNodeId == requesterNodeId)&&(identical(other.lenderNodeId, lenderNodeId) || other.lenderNodeId == lenderNodeId)&&(identical(other.isbn, isbn) || other.isbn == isbn)&&(identical(other.bookTitle, bookTitle) || other.bookTitle == bookTitle)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.requesterDisplayName, requesterDisplayName) || other.requesterDisplayName == requesterDisplayName)&&(identical(other.lenderDisplayName, lenderDisplayName) || other.lenderDisplayName == lenderDisplayName));
}


@override
int get hashCode => Object.hash(runtimeType,id,requesterNodeId,lenderNodeId,isbn,bookTitle,status,createdAt,resolvedAt,requesterDisplayName,lenderDisplayName);

@override
String toString() {
  return 'FrbHubBorrowRequest(id: $id, requesterNodeId: $requesterNodeId, lenderNodeId: $lenderNodeId, isbn: $isbn, bookTitle: $bookTitle, status: $status, createdAt: $createdAt, resolvedAt: $resolvedAt, requesterDisplayName: $requesterDisplayName, lenderDisplayName: $lenderDisplayName)';
}


}

/// @nodoc
abstract mixin class $FrbHubBorrowRequestCopyWith<$Res>  {
  factory $FrbHubBorrowRequestCopyWith(FrbHubBorrowRequest value, $Res Function(FrbHubBorrowRequest) _then) = _$FrbHubBorrowRequestCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 id, String requesterNodeId, String lenderNodeId, String isbn, String bookTitle, String status, String createdAt, String? resolvedAt, String? requesterDisplayName, String? lenderDisplayName
});




}
/// @nodoc
class _$FrbHubBorrowRequestCopyWithImpl<$Res>
    implements $FrbHubBorrowRequestCopyWith<$Res> {
  _$FrbHubBorrowRequestCopyWithImpl(this._self, this._then);

  final FrbHubBorrowRequest _self;
  final $Res Function(FrbHubBorrowRequest) _then;

/// Create a copy of FrbHubBorrowRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? requesterNodeId = null,Object? lenderNodeId = null,Object? isbn = null,Object? bookTitle = null,Object? status = null,Object? createdAt = null,Object? resolvedAt = freezed,Object? requesterDisplayName = freezed,Object? lenderDisplayName = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as PlatformInt64,requesterNodeId: null == requesterNodeId ? _self.requesterNodeId : requesterNodeId // ignore: cast_nullable_to_non_nullable
as String,lenderNodeId: null == lenderNodeId ? _self.lenderNodeId : lenderNodeId // ignore: cast_nullable_to_non_nullable
as String,isbn: null == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String,bookTitle: null == bookTitle ? _self.bookTitle : bookTitle // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as String?,requesterDisplayName: freezed == requesterDisplayName ? _self.requesterDisplayName : requesterDisplayName // ignore: cast_nullable_to_non_nullable
as String?,lenderDisplayName: freezed == lenderDisplayName ? _self.lenderDisplayName : lenderDisplayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbHubBorrowRequest].
extension FrbHubBorrowRequestPatterns on FrbHubBorrowRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbHubBorrowRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbHubBorrowRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbHubBorrowRequest value)  $default,){
final _that = this;
switch (_that) {
case _FrbHubBorrowRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbHubBorrowRequest value)?  $default,){
final _that = this;
switch (_that) {
case _FrbHubBorrowRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PlatformInt64 id,  String requesterNodeId,  String lenderNodeId,  String isbn,  String bookTitle,  String status,  String createdAt,  String? resolvedAt,  String? requesterDisplayName,  String? lenderDisplayName)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbHubBorrowRequest() when $default != null:
return $default(_that.id,_that.requesterNodeId,_that.lenderNodeId,_that.isbn,_that.bookTitle,_that.status,_that.createdAt,_that.resolvedAt,_that.requesterDisplayName,_that.lenderDisplayName);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PlatformInt64 id,  String requesterNodeId,  String lenderNodeId,  String isbn,  String bookTitle,  String status,  String createdAt,  String? resolvedAt,  String? requesterDisplayName,  String? lenderDisplayName)  $default,) {final _that = this;
switch (_that) {
case _FrbHubBorrowRequest():
return $default(_that.id,_that.requesterNodeId,_that.lenderNodeId,_that.isbn,_that.bookTitle,_that.status,_that.createdAt,_that.resolvedAt,_that.requesterDisplayName,_that.lenderDisplayName);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PlatformInt64 id,  String requesterNodeId,  String lenderNodeId,  String isbn,  String bookTitle,  String status,  String createdAt,  String? resolvedAt,  String? requesterDisplayName,  String? lenderDisplayName)?  $default,) {final _that = this;
switch (_that) {
case _FrbHubBorrowRequest() when $default != null:
return $default(_that.id,_that.requesterNodeId,_that.lenderNodeId,_that.isbn,_that.bookTitle,_that.status,_that.createdAt,_that.resolvedAt,_that.requesterDisplayName,_that.lenderDisplayName);case _:
  return null;

}
}

}

/// @nodoc


class _FrbHubBorrowRequest implements FrbHubBorrowRequest {
  const _FrbHubBorrowRequest({required this.id, required this.requesterNodeId, required this.lenderNodeId, required this.isbn, required this.bookTitle, required this.status, required this.createdAt, this.resolvedAt, this.requesterDisplayName, this.lenderDisplayName});
  

@override final  PlatformInt64 id;
@override final  String requesterNodeId;
@override final  String lenderNodeId;
@override final  String isbn;
@override final  String bookTitle;
@override final  String status;
@override final  String createdAt;
@override final  String? resolvedAt;
@override final  String? requesterDisplayName;
@override final  String? lenderDisplayName;

/// Create a copy of FrbHubBorrowRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbHubBorrowRequestCopyWith<_FrbHubBorrowRequest> get copyWith => __$FrbHubBorrowRequestCopyWithImpl<_FrbHubBorrowRequest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbHubBorrowRequest&&(identical(other.id, id) || other.id == id)&&(identical(other.requesterNodeId, requesterNodeId) || other.requesterNodeId == requesterNodeId)&&(identical(other.lenderNodeId, lenderNodeId) || other.lenderNodeId == lenderNodeId)&&(identical(other.isbn, isbn) || other.isbn == isbn)&&(identical(other.bookTitle, bookTitle) || other.bookTitle == bookTitle)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.requesterDisplayName, requesterDisplayName) || other.requesterDisplayName == requesterDisplayName)&&(identical(other.lenderDisplayName, lenderDisplayName) || other.lenderDisplayName == lenderDisplayName));
}


@override
int get hashCode => Object.hash(runtimeType,id,requesterNodeId,lenderNodeId,isbn,bookTitle,status,createdAt,resolvedAt,requesterDisplayName,lenderDisplayName);

@override
String toString() {
  return 'FrbHubBorrowRequest(id: $id, requesterNodeId: $requesterNodeId, lenderNodeId: $lenderNodeId, isbn: $isbn, bookTitle: $bookTitle, status: $status, createdAt: $createdAt, resolvedAt: $resolvedAt, requesterDisplayName: $requesterDisplayName, lenderDisplayName: $lenderDisplayName)';
}


}

/// @nodoc
abstract mixin class _$FrbHubBorrowRequestCopyWith<$Res> implements $FrbHubBorrowRequestCopyWith<$Res> {
  factory _$FrbHubBorrowRequestCopyWith(_FrbHubBorrowRequest value, $Res Function(_FrbHubBorrowRequest) _then) = __$FrbHubBorrowRequestCopyWithImpl;
@override @useResult
$Res call({
 PlatformInt64 id, String requesterNodeId, String lenderNodeId, String isbn, String bookTitle, String status, String createdAt, String? resolvedAt, String? requesterDisplayName, String? lenderDisplayName
});




}
/// @nodoc
class __$FrbHubBorrowRequestCopyWithImpl<$Res>
    implements _$FrbHubBorrowRequestCopyWith<$Res> {
  __$FrbHubBorrowRequestCopyWithImpl(this._self, this._then);

  final _FrbHubBorrowRequest _self;
  final $Res Function(_FrbHubBorrowRequest) _then;

/// Create a copy of FrbHubBorrowRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? requesterNodeId = null,Object? lenderNodeId = null,Object? isbn = null,Object? bookTitle = null,Object? status = null,Object? createdAt = null,Object? resolvedAt = freezed,Object? requesterDisplayName = freezed,Object? lenderDisplayName = freezed,}) {
  return _then(_FrbHubBorrowRequest(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as PlatformInt64,requesterNodeId: null == requesterNodeId ? _self.requesterNodeId : requesterNodeId // ignore: cast_nullable_to_non_nullable
as String,lenderNodeId: null == lenderNodeId ? _self.lenderNodeId : lenderNodeId // ignore: cast_nullable_to_non_nullable
as String,isbn: null == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String,bookTitle: null == bookTitle ? _self.bookTitle : bookTitle // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as String?,requesterDisplayName: freezed == requesterDisplayName ? _self.requesterDisplayName : requesterDisplayName // ignore: cast_nullable_to_non_nullable
as String?,lenderDisplayName: freezed == lenderDisplayName ? _self.lenderDisplayName : lenderDisplayName // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$FrbHubFollow {

 PlatformInt64 get id; String get followerNodeId; String get followedNodeId; String get status; String get createdAt; String? get resolvedAt; String? get followerDisplayName; String? get encryptedContact; String? get followerX25519PublicKey;
/// Create a copy of FrbHubFollow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbHubFollowCopyWith<FrbHubFollow> get copyWith => _$FrbHubFollowCopyWithImpl<FrbHubFollow>(this as FrbHubFollow, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbHubFollow&&(identical(other.id, id) || other.id == id)&&(identical(other.followerNodeId, followerNodeId) || other.followerNodeId == followerNodeId)&&(identical(other.followedNodeId, followedNodeId) || other.followedNodeId == followedNodeId)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.followerDisplayName, followerDisplayName) || other.followerDisplayName == followerDisplayName)&&(identical(other.encryptedContact, encryptedContact) || other.encryptedContact == encryptedContact)&&(identical(other.followerX25519PublicKey, followerX25519PublicKey) || other.followerX25519PublicKey == followerX25519PublicKey));
}


@override
int get hashCode => Object.hash(runtimeType,id,followerNodeId,followedNodeId,status,createdAt,resolvedAt,followerDisplayName,encryptedContact,followerX25519PublicKey);

@override
String toString() {
  return 'FrbHubFollow(id: $id, followerNodeId: $followerNodeId, followedNodeId: $followedNodeId, status: $status, createdAt: $createdAt, resolvedAt: $resolvedAt, followerDisplayName: $followerDisplayName, encryptedContact: $encryptedContact, followerX25519PublicKey: $followerX25519PublicKey)';
}


}

/// @nodoc
abstract mixin class $FrbHubFollowCopyWith<$Res>  {
  factory $FrbHubFollowCopyWith(FrbHubFollow value, $Res Function(FrbHubFollow) _then) = _$FrbHubFollowCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 id, String followerNodeId, String followedNodeId, String status, String createdAt, String? resolvedAt, String? followerDisplayName, String? encryptedContact, String? followerX25519PublicKey
});




}
/// @nodoc
class _$FrbHubFollowCopyWithImpl<$Res>
    implements $FrbHubFollowCopyWith<$Res> {
  _$FrbHubFollowCopyWithImpl(this._self, this._then);

  final FrbHubFollow _self;
  final $Res Function(FrbHubFollow) _then;

/// Create a copy of FrbHubFollow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? followerNodeId = null,Object? followedNodeId = null,Object? status = null,Object? createdAt = null,Object? resolvedAt = freezed,Object? followerDisplayName = freezed,Object? encryptedContact = freezed,Object? followerX25519PublicKey = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as PlatformInt64,followerNodeId: null == followerNodeId ? _self.followerNodeId : followerNodeId // ignore: cast_nullable_to_non_nullable
as String,followedNodeId: null == followedNodeId ? _self.followedNodeId : followedNodeId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as String?,followerDisplayName: freezed == followerDisplayName ? _self.followerDisplayName : followerDisplayName // ignore: cast_nullable_to_non_nullable
as String?,encryptedContact: freezed == encryptedContact ? _self.encryptedContact : encryptedContact // ignore: cast_nullable_to_non_nullable
as String?,followerX25519PublicKey: freezed == followerX25519PublicKey ? _self.followerX25519PublicKey : followerX25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbHubFollow].
extension FrbHubFollowPatterns on FrbHubFollow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbHubFollow value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbHubFollow() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbHubFollow value)  $default,){
final _that = this;
switch (_that) {
case _FrbHubFollow():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbHubFollow value)?  $default,){
final _that = this;
switch (_that) {
case _FrbHubFollow() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PlatformInt64 id,  String followerNodeId,  String followedNodeId,  String status,  String createdAt,  String? resolvedAt,  String? followerDisplayName,  String? encryptedContact,  String? followerX25519PublicKey)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbHubFollow() when $default != null:
return $default(_that.id,_that.followerNodeId,_that.followedNodeId,_that.status,_that.createdAt,_that.resolvedAt,_that.followerDisplayName,_that.encryptedContact,_that.followerX25519PublicKey);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PlatformInt64 id,  String followerNodeId,  String followedNodeId,  String status,  String createdAt,  String? resolvedAt,  String? followerDisplayName,  String? encryptedContact,  String? followerX25519PublicKey)  $default,) {final _that = this;
switch (_that) {
case _FrbHubFollow():
return $default(_that.id,_that.followerNodeId,_that.followedNodeId,_that.status,_that.createdAt,_that.resolvedAt,_that.followerDisplayName,_that.encryptedContact,_that.followerX25519PublicKey);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PlatformInt64 id,  String followerNodeId,  String followedNodeId,  String status,  String createdAt,  String? resolvedAt,  String? followerDisplayName,  String? encryptedContact,  String? followerX25519PublicKey)?  $default,) {final _that = this;
switch (_that) {
case _FrbHubFollow() when $default != null:
return $default(_that.id,_that.followerNodeId,_that.followedNodeId,_that.status,_that.createdAt,_that.resolvedAt,_that.followerDisplayName,_that.encryptedContact,_that.followerX25519PublicKey);case _:
  return null;

}
}

}

/// @nodoc


class _FrbHubFollow implements FrbHubFollow {
  const _FrbHubFollow({required this.id, required this.followerNodeId, required this.followedNodeId, required this.status, required this.createdAt, this.resolvedAt, this.followerDisplayName, this.encryptedContact, this.followerX25519PublicKey});
  

@override final  PlatformInt64 id;
@override final  String followerNodeId;
@override final  String followedNodeId;
@override final  String status;
@override final  String createdAt;
@override final  String? resolvedAt;
@override final  String? followerDisplayName;
@override final  String? encryptedContact;
@override final  String? followerX25519PublicKey;

/// Create a copy of FrbHubFollow
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbHubFollowCopyWith<_FrbHubFollow> get copyWith => __$FrbHubFollowCopyWithImpl<_FrbHubFollow>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbHubFollow&&(identical(other.id, id) || other.id == id)&&(identical(other.followerNodeId, followerNodeId) || other.followerNodeId == followerNodeId)&&(identical(other.followedNodeId, followedNodeId) || other.followedNodeId == followedNodeId)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.resolvedAt, resolvedAt) || other.resolvedAt == resolvedAt)&&(identical(other.followerDisplayName, followerDisplayName) || other.followerDisplayName == followerDisplayName)&&(identical(other.encryptedContact, encryptedContact) || other.encryptedContact == encryptedContact)&&(identical(other.followerX25519PublicKey, followerX25519PublicKey) || other.followerX25519PublicKey == followerX25519PublicKey));
}


@override
int get hashCode => Object.hash(runtimeType,id,followerNodeId,followedNodeId,status,createdAt,resolvedAt,followerDisplayName,encryptedContact,followerX25519PublicKey);

@override
String toString() {
  return 'FrbHubFollow(id: $id, followerNodeId: $followerNodeId, followedNodeId: $followedNodeId, status: $status, createdAt: $createdAt, resolvedAt: $resolvedAt, followerDisplayName: $followerDisplayName, encryptedContact: $encryptedContact, followerX25519PublicKey: $followerX25519PublicKey)';
}


}

/// @nodoc
abstract mixin class _$FrbHubFollowCopyWith<$Res> implements $FrbHubFollowCopyWith<$Res> {
  factory _$FrbHubFollowCopyWith(_FrbHubFollow value, $Res Function(_FrbHubFollow) _then) = __$FrbHubFollowCopyWithImpl;
@override @useResult
$Res call({
 PlatformInt64 id, String followerNodeId, String followedNodeId, String status, String createdAt, String? resolvedAt, String? followerDisplayName, String? encryptedContact, String? followerX25519PublicKey
});




}
/// @nodoc
class __$FrbHubFollowCopyWithImpl<$Res>
    implements _$FrbHubFollowCopyWith<$Res> {
  __$FrbHubFollowCopyWithImpl(this._self, this._then);

  final _FrbHubFollow _self;
  final $Res Function(_FrbHubFollow) _then;

/// Create a copy of FrbHubFollow
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? followerNodeId = null,Object? followedNodeId = null,Object? status = null,Object? createdAt = null,Object? resolvedAt = freezed,Object? followerDisplayName = freezed,Object? encryptedContact = freezed,Object? followerX25519PublicKey = freezed,}) {
  return _then(_FrbHubFollow(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as PlatformInt64,followerNodeId: null == followerNodeId ? _self.followerNodeId : followerNodeId // ignore: cast_nullable_to_non_nullable
as String,followedNodeId: null == followedNodeId ? _self.followedNodeId : followedNodeId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,resolvedAt: freezed == resolvedAt ? _self.resolvedAt : resolvedAt // ignore: cast_nullable_to_non_nullable
as String?,followerDisplayName: freezed == followerDisplayName ? _self.followerDisplayName : followerDisplayName // ignore: cast_nullable_to_non_nullable
as String?,encryptedContact: freezed == encryptedContact ? _self.encryptedContact : encryptedContact // ignore: cast_nullable_to_non_nullable
as String?,followerX25519PublicKey: freezed == followerX25519PublicKey ? _self.followerX25519PublicKey : followerX25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$FrbHubProfile {

 String get nodeId; String get displayName; String? get description; int get bookCount; String? get locationCountry; bool get requiresApproval; bool? get allowBorrowing; String? get lastSeenAt; String? get x25519PublicKey; String? get website; String? get deviceModel; String? get deviceFingerprint;
/// Create a copy of FrbHubProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbHubProfileCopyWith<FrbHubProfile> get copyWith => _$FrbHubProfileCopyWithImpl<FrbHubProfile>(this as FrbHubProfile, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbHubProfile&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.bookCount, bookCount) || other.bookCount == bookCount)&&(identical(other.locationCountry, locationCountry) || other.locationCountry == locationCountry)&&(identical(other.requiresApproval, requiresApproval) || other.requiresApproval == requiresApproval)&&(identical(other.allowBorrowing, allowBorrowing) || other.allowBorrowing == allowBorrowing)&&(identical(other.lastSeenAt, lastSeenAt) || other.lastSeenAt == lastSeenAt)&&(identical(other.x25519PublicKey, x25519PublicKey) || other.x25519PublicKey == x25519PublicKey)&&(identical(other.website, website) || other.website == website)&&(identical(other.deviceModel, deviceModel) || other.deviceModel == deviceModel)&&(identical(other.deviceFingerprint, deviceFingerprint) || other.deviceFingerprint == deviceFingerprint));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,displayName,description,bookCount,locationCountry,requiresApproval,allowBorrowing,lastSeenAt,x25519PublicKey,website,deviceModel,deviceFingerprint);

@override
String toString() {
  return 'FrbHubProfile(nodeId: $nodeId, displayName: $displayName, description: $description, bookCount: $bookCount, locationCountry: $locationCountry, requiresApproval: $requiresApproval, allowBorrowing: $allowBorrowing, lastSeenAt: $lastSeenAt, x25519PublicKey: $x25519PublicKey, website: $website, deviceModel: $deviceModel, deviceFingerprint: $deviceFingerprint)';
}


}

/// @nodoc
abstract mixin class $FrbHubProfileCopyWith<$Res>  {
  factory $FrbHubProfileCopyWith(FrbHubProfile value, $Res Function(FrbHubProfile) _then) = _$FrbHubProfileCopyWithImpl;
@useResult
$Res call({
 String nodeId, String displayName, String? description, int bookCount, String? locationCountry, bool requiresApproval, bool? allowBorrowing, String? lastSeenAt, String? x25519PublicKey, String? website, String? deviceModel, String? deviceFingerprint
});




}
/// @nodoc
class _$FrbHubProfileCopyWithImpl<$Res>
    implements $FrbHubProfileCopyWith<$Res> {
  _$FrbHubProfileCopyWithImpl(this._self, this._then);

  final FrbHubProfile _self;
  final $Res Function(FrbHubProfile) _then;

/// Create a copy of FrbHubProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? displayName = null,Object? description = freezed,Object? bookCount = null,Object? locationCountry = freezed,Object? requiresApproval = null,Object? allowBorrowing = freezed,Object? lastSeenAt = freezed,Object? x25519PublicKey = freezed,Object? website = freezed,Object? deviceModel = freezed,Object? deviceFingerprint = freezed,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,bookCount: null == bookCount ? _self.bookCount : bookCount // ignore: cast_nullable_to_non_nullable
as int,locationCountry: freezed == locationCountry ? _self.locationCountry : locationCountry // ignore: cast_nullable_to_non_nullable
as String?,requiresApproval: null == requiresApproval ? _self.requiresApproval : requiresApproval // ignore: cast_nullable_to_non_nullable
as bool,allowBorrowing: freezed == allowBorrowing ? _self.allowBorrowing : allowBorrowing // ignore: cast_nullable_to_non_nullable
as bool?,lastSeenAt: freezed == lastSeenAt ? _self.lastSeenAt : lastSeenAt // ignore: cast_nullable_to_non_nullable
as String?,x25519PublicKey: freezed == x25519PublicKey ? _self.x25519PublicKey : x25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,website: freezed == website ? _self.website : website // ignore: cast_nullable_to_non_nullable
as String?,deviceModel: freezed == deviceModel ? _self.deviceModel : deviceModel // ignore: cast_nullable_to_non_nullable
as String?,deviceFingerprint: freezed == deviceFingerprint ? _self.deviceFingerprint : deviceFingerprint // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbHubProfile].
extension FrbHubProfilePatterns on FrbHubProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbHubProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbHubProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbHubProfile value)  $default,){
final _that = this;
switch (_that) {
case _FrbHubProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbHubProfile value)?  $default,){
final _that = this;
switch (_that) {
case _FrbHubProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  String displayName,  String? description,  int bookCount,  String? locationCountry,  bool requiresApproval,  bool? allowBorrowing,  String? lastSeenAt,  String? x25519PublicKey,  String? website,  String? deviceModel,  String? deviceFingerprint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbHubProfile() when $default != null:
return $default(_that.nodeId,_that.displayName,_that.description,_that.bookCount,_that.locationCountry,_that.requiresApproval,_that.allowBorrowing,_that.lastSeenAt,_that.x25519PublicKey,_that.website,_that.deviceModel,_that.deviceFingerprint);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  String displayName,  String? description,  int bookCount,  String? locationCountry,  bool requiresApproval,  bool? allowBorrowing,  String? lastSeenAt,  String? x25519PublicKey,  String? website,  String? deviceModel,  String? deviceFingerprint)  $default,) {final _that = this;
switch (_that) {
case _FrbHubProfile():
return $default(_that.nodeId,_that.displayName,_that.description,_that.bookCount,_that.locationCountry,_that.requiresApproval,_that.allowBorrowing,_that.lastSeenAt,_that.x25519PublicKey,_that.website,_that.deviceModel,_that.deviceFingerprint);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  String displayName,  String? description,  int bookCount,  String? locationCountry,  bool requiresApproval,  bool? allowBorrowing,  String? lastSeenAt,  String? x25519PublicKey,  String? website,  String? deviceModel,  String? deviceFingerprint)?  $default,) {final _that = this;
switch (_that) {
case _FrbHubProfile() when $default != null:
return $default(_that.nodeId,_that.displayName,_that.description,_that.bookCount,_that.locationCountry,_that.requiresApproval,_that.allowBorrowing,_that.lastSeenAt,_that.x25519PublicKey,_that.website,_that.deviceModel,_that.deviceFingerprint);case _:
  return null;

}
}

}

/// @nodoc


class _FrbHubProfile implements FrbHubProfile {
  const _FrbHubProfile({required this.nodeId, required this.displayName, this.description, required this.bookCount, this.locationCountry, required this.requiresApproval, this.allowBorrowing, this.lastSeenAt, this.x25519PublicKey, this.website, this.deviceModel, this.deviceFingerprint});


@override final  String nodeId;
@override final  String displayName;
@override final  String? description;
@override final  int bookCount;
@override final  String? locationCountry;
@override final  bool requiresApproval;
@override final  bool? allowBorrowing;
@override final  String? lastSeenAt;
@override final  String? x25519PublicKey;
@override final  String? website;
@override final  String? deviceModel;
@override final  String? deviceFingerprint;

/// Create a copy of FrbHubProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbHubProfileCopyWith<_FrbHubProfile> get copyWith => __$FrbHubProfileCopyWithImpl<_FrbHubProfile>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbHubProfile&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.bookCount, bookCount) || other.bookCount == bookCount)&&(identical(other.locationCountry, locationCountry) || other.locationCountry == locationCountry)&&(identical(other.requiresApproval, requiresApproval) || other.requiresApproval == requiresApproval)&&(identical(other.allowBorrowing, allowBorrowing) || other.allowBorrowing == allowBorrowing)&&(identical(other.lastSeenAt, lastSeenAt) || other.lastSeenAt == lastSeenAt)&&(identical(other.x25519PublicKey, x25519PublicKey) || other.x25519PublicKey == x25519PublicKey)&&(identical(other.website, website) || other.website == website)&&(identical(other.deviceModel, deviceModel) || other.deviceModel == deviceModel)&&(identical(other.deviceFingerprint, deviceFingerprint) || other.deviceFingerprint == deviceFingerprint));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,displayName,description,bookCount,locationCountry,requiresApproval,allowBorrowing,lastSeenAt,x25519PublicKey,website,deviceModel,deviceFingerprint);

@override
String toString() {
  return 'FrbHubProfile(nodeId: $nodeId, displayName: $displayName, description: $description, bookCount: $bookCount, locationCountry: $locationCountry, requiresApproval: $requiresApproval, allowBorrowing: $allowBorrowing, lastSeenAt: $lastSeenAt, x25519PublicKey: $x25519PublicKey, website: $website, deviceModel: $deviceModel, deviceFingerprint: $deviceFingerprint)';
}


}

/// @nodoc
abstract mixin class _$FrbHubProfileCopyWith<$Res> implements $FrbHubProfileCopyWith<$Res> {
  factory _$FrbHubProfileCopyWith(_FrbHubProfile value, $Res Function(_FrbHubProfile) _then) = __$FrbHubProfileCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String displayName, String? description, int bookCount, String? locationCountry, bool requiresApproval, bool? allowBorrowing, String? lastSeenAt, String? x25519PublicKey, String? website, String? deviceModel, String? deviceFingerprint
});




}
/// @nodoc
class __$FrbHubProfileCopyWithImpl<$Res>
    implements _$FrbHubProfileCopyWith<$Res> {
  __$FrbHubProfileCopyWithImpl(this._self, this._then);

  final _FrbHubProfile _self;
  final $Res Function(_FrbHubProfile) _then;

/// Create a copy of FrbHubProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? displayName = null,Object? description = freezed,Object? bookCount = null,Object? locationCountry = freezed,Object? requiresApproval = null,Object? allowBorrowing = freezed,Object? lastSeenAt = freezed,Object? x25519PublicKey = freezed,Object? website = freezed,Object? deviceModel = freezed,Object? deviceFingerprint = freezed,}) {
  return _then(_FrbHubProfile(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,bookCount: null == bookCount ? _self.bookCount : bookCount // ignore: cast_nullable_to_non_nullable
as int,locationCountry: freezed == locationCountry ? _self.locationCountry : locationCountry // ignore: cast_nullable_to_non_nullable
as String?,requiresApproval: null == requiresApproval ? _self.requiresApproval : requiresApproval // ignore: cast_nullable_to_non_nullable
as bool,allowBorrowing: freezed == allowBorrowing ? _self.allowBorrowing : allowBorrowing // ignore: cast_nullable_to_non_nullable
as bool?,lastSeenAt: freezed == lastSeenAt ? _self.lastSeenAt : lastSeenAt // ignore: cast_nullable_to_non_nullable
as String?,x25519PublicKey: freezed == x25519PublicKey ? _self.x25519PublicKey : x25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,website: freezed == website ? _self.website : website // ignore: cast_nullable_to_non_nullable
as String?,deviceModel: freezed == deviceModel ? _self.deviceModel : deviceModel // ignore: cast_nullable_to_non_nullable
as String?,deviceFingerprint: freezed == deviceFingerprint ? _self.deviceFingerprint : deviceFingerprint // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$FrbLoan {

 int get id; int get copyId; int get contactId; int get libraryId; String get loanDate; String get dueDate; String? get returnDate; String get status; String? get notes; String get contactName; String get bookTitle; int? get bookId; String? get coverUrl; String? get isbn;
/// Create a copy of FrbLoan
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbLoanCopyWith<FrbLoan> get copyWith => _$FrbLoanCopyWithImpl<FrbLoan>(this as FrbLoan, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbLoan&&(identical(other.id, id) || other.id == id)&&(identical(other.copyId, copyId) || other.copyId == copyId)&&(identical(other.contactId, contactId) || other.contactId == contactId)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.loanDate, loanDate) || other.loanDate == loanDate)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.returnDate, returnDate) || other.returnDate == returnDate)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.contactName, contactName) || other.contactName == contactName)&&(identical(other.bookTitle, bookTitle) || other.bookTitle == bookTitle)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.isbn, isbn) || other.isbn == isbn));
}


@override
int get hashCode => Object.hash(runtimeType,id,copyId,contactId,libraryId,loanDate,dueDate,returnDate,status,notes,contactName,bookTitle,bookId,coverUrl,isbn);

@override
String toString() {
  return 'FrbLoan(id: $id, copyId: $copyId, contactId: $contactId, libraryId: $libraryId, loanDate: $loanDate, dueDate: $dueDate, returnDate: $returnDate, status: $status, notes: $notes, contactName: $contactName, bookTitle: $bookTitle, bookId: $bookId, coverUrl: $coverUrl, isbn: $isbn)';
}


}

/// @nodoc
abstract mixin class $FrbLoanCopyWith<$Res>  {
  factory $FrbLoanCopyWith(FrbLoan value, $Res Function(FrbLoan) _then) = _$FrbLoanCopyWithImpl;
@useResult
$Res call({
 int id, int copyId, int contactId, int libraryId, String loanDate, String dueDate, String? returnDate, String status, String? notes, String contactName, String bookTitle, int? bookId, String? coverUrl, String? isbn
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? copyId = null,Object? contactId = null,Object? libraryId = null,Object? loanDate = null,Object? dueDate = null,Object? returnDate = freezed,Object? status = null,Object? notes = freezed,Object? contactName = null,Object? bookTitle = null,Object? bookId = freezed,Object? coverUrl = freezed,Object? isbn = freezed,}) {
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
as String,bookId: freezed == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as int?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,isbn: freezed == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int copyId,  int contactId,  int libraryId,  String loanDate,  String dueDate,  String? returnDate,  String status,  String? notes,  String contactName,  String bookTitle,  int? bookId,  String? coverUrl,  String? isbn)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbLoan() when $default != null:
return $default(_that.id,_that.copyId,_that.contactId,_that.libraryId,_that.loanDate,_that.dueDate,_that.returnDate,_that.status,_that.notes,_that.contactName,_that.bookTitle,_that.bookId,_that.coverUrl,_that.isbn);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int copyId,  int contactId,  int libraryId,  String loanDate,  String dueDate,  String? returnDate,  String status,  String? notes,  String contactName,  String bookTitle,  int? bookId,  String? coverUrl,  String? isbn)  $default,) {final _that = this;
switch (_that) {
case _FrbLoan():
return $default(_that.id,_that.copyId,_that.contactId,_that.libraryId,_that.loanDate,_that.dueDate,_that.returnDate,_that.status,_that.notes,_that.contactName,_that.bookTitle,_that.bookId,_that.coverUrl,_that.isbn);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int copyId,  int contactId,  int libraryId,  String loanDate,  String dueDate,  String? returnDate,  String status,  String? notes,  String contactName,  String bookTitle,  int? bookId,  String? coverUrl,  String? isbn)?  $default,) {final _that = this;
switch (_that) {
case _FrbLoan() when $default != null:
return $default(_that.id,_that.copyId,_that.contactId,_that.libraryId,_that.loanDate,_that.dueDate,_that.returnDate,_that.status,_that.notes,_that.contactName,_that.bookTitle,_that.bookId,_that.coverUrl,_that.isbn);case _:
  return null;

}
}

}

/// @nodoc


class _FrbLoan implements FrbLoan {
  const _FrbLoan({required this.id, required this.copyId, required this.contactId, required this.libraryId, required this.loanDate, required this.dueDate, this.returnDate, required this.status, this.notes, required this.contactName, required this.bookTitle, this.bookId, this.coverUrl, this.isbn});
  

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
@override final  int? bookId;
@override final  String? coverUrl;
@override final  String? isbn;

/// Create a copy of FrbLoan
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbLoanCopyWith<_FrbLoan> get copyWith => __$FrbLoanCopyWithImpl<_FrbLoan>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbLoan&&(identical(other.id, id) || other.id == id)&&(identical(other.copyId, copyId) || other.copyId == copyId)&&(identical(other.contactId, contactId) || other.contactId == contactId)&&(identical(other.libraryId, libraryId) || other.libraryId == libraryId)&&(identical(other.loanDate, loanDate) || other.loanDate == loanDate)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.returnDate, returnDate) || other.returnDate == returnDate)&&(identical(other.status, status) || other.status == status)&&(identical(other.notes, notes) || other.notes == notes)&&(identical(other.contactName, contactName) || other.contactName == contactName)&&(identical(other.bookTitle, bookTitle) || other.bookTitle == bookTitle)&&(identical(other.bookId, bookId) || other.bookId == bookId)&&(identical(other.coverUrl, coverUrl) || other.coverUrl == coverUrl)&&(identical(other.isbn, isbn) || other.isbn == isbn));
}


@override
int get hashCode => Object.hash(runtimeType,id,copyId,contactId,libraryId,loanDate,dueDate,returnDate,status,notes,contactName,bookTitle,bookId,coverUrl,isbn);

@override
String toString() {
  return 'FrbLoan(id: $id, copyId: $copyId, contactId: $contactId, libraryId: $libraryId, loanDate: $loanDate, dueDate: $dueDate, returnDate: $returnDate, status: $status, notes: $notes, contactName: $contactName, bookTitle: $bookTitle, bookId: $bookId, coverUrl: $coverUrl, isbn: $isbn)';
}


}

/// @nodoc
abstract mixin class _$FrbLoanCopyWith<$Res> implements $FrbLoanCopyWith<$Res> {
  factory _$FrbLoanCopyWith(_FrbLoan value, $Res Function(_FrbLoan) _then) = __$FrbLoanCopyWithImpl;
@override @useResult
$Res call({
 int id, int copyId, int contactId, int libraryId, String loanDate, String dueDate, String? returnDate, String status, String? notes, String contactName, String bookTitle, int? bookId, String? coverUrl, String? isbn
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? copyId = null,Object? contactId = null,Object? libraryId = null,Object? loanDate = null,Object? dueDate = null,Object? returnDate = freezed,Object? status = null,Object? notes = freezed,Object? contactName = null,Object? bookTitle = null,Object? bookId = freezed,Object? coverUrl = freezed,Object? isbn = freezed,}) {
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
as String,bookId: freezed == bookId ? _self.bookId : bookId // ignore: cast_nullable_to_non_nullable
as int?,coverUrl: freezed == coverUrl ? _self.coverUrl : coverUrl // ignore: cast_nullable_to_non_nullable
as String?,isbn: freezed == isbn ? _self.isbn : isbn // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$FrbOperationLogEntry {

 int get id; String get entityType; int get entityId; String get operation; String? get payload; String get status; String? get errorMessage; bool get pinned; String get createdAt;
/// Create a copy of FrbOperationLogEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbOperationLogEntryCopyWith<FrbOperationLogEntry> get copyWith => _$FrbOperationLogEntryCopyWithImpl<FrbOperationLogEntry>(this as FrbOperationLogEntry, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbOperationLogEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.entityType, entityType) || other.entityType == entityType)&&(identical(other.entityId, entityId) || other.entityId == entityId)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.status, status) || other.status == status)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,entityType,entityId,operation,payload,status,errorMessage,pinned,createdAt);

@override
String toString() {
  return 'FrbOperationLogEntry(id: $id, entityType: $entityType, entityId: $entityId, operation: $operation, payload: $payload, status: $status, errorMessage: $errorMessage, pinned: $pinned, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class $FrbOperationLogEntryCopyWith<$Res>  {
  factory $FrbOperationLogEntryCopyWith(FrbOperationLogEntry value, $Res Function(FrbOperationLogEntry) _then) = _$FrbOperationLogEntryCopyWithImpl;
@useResult
$Res call({
 int id, String entityType, int entityId, String operation, String? payload, String status, String? errorMessage, bool pinned, String createdAt
});




}
/// @nodoc
class _$FrbOperationLogEntryCopyWithImpl<$Res>
    implements $FrbOperationLogEntryCopyWith<$Res> {
  _$FrbOperationLogEntryCopyWithImpl(this._self, this._then);

  final FrbOperationLogEntry _self;
  final $Res Function(FrbOperationLogEntry) _then;

/// Create a copy of FrbOperationLogEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? entityType = null,Object? entityId = null,Object? operation = null,Object? payload = freezed,Object? status = null,Object? errorMessage = freezed,Object? pinned = null,Object? createdAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,entityType: null == entityType ? _self.entityType : entityType // ignore: cast_nullable_to_non_nullable
as String,entityId: null == entityId ? _self.entityId : entityId // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as String,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbOperationLogEntry].
extension FrbOperationLogEntryPatterns on FrbOperationLogEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbOperationLogEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbOperationLogEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbOperationLogEntry value)  $default,){
final _that = this;
switch (_that) {
case _FrbOperationLogEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbOperationLogEntry value)?  $default,){
final _that = this;
switch (_that) {
case _FrbOperationLogEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  String entityType,  int entityId,  String operation,  String? payload,  String status,  String? errorMessage,  bool pinned,  String createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbOperationLogEntry() when $default != null:
return $default(_that.id,_that.entityType,_that.entityId,_that.operation,_that.payload,_that.status,_that.errorMessage,_that.pinned,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  String entityType,  int entityId,  String operation,  String? payload,  String status,  String? errorMessage,  bool pinned,  String createdAt)  $default,) {final _that = this;
switch (_that) {
case _FrbOperationLogEntry():
return $default(_that.id,_that.entityType,_that.entityId,_that.operation,_that.payload,_that.status,_that.errorMessage,_that.pinned,_that.createdAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  String entityType,  int entityId,  String operation,  String? payload,  String status,  String? errorMessage,  bool pinned,  String createdAt)?  $default,) {final _that = this;
switch (_that) {
case _FrbOperationLogEntry() when $default != null:
return $default(_that.id,_that.entityType,_that.entityId,_that.operation,_that.payload,_that.status,_that.errorMessage,_that.pinned,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _FrbOperationLogEntry implements FrbOperationLogEntry {
  const _FrbOperationLogEntry({required this.id, required this.entityType, required this.entityId, required this.operation, this.payload, required this.status, this.errorMessage, required this.pinned, required this.createdAt});
  

@override final  int id;
@override final  String entityType;
@override final  int entityId;
@override final  String operation;
@override final  String? payload;
@override final  String status;
@override final  String? errorMessage;
@override final  bool pinned;
@override final  String createdAt;

/// Create a copy of FrbOperationLogEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbOperationLogEntryCopyWith<_FrbOperationLogEntry> get copyWith => __$FrbOperationLogEntryCopyWithImpl<_FrbOperationLogEntry>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbOperationLogEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.entityType, entityType) || other.entityType == entityType)&&(identical(other.entityId, entityId) || other.entityId == entityId)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.payload, payload) || other.payload == payload)&&(identical(other.status, status) || other.status == status)&&(identical(other.errorMessage, errorMessage) || other.errorMessage == errorMessage)&&(identical(other.pinned, pinned) || other.pinned == pinned)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode => Object.hash(runtimeType,id,entityType,entityId,operation,payload,status,errorMessage,pinned,createdAt);

@override
String toString() {
  return 'FrbOperationLogEntry(id: $id, entityType: $entityType, entityId: $entityId, operation: $operation, payload: $payload, status: $status, errorMessage: $errorMessage, pinned: $pinned, createdAt: $createdAt)';
}


}

/// @nodoc
abstract mixin class _$FrbOperationLogEntryCopyWith<$Res> implements $FrbOperationLogEntryCopyWith<$Res> {
  factory _$FrbOperationLogEntryCopyWith(_FrbOperationLogEntry value, $Res Function(_FrbOperationLogEntry) _then) = __$FrbOperationLogEntryCopyWithImpl;
@override @useResult
$Res call({
 int id, String entityType, int entityId, String operation, String? payload, String status, String? errorMessage, bool pinned, String createdAt
});




}
/// @nodoc
class __$FrbOperationLogEntryCopyWithImpl<$Res>
    implements _$FrbOperationLogEntryCopyWith<$Res> {
  __$FrbOperationLogEntryCopyWithImpl(this._self, this._then);

  final _FrbOperationLogEntry _self;
  final $Res Function(_FrbOperationLogEntry) _then;

/// Create a copy of FrbOperationLogEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? entityType = null,Object? entityId = null,Object? operation = null,Object? payload = freezed,Object? status = null,Object? errorMessage = freezed,Object? pinned = null,Object? createdAt = null,}) {
  return _then(_FrbOperationLogEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,entityType: null == entityType ? _self.entityType : entityType // ignore: cast_nullable_to_non_nullable
as String,entityId: null == entityId ? _self.entityId : entityId // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as String,payload: freezed == payload ? _self.payload : payload // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,pinned: null == pinned ? _self.pinned : pinned // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$FrbOperationLogStats {

 BigInt get total; BigInt get today; BigInt get pending; BigInt get failed;
/// Create a copy of FrbOperationLogStats
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbOperationLogStatsCopyWith<FrbOperationLogStats> get copyWith => _$FrbOperationLogStatsCopyWithImpl<FrbOperationLogStats>(this as FrbOperationLogStats, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbOperationLogStats&&(identical(other.total, total) || other.total == total)&&(identical(other.today, today) || other.today == today)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.failed, failed) || other.failed == failed));
}


@override
int get hashCode => Object.hash(runtimeType,total,today,pending,failed);

@override
String toString() {
  return 'FrbOperationLogStats(total: $total, today: $today, pending: $pending, failed: $failed)';
}


}

/// @nodoc
abstract mixin class $FrbOperationLogStatsCopyWith<$Res>  {
  factory $FrbOperationLogStatsCopyWith(FrbOperationLogStats value, $Res Function(FrbOperationLogStats) _then) = _$FrbOperationLogStatsCopyWithImpl;
@useResult
$Res call({
 BigInt total, BigInt today, BigInt pending, BigInt failed
});




}
/// @nodoc
class _$FrbOperationLogStatsCopyWithImpl<$Res>
    implements $FrbOperationLogStatsCopyWith<$Res> {
  _$FrbOperationLogStatsCopyWithImpl(this._self, this._then);

  final FrbOperationLogStats _self;
  final $Res Function(FrbOperationLogStats) _then;

/// Create a copy of FrbOperationLogStats
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? total = null,Object? today = null,Object? pending = null,Object? failed = null,}) {
  return _then(_self.copyWith(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,today: null == today ? _self.today : today // ignore: cast_nullable_to_non_nullable
as BigInt,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as BigInt,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbOperationLogStats].
extension FrbOperationLogStatsPatterns on FrbOperationLogStats {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbOperationLogStats value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbOperationLogStats() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbOperationLogStats value)  $default,){
final _that = this;
switch (_that) {
case _FrbOperationLogStats():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbOperationLogStats value)?  $default,){
final _that = this;
switch (_that) {
case _FrbOperationLogStats() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( BigInt total,  BigInt today,  BigInt pending,  BigInt failed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbOperationLogStats() when $default != null:
return $default(_that.total,_that.today,_that.pending,_that.failed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( BigInt total,  BigInt today,  BigInt pending,  BigInt failed)  $default,) {final _that = this;
switch (_that) {
case _FrbOperationLogStats():
return $default(_that.total,_that.today,_that.pending,_that.failed);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( BigInt total,  BigInt today,  BigInt pending,  BigInt failed)?  $default,) {final _that = this;
switch (_that) {
case _FrbOperationLogStats() when $default != null:
return $default(_that.total,_that.today,_that.pending,_that.failed);case _:
  return null;

}
}

}

/// @nodoc


class _FrbOperationLogStats implements FrbOperationLogStats {
  const _FrbOperationLogStats({required this.total, required this.today, required this.pending, required this.failed});
  

@override final  BigInt total;
@override final  BigInt today;
@override final  BigInt pending;
@override final  BigInt failed;

/// Create a copy of FrbOperationLogStats
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbOperationLogStatsCopyWith<_FrbOperationLogStats> get copyWith => __$FrbOperationLogStatsCopyWithImpl<_FrbOperationLogStats>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbOperationLogStats&&(identical(other.total, total) || other.total == total)&&(identical(other.today, today) || other.today == today)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.failed, failed) || other.failed == failed));
}


@override
int get hashCode => Object.hash(runtimeType,total,today,pending,failed);

@override
String toString() {
  return 'FrbOperationLogStats(total: $total, today: $today, pending: $pending, failed: $failed)';
}


}

/// @nodoc
abstract mixin class _$FrbOperationLogStatsCopyWith<$Res> implements $FrbOperationLogStatsCopyWith<$Res> {
  factory _$FrbOperationLogStatsCopyWith(_FrbOperationLogStats value, $Res Function(_FrbOperationLogStats) _then) = __$FrbOperationLogStatsCopyWithImpl;
@override @useResult
$Res call({
 BigInt total, BigInt today, BigInt pending, BigInt failed
});




}
/// @nodoc
class __$FrbOperationLogStatsCopyWithImpl<$Res>
    implements _$FrbOperationLogStatsCopyWith<$Res> {
  __$FrbOperationLogStatsCopyWithImpl(this._self, this._then);

  final _FrbOperationLogStats _self;
  final $Res Function(_FrbOperationLogStats) _then;

/// Create a copy of FrbOperationLogStats
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? total = null,Object? today = null,Object? pending = null,Object? failed = null,}) {
  return _then(_FrbOperationLogStats(
total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as BigInt,today: null == today ? _self.today : today // ignore: cast_nullable_to_non_nullable
as BigInt,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as BigInt,failed: null == failed ? _self.failed : failed // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc
mixin _$FrbRegisterParams {

 String get nodeId; String get displayName; int get bookCount; bool get isListed; bool get requiresApproval; String get acceptFrom; String? get description; String? get locationCountry; bool get allowBorrowing; String? get x25519PublicKey; String? get website; String? get deviceModel; String? get deviceFingerprint;
/// Create a copy of FrbRegisterParams
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FrbRegisterParamsCopyWith<FrbRegisterParams> get copyWith => _$FrbRegisterParamsCopyWithImpl<FrbRegisterParams>(this as FrbRegisterParams, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FrbRegisterParams&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.bookCount, bookCount) || other.bookCount == bookCount)&&(identical(other.isListed, isListed) || other.isListed == isListed)&&(identical(other.requiresApproval, requiresApproval) || other.requiresApproval == requiresApproval)&&(identical(other.acceptFrom, acceptFrom) || other.acceptFrom == acceptFrom)&&(identical(other.description, description) || other.description == description)&&(identical(other.locationCountry, locationCountry) || other.locationCountry == locationCountry)&&(identical(other.allowBorrowing, allowBorrowing) || other.allowBorrowing == allowBorrowing)&&(identical(other.x25519PublicKey, x25519PublicKey) || other.x25519PublicKey == x25519PublicKey)&&(identical(other.website, website) || other.website == website)&&(identical(other.deviceModel, deviceModel) || other.deviceModel == deviceModel)&&(identical(other.deviceFingerprint, deviceFingerprint) || other.deviceFingerprint == deviceFingerprint));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,displayName,bookCount,isListed,requiresApproval,acceptFrom,description,locationCountry,allowBorrowing,x25519PublicKey,website,deviceModel,deviceFingerprint);

@override
String toString() {
  return 'FrbRegisterParams(nodeId: $nodeId, displayName: $displayName, bookCount: $bookCount, isListed: $isListed, requiresApproval: $requiresApproval, acceptFrom: $acceptFrom, description: $description, locationCountry: $locationCountry, allowBorrowing: $allowBorrowing, x25519PublicKey: $x25519PublicKey, website: $website, deviceModel: $deviceModel, deviceFingerprint: $deviceFingerprint)';
}


}

/// @nodoc
abstract mixin class $FrbRegisterParamsCopyWith<$Res>  {
  factory $FrbRegisterParamsCopyWith(FrbRegisterParams value, $Res Function(FrbRegisterParams) _then) = _$FrbRegisterParamsCopyWithImpl;
@useResult
$Res call({
 String nodeId, String displayName, int bookCount, bool isListed, bool requiresApproval, String acceptFrom, String? description, String? locationCountry, bool allowBorrowing, String? x25519PublicKey, String? website, String? deviceModel, String? deviceFingerprint
});




}
/// @nodoc
class _$FrbRegisterParamsCopyWithImpl<$Res>
    implements $FrbRegisterParamsCopyWith<$Res> {
  _$FrbRegisterParamsCopyWithImpl(this._self, this._then);

  final FrbRegisterParams _self;
  final $Res Function(FrbRegisterParams) _then;

/// Create a copy of FrbRegisterParams
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? nodeId = null,Object? displayName = null,Object? bookCount = null,Object? isListed = null,Object? requiresApproval = null,Object? acceptFrom = null,Object? description = freezed,Object? locationCountry = freezed,Object? allowBorrowing = null,Object? x25519PublicKey = freezed,Object? website = freezed,Object? deviceModel = freezed,Object? deviceFingerprint = freezed,}) {
  return _then(_self.copyWith(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,bookCount: null == bookCount ? _self.bookCount : bookCount // ignore: cast_nullable_to_non_nullable
as int,isListed: null == isListed ? _self.isListed : isListed // ignore: cast_nullable_to_non_nullable
as bool,requiresApproval: null == requiresApproval ? _self.requiresApproval : requiresApproval // ignore: cast_nullable_to_non_nullable
as bool,acceptFrom: null == acceptFrom ? _self.acceptFrom : acceptFrom // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,locationCountry: freezed == locationCountry ? _self.locationCountry : locationCountry // ignore: cast_nullable_to_non_nullable
as String?,allowBorrowing: null == allowBorrowing ? _self.allowBorrowing : allowBorrowing // ignore: cast_nullable_to_non_nullable
as bool,x25519PublicKey: freezed == x25519PublicKey ? _self.x25519PublicKey : x25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,website: freezed == website ? _self.website : website // ignore: cast_nullable_to_non_nullable
as String?,deviceModel: freezed == deviceModel ? _self.deviceModel : deviceModel // ignore: cast_nullable_to_non_nullable
as String?,deviceFingerprint: freezed == deviceFingerprint ? _self.deviceFingerprint : deviceFingerprint // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [FrbRegisterParams].
extension FrbRegisterParamsPatterns on FrbRegisterParams {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FrbRegisterParams value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FrbRegisterParams() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FrbRegisterParams value)  $default,){
final _that = this;
switch (_that) {
case _FrbRegisterParams():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FrbRegisterParams value)?  $default,){
final _that = this;
switch (_that) {
case _FrbRegisterParams() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String nodeId,  String displayName,  int bookCount,  bool isListed,  bool requiresApproval,  String acceptFrom,  String? description,  String? locationCountry,  bool allowBorrowing,  String? x25519PublicKey,  String? website,  String? deviceModel,  String? deviceFingerprint)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FrbRegisterParams() when $default != null:
return $default(_that.nodeId,_that.displayName,_that.bookCount,_that.isListed,_that.requiresApproval,_that.acceptFrom,_that.description,_that.locationCountry,_that.allowBorrowing,_that.x25519PublicKey,_that.website,_that.deviceModel,_that.deviceFingerprint);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String nodeId,  String displayName,  int bookCount,  bool isListed,  bool requiresApproval,  String acceptFrom,  String? description,  String? locationCountry,  bool allowBorrowing,  String? x25519PublicKey,  String? website,  String? deviceModel,  String? deviceFingerprint)  $default,) {final _that = this;
switch (_that) {
case _FrbRegisterParams():
return $default(_that.nodeId,_that.displayName,_that.bookCount,_that.isListed,_that.requiresApproval,_that.acceptFrom,_that.description,_that.locationCountry,_that.allowBorrowing,_that.x25519PublicKey,_that.website,_that.deviceModel,_that.deviceFingerprint);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String nodeId,  String displayName,  int bookCount,  bool isListed,  bool requiresApproval,  String acceptFrom,  String? description,  String? locationCountry,  bool allowBorrowing,  String? x25519PublicKey,  String? website,  String? deviceModel,  String? deviceFingerprint)?  $default,) {final _that = this;
switch (_that) {
case _FrbRegisterParams() when $default != null:
return $default(_that.nodeId,_that.displayName,_that.bookCount,_that.isListed,_that.requiresApproval,_that.acceptFrom,_that.description,_that.locationCountry,_that.allowBorrowing,_that.x25519PublicKey,_that.website,_that.deviceModel,_that.deviceFingerprint);case _:
  return null;

}
}

}

/// @nodoc


class _FrbRegisterParams implements FrbRegisterParams {
  const _FrbRegisterParams({required this.nodeId, required this.displayName, required this.bookCount, required this.isListed, required this.requiresApproval, required this.acceptFrom, this.description, this.locationCountry, required this.allowBorrowing, this.x25519PublicKey, this.website, this.deviceModel, this.deviceFingerprint});


@override final  String nodeId;
@override final  String displayName;
@override final  int bookCount;
@override final  bool isListed;
@override final  bool requiresApproval;
@override final  String acceptFrom;
@override final  String? description;
@override final  String? locationCountry;
@override final  bool allowBorrowing;
@override final  String? x25519PublicKey;
@override final  String? website;
@override final  String? deviceModel;
@override final  String? deviceFingerprint;

/// Create a copy of FrbRegisterParams
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FrbRegisterParamsCopyWith<_FrbRegisterParams> get copyWith => __$FrbRegisterParamsCopyWithImpl<_FrbRegisterParams>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FrbRegisterParams&&(identical(other.nodeId, nodeId) || other.nodeId == nodeId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.bookCount, bookCount) || other.bookCount == bookCount)&&(identical(other.isListed, isListed) || other.isListed == isListed)&&(identical(other.requiresApproval, requiresApproval) || other.requiresApproval == requiresApproval)&&(identical(other.acceptFrom, acceptFrom) || other.acceptFrom == acceptFrom)&&(identical(other.description, description) || other.description == description)&&(identical(other.locationCountry, locationCountry) || other.locationCountry == locationCountry)&&(identical(other.allowBorrowing, allowBorrowing) || other.allowBorrowing == allowBorrowing)&&(identical(other.x25519PublicKey, x25519PublicKey) || other.x25519PublicKey == x25519PublicKey)&&(identical(other.website, website) || other.website == website)&&(identical(other.deviceModel, deviceModel) || other.deviceModel == deviceModel)&&(identical(other.deviceFingerprint, deviceFingerprint) || other.deviceFingerprint == deviceFingerprint));
}


@override
int get hashCode => Object.hash(runtimeType,nodeId,displayName,bookCount,isListed,requiresApproval,acceptFrom,description,locationCountry,allowBorrowing,x25519PublicKey,website,deviceModel,deviceFingerprint);

@override
String toString() {
  return 'FrbRegisterParams(nodeId: $nodeId, displayName: $displayName, bookCount: $bookCount, isListed: $isListed, requiresApproval: $requiresApproval, acceptFrom: $acceptFrom, description: $description, locationCountry: $locationCountry, allowBorrowing: $allowBorrowing, x25519PublicKey: $x25519PublicKey, website: $website, deviceModel: $deviceModel, deviceFingerprint: $deviceFingerprint)';
}


}

/// @nodoc
abstract mixin class _$FrbRegisterParamsCopyWith<$Res> implements $FrbRegisterParamsCopyWith<$Res> {
  factory _$FrbRegisterParamsCopyWith(_FrbRegisterParams value, $Res Function(_FrbRegisterParams) _then) = __$FrbRegisterParamsCopyWithImpl;
@override @useResult
$Res call({
 String nodeId, String displayName, int bookCount, bool isListed, bool requiresApproval, String acceptFrom, String? description, String? locationCountry, bool allowBorrowing, String? x25519PublicKey, String? website, String? deviceModel, String? deviceFingerprint
});




}
/// @nodoc
class __$FrbRegisterParamsCopyWithImpl<$Res>
    implements _$FrbRegisterParamsCopyWith<$Res> {
  __$FrbRegisterParamsCopyWithImpl(this._self, this._then);

  final _FrbRegisterParams _self;
  final $Res Function(_FrbRegisterParams) _then;

/// Create a copy of FrbRegisterParams
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? nodeId = null,Object? displayName = null,Object? bookCount = null,Object? isListed = null,Object? requiresApproval = null,Object? acceptFrom = null,Object? description = freezed,Object? locationCountry = freezed,Object? allowBorrowing = null,Object? x25519PublicKey = freezed,Object? website = freezed,Object? deviceModel = freezed,Object? deviceFingerprint = freezed,}) {
  return _then(_FrbRegisterParams(
nodeId: null == nodeId ? _self.nodeId : nodeId // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,bookCount: null == bookCount ? _self.bookCount : bookCount // ignore: cast_nullable_to_non_nullable
as int,isListed: null == isListed ? _self.isListed : isListed // ignore: cast_nullable_to_non_nullable
as bool,requiresApproval: null == requiresApproval ? _self.requiresApproval : requiresApproval // ignore: cast_nullable_to_non_nullable
as bool,acceptFrom: null == acceptFrom ? _self.acceptFrom : acceptFrom // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,locationCountry: freezed == locationCountry ? _self.locationCountry : locationCountry // ignore: cast_nullable_to_non_nullable
as String?,allowBorrowing: null == allowBorrowing ? _self.allowBorrowing : allowBorrowing // ignore: cast_nullable_to_non_nullable
as bool,x25519PublicKey: freezed == x25519PublicKey ? _self.x25519PublicKey : x25519PublicKey // ignore: cast_nullable_to_non_nullable
as String?,website: freezed == website ? _self.website : website // ignore: cast_nullable_to_non_nullable
as String?,deviceModel: freezed == deviceModel ? _self.deviceModel : deviceModel // ignore: cast_nullable_to_non_nullable
as String?,deviceFingerprint: freezed == deviceFingerprint ? _self.deviceFingerprint : deviceFingerprint // ignore: cast_nullable_to_non_nullable
as String?,
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
