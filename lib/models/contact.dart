class Contact {
  /// Cross-device stable identity (the contact's uuid). Backend-owned; null for
  /// transient/peer contacts or rows not yet persisted. Addresses a contact
  /// over FFI. Callers that still hold an integer local id (loan references)
  /// resolve through [localId] until the wire flip retires it.
  final String? id;

  /// Transitional device-local integer id. Still required by int-keyed
  /// references (loans, the dormant web HTTP leg) until those callers address
  /// contacts by uuid. Removed with the wire flip.
  final int? localId;

  /// Backwards-compatible alias: the uuid is now the primary [id].
  String? get uuid => id;

  final String type; // 'borrower', 'library', 'user'
  final String name;
  final String? firstName;
  final String? email;
  final String? phone;
  final String? address;
  final String? streetAddress;
  final String? postalCode;
  final String? city;
  final String? country;
  final double? latitude;
  final double? longitude;
  final String? notes;
  final int? userId;
  final int? libraryOwnerId;
  final bool isActive;

  /// True when the contact's peer owns the book requested in the borrow dialog.
  /// Null when no book context was provided (e.g. regular contact list fetch).
  final bool? hasBook;

  Contact({
    this.id,
    this.localId,
    required this.type,
    required this.name,
    this.firstName,
    this.email,
    this.phone,
    this.address,
    this.streetAddress,
    this.postalCode,
    this.city,
    this.country,
    this.latitude,
    this.longitude,
    this.notes,
    this.userId,
    this.libraryOwnerId,
    this.isActive = true,
    this.hasBook,
  });

  /// Returns display name: firstName if available, otherwise name
  String get displayName => firstName?.isNotEmpty == true ? firstName! : name;

  /// Returns full name: firstName + name if firstName is available, otherwise name
  String get fullName {
    if (firstName != null && firstName!.isNotEmpty && name.isNotEmpty) {
      return '$firstName $name';
    }
    return name;
  }

  /// Returns formatted full address from structured fields
  String get formattedAddress {
    final parts = <String>[];
    if (streetAddress != null && streetAddress!.isNotEmpty) {
      parts.add(streetAddress!);
    }
    if (postalCode != null && postalCode!.isNotEmpty) {
      parts.add(postalCode!);
    }
    if (city != null && city!.isNotEmpty) {
      parts.add(city!);
    }
    if (country != null && country!.isNotEmpty) {
      parts.add(country!);
    }
    return parts.isNotEmpty ? parts.join(', ') : (address ?? '');
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      // Identity is the uuid; the integer `id` becomes the transitional localId.
      id: json['uuid'] as String?,
      localId: json['id'] as int?,
      type: (json['type'] ?? json['contact_type'] ?? 'borrower') as String,
      name: json['name'] as String,
      firstName: json['first_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      streetAddress: json['street_address'] as String?,
      postalCode: json['postal_code'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      userId: json['user_id'] as int?,
      libraryOwnerId: json['library_owner_id'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      hasBook: json['has_book'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // `id` carries the transitional integer local id; `uuid` is the identity.
      if (localId != null) 'id': localId,
      if (id != null) 'uuid': id,
      'type': type,
      'name': name,
      'first_name': firstName,
      'email': email,
      'phone': phone,
      'address': address,
      'street_address': streetAddress,
      'postal_code': postalCode,
      'city': city,
      'country': country,
      'latitude': latitude,
      'longitude': longitude,
      'notes': notes,
      'user_id': userId,
      'library_owner_id': libraryOwnerId,
      'is_active': isActive,
      if (hasBook != null) 'has_book': hasBook,
    };
  }
}
