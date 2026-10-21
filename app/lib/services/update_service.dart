import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models.dart';
import '../data/repository.dart';

String? get currentPlatformName => Platform.isAndroid ? 'android' : (Platform.isWindows ? 'windows' : null);

/// Returns the newer published build for this platform, or null when the
/// installed build is current.
Future<AppVersion?> findAvailableUpdate(FinanceRepository repo) async {
  final platform = currentPlatformName;
  if (platform == null) return null;
  final latest = await repo.fetchLatestVersion(platform);
  if (latest == null) return null;
  final info = await PackageInfo.fromPlatform();
  final installed = int.tryParse(info.buildNumber) ?? 0;
  return latest.buildNumber > installed ? latest : null;
}

Future<void> showUpdateDialog(BuildContext context, AppVersion update) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Symbols.system_update_rounded),
      title: Text('Update available: ${update.version}'),
      content: SingleChildScrollView(
        child: Text(
          update.releaseNotes?.trim().isNotEmpty == true
              ? update.releaseNotes!
              : 'A new version of FinTrack is ready to download.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
          onPressed: () {
            Navigator.pop(context);
            launchUrl(Uri.parse(update.downloadUrl), mode: LaunchMode.externalApplication);
          },
          child: const Text('Download'),
        ),
      ],
    ),
  );
}
