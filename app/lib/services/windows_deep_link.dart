import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

/// Registers the `io.fintrack.app://` URL scheme for the current user so the
/// browser can hand OAuth / email-link callbacks back to the desktop app.
/// The installer registers it too; doing it at startup also covers
/// `flutter run` builds and moved installs.
void registerWindowsUrlScheme(String scheme) {
  if (!Platform.isWindows) return;
  try {
    final exe = Platform.resolvedExecutable;
    final key = CURRENT_USER.create('Software\\Classes\\$scheme');
    key.setValue('', RegistryValue.string('URL:$scheme'));
    key.setValue('URL Protocol', const RegistryValue.string(''));
    final command = key.create('shell\\open\\command');
    command.setValue('', RegistryValue.string('"$exe" "%1"'));
    command.close();
    key.close();
  } catch (e) {
    debugPrint('Could not register URL scheme: $e');
  }
}
