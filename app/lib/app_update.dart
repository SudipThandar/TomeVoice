import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'speech_service.dart';

/// A release newer than the one installed.
class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.url,
    required this.title,
    this.apk64,
    this.apk32,
    this.bytes64 = 0,
    this.bytes32 = 0,
  });

  /// "0.6.0".
  final String version;

  /// The release page, where the APK is.
  final String url;
  final String title;

  /// The APKs attached to the release, for 64- and 32-bit phones, if any.
  final String? apk64;
  final String? apk32;
  final int bytes64;
  final int bytes32;

  /// The download's size in MB, rounded up, or null if unknown.
  int? sizeMb({required bool is64}) {
    final b = is64 ? bytes64 : bytes32;
    return b <= 0 ? null : (b / (1024 * 1024)).ceil();
  }
}

/// Whether there is a newer TomeVoice on GitHub.
///
/// The test build ships from the fork's `m11-test-apk` release, so that is the
/// one release it asks about. Every few hours it makes one request, with no
/// account and nothing sent but the request itself. It can be turned off.
class AppUpdates {
  AppUpdates._();

  static const releasesApi = 'https://api.github.com/repos/SudipThandar/TomeVoice/releases/tags/m11-test-apk';
  static const releasePage = 'https://github.com/SudipThandar/TomeVoice/releases/tag/m11-test-apk';
  static const universalApk = 'TomeVoice-test.apk';
  static const downloadRoot = 'https://github.com/SudipThandar/TomeVoice/releases/download/m11-test-apk/';
  static const _every = Duration(hours: 6);

  /// How long Later keeps a release from being offered again.
  static const snooze = Duration(days: 3);

  /// The newer release, once one has been seen.
  static final available = ValueNotifier<AppUpdate?>(null);

  static File _file(Directory root) => File('${root.path}/app_update.json');

  static Future<Map<String, Object?>> _read(Directory root) async {
    try {
      final f = _file(root);
      if (await f.exists()) return Map<String, Object?>.from(jsonDecode(await f.readAsString()) as Map);
    } on Object {
      // Start again.
    }
    return {};
  }

  static Future<void> _write(Directory root, Map<String, Object?> state) async {
    try {
      await _file(root).writeAsString(jsonEncode(state));
    } on Object {
      // Next check tries again.
    }
  }

  static Future<bool> enabled(Directory root) async => (await _read(root))['enabled'] != false;

  static Future<void> setEnabled(Directory root, bool on) async =>
      _write(root, {...await _read(root), 'enabled': on});

  /// Ask GitHub, at most every six hours unless [force]. Returns the newer release,
  /// or null when this is the latest (or the check could not run and [force]
  /// is false).
  static Future<AppUpdate?> check(Directory root, {bool force = false}) async {
    final state = await _read(root);
    if (!force && state['enabled'] == false) return null;
    var last = DateTime.tryParse(state['checked'] as String? ?? '');
    // A date in the future would keep the stored answer for ever.
    if (last != null && last.isAfter(DateTime.now())) last = null;
    final installed = await const SpeechService().appVersion();
    Map<String, Object?>? latest;
    if (!force && last != null && DateTime.now().difference(last) < _every) {
      latest = (state['latest'] as Map?)?.cast<String, Object?>();
    } else {
      latest = await _fetch();
      if (latest == null && force) throw const SocketException('Could not reach GitHub');
      if (latest != null) {
        await _write(root, {...state, 'checked': DateTime.now().toIso8601String(), 'latest': latest});
      }
    }
    final update = latest == null ? null : _newer(latest, installed);
    available.value = update;
    return update;
  }

  /// Whether to offer [update] on its own: not when the reader skipped that
  /// version, nor within [snooze] of putting it off. A newer release than
  /// the one put off is offered at once.
  static Future<bool> shouldOffer(Directory root, AppUpdate update, {DateTime? now}) async {
    final state = await _read(root);
    if (state['skipped'] == update.version) return false;
    final later = (state['later'] as Map?)?.cast<String, Object?>();
    if (later == null || later['version'] != update.version) return true;
    final until = DateTime.tryParse(later['until'] as String? ?? '');
    final at = now ?? DateTime.now();
    // Nor for ever, if the clock was wound back.
    return until == null || !at.isBefore(until) || until.difference(at) > snooze;
  }

