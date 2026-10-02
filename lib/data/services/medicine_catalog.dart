import 'dart:convert';

import 'package:flutter/services.dart';

/// Medicine trade names for autocomplete, bundled with the app so it works
/// offline (about 5,000 names).
class MedicineCatalog {
  MedicineCatalog({AssetBundle? bundle}) : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;
  List<String>? _names;

  Future<List<String>> names() async {
    final cached = _names;
    if (cached != null) return cached;
    final raw = await _bundle.loadString('assets/medicines/trade_names.json');
    final list = (jsonDecode(raw) as List<dynamic>).cast<String>();
    return _names = list.toSet().toList()..sort();
  }

  /// Names starting with [query] first, then names containing it.
  Future<List<String>> search(String query, {int limit = 8}) async {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    final all = await names();
    final starts = <String>[];
    final contains = <String>[];
    for (final name in all) {
      final lower = name.toLowerCase();
      if (lower.startsWith(q)) {
        starts.add(name);
      } else if (lower.contains(q)) {
        contains.add(name);
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }
}
