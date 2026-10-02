import 'package:flutter/foundation.dart';

@immutable
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.updatedAt,
    this.email,
  });

  final String id;
  final String name;
  final String? email;
  final DateTime updatedAt;
}
