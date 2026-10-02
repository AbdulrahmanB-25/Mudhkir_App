import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';

/// Runs one account action at a time and exposes busy/error state to the
/// auth and profile screens.
class AuthAction extends ChangeNotifier {
  bool _busy = false;
  AuthFailureReason? _error;

  bool get busy => _busy;
  AuthFailureReason? get error => _error;

  /// Returns true on success.
  Future<bool> run(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthFailure catch (e) {
      _error = e.reason;
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }
}
