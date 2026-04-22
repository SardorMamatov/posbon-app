import 'package:flutter/material.dart';

enum SafeCategory { banking, email, social, work, other }

extension SafeCategoryX on SafeCategory {
  String get label => switch (this) {
        SafeCategory.banking => 'Bank',
        SafeCategory.email => 'Email',
        SafeCategory.social => 'Ijtimoiy',
        SafeCategory.work => 'Ish',
        SafeCategory.other => 'Boshqa',
      };

  IconData get icon => switch (this) {
        SafeCategory.banking => Icons.account_balance_wallet_rounded,
        SafeCategory.email => Icons.mail_outline_rounded,
        SafeCategory.social => Icons.people_alt_outlined,
        SafeCategory.work => Icons.work_outline_rounded,
        SafeCategory.other => Icons.lock_outline_rounded,
      };
}

class SafeCredential {
  const SafeCredential({
    required this.id,
    required this.site,
    required this.username,
    required this.password,
    required this.category,
    required this.createdAt,
    this.website,
    this.note,
  });

  final String id;
  final String site;
  final String username;
  final String password;
  final SafeCategory category;
  final String? note;
  final String? website;
  final DateTime createdAt;

  SafeCredential copyWith({
    String? id,
    String? site,
    String? username,
    String? password,
    SafeCategory? category,
    String? note,
    String? website,
    DateTime? createdAt,
  }) {
    return SafeCredential(
      id: id ?? this.id,
      site: site ?? this.site,
      username: username ?? this.username,
      password: password ?? this.password,
      category: category ?? this.category,
      note: note ?? this.note,
      website: website ?? this.website,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'site': site,
      'username': username,
      'password': password,
      'category': category.name,
      'note': note,
      'website': website,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory SafeCredential.fromJson(Map<String, dynamic> json) {
    return SafeCredential(
      id: json['id']?.toString() ?? '',
      site: json['site']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      password: json['password']?.toString() ?? '',
      category: SafeCategory.values.firstWhere(
        (value) => value.name == json['category']?.toString(),
        orElse: () => SafeCategory.other,
      ),
      note: json['note']?.toString(),
      website: json['website']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