  /// Later: offer [update] again in [snooze].
  static Future<void> putOff(Directory root, AppUpdate update, {DateTime? now}) async => _write(root, {
        ...await _read(root),
        'later': {'version': update.version, 'until': (now ?? DateTime.now()).add(snooze).toIso8601String()},
      });

  /// Skip this version: never offer [update] on its own again.
  static Future<void> skip(Directory root, AppUpdate update) async =>
      _write(root, {...await _read(root), 'skipped': update.version});

  static Future<Map<String, Object?>?> _fetch() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.parse(releasesApi));
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'TomeVoice')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final body = Map<String, Object?>.from(jsonDecode(await res.transform(utf8.decoder).join()) as Map);
      // The fork's test release carries one universal APK for both ABIs.
      final apk = forkApk(body['assets'] as List? ?? const []);
      if (apk == null) return null;
      return {
        'tag': releaseVersion(body),
        'url': releasePage,
        'title': body['name'],
        'apk64': apk['url'],
        'apk32': apk['url'],
        'bytes64': apk['bytes'],
        'bytes32': apk['bytes'],
      };
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// The release-to-offer decision, exposed for the fork-update tests.
  @visibleForTesting
  static AppUpdate? updateFromRelease(Map<String, Object?> latest, String? installed) => _newer(latest, installed);

  static AppUpdate? _newer(Map<String, Object?> latest, String? installed) {
    final tag = (latest['tag'] as String? ?? '').replaceFirst(RegExp('^v'), '');
    if (tag.isEmpty || installed == null) return null;
    if (compareVersions(tag, installed) <= 0) return null;
    return AppUpdate(
      version: tag,
      url: latest['url'] as String? ?? releasePage,
      title: latest['title'] as String? ?? 'TomeVoice $tag',
      apk64: _ours(latest['apk64']),
      apk32: _ours(latest['apk32']),
      bytes64: (latest['bytes64'] as num?)?.toInt() ?? 0,
      bytes32: (latest['bytes32'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The release's version. Its tag is a name (`m11-test-apk`), so the number
/// lives in the title the release page shows. Older releases may still put it
/// in the tag, and the notes are a last resort.
@visibleForTesting
String? releaseVersion(Map<String, Object?> release) {
  for (final key in ['tag_name', 'name', 'body']) {
    final text = release[key];
    if (text is! String) continue;
    final match = RegExp(r'(?:^|[^0-9])(\d+\.\d+(?:\.\d+)?)').firstMatch(text);
    if (match != null) return match.group(1);
  }
  return null;
}

/// The universal APK attached to the fork's test release, if any. Nothing else
/// is ever offered for install.
@visibleForTesting
Map<String, Object?>? forkApk(List<Object?> assets) {
  for (final a in assets) {
    if (a is! Map || '${a['name']}' != AppUpdates.universalApk) continue;
    final url = _ours(a['browser_download_url']);
    if (url == null) continue;
    return {'url': url, 'bytes': (a['size'] as num?)?.toInt() ?? 0};
  }
  return null;
}

/// [url] if it is the APK on the fork's own release; null otherwise.
String? _ours(Object? url) =>
    url is String &&
            url.startsWith(AppUpdates.downloadRoot) &&
            url.endsWith(AppUpdates.universalApk) &&
            // No ".." or escapes: it must stay inside that release.
            !url.contains('..') &&
            !url.contains('%')
        ? url
        : null;

/// Compare "0.10.1" with "0.9" as versions: negative, zero or positive.
/// Anything after a "+" or "-" (build numbers, "-beta") is ignored.
@visibleForTesting
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      [for (final p in v.split(RegExp(r'[+-]')).first.split('.')) int.tryParse(p.trim()) ?? 0];
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < (x.length > y.length ? x.length : y.length); i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}
