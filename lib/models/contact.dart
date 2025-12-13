class Contact {
  final int? id;
  final String type; // 'borrower', 'library', 'user'
  final String name;
  final String? firstName;
  final String? email;
  final String? phone;
  final String? address;
  final String? notes;
  final int? userId;
  final int libraryOwnerId;
  final bool isActive;

  Contact({
    this.id,
    required this.type,
    required this.name,
    this.firstName,
    this.email,
    this.phone,
    this.address,
    this.notes,
    this.userId,
    required this.libraryOwnerId,
    this.isActive = true,
  });

  /// Returns display name: firstName if available, otherwise name
  String get displayName => firstName?.isNotEmpty == true ? firstName! : name;

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as int?,
      type: json['type'] as String,
      name: json['name'] as String,
      firstName: json['first_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      address: json['address'] as String?,
      notes: json['notes'] as String?,
      userId: json['user_id'] as int?,
      libraryOwnerId: json['library_owner_id'] as int,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'name': name,
      'first_name': firstName,
      'email': email,
      'phone': phone,
      'address': address,
      'notes': notes,
      'user_id': userId,
      'library_owner_id': libraryOwnerId,
      'is_active': isActive,
    };
  }
}

