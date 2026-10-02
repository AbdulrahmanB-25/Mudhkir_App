import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A new random id for locally created rows. Random v4 ids never clash
/// between devices, so rows can be created offline and synced later.
String newId() => _uuid.v4();
