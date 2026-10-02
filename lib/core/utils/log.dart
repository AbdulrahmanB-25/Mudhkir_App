import 'package:flutter/foundation.dart';

/// Debug-only logging. Nothing is printed in release builds.
void log(String tag, String message, [Object? error, StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('[$tag] $message${error != null ? ' — $error' : ''}');
  if (stack != null) debugPrint(stack.toString());
}
