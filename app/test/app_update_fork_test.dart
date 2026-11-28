// The test build finds its own update on the fork, never on the upstream
// project's latest release. Its one universal APK works on 32- and 64-bit
// phones, so both paths in the install flow receive the same file.

import 'package:flutter_test/flutter_test.dart';
import 'package:tomevoice_spike/app_update.dart';

void main() {
  const good = '${AppUpdates.downloadRoot}${AppUpdates.universalApk}';

  test('the check targets the fork test release and its download prefix', () {
    expect(AppUpdates.releasesApi,
        'https://api.github.com/repos/SudipThandar/TomeVoice/releases/tags/m11-test-apk');
    expect(AppUpdates.releasePage,
        'https://github.com/SudipThandar/TomeVoice/releases/tag/m11-test-apk');
    expect(good,
        'https://github.com/SudipThandar/TomeVoice/releases/download/m11-test-apk/TomeVoice-test.apk');
  });

  test('a named tag still yields a comparable version from the release title', () {
    expect(
      releaseVersion({
        'tag_name': 'm11-test-apk',
        'name': 'TomeVoice 2.6.7 - Gothic Obsidian',
        'body': 'SHA-256: abcdef',
      }),
      '2.6.7',
    );
    expect(releaseVersion({'tag_name': 'v2.6.6', 'name': 'TomeVoice'}), '2.6.6');
    expect(releaseVersion({'tag_name': 'm11-test-apk', 'name': 'TomeVoice Test'}), isNull);
  });

  test('only the fork universal APK is picked', () {
    final picked = forkApk([
      {
        'name': 'TomeVoice-2.6.7.apk',
        'browser_download_url': '${AppUpdates.downloadRoot}TomeVoice-2.6.7.apk',
        'size': 1,
      },
      {'name': AppUpdates.universalApk, 'browser_download_url': good, 'size': 57228918},
    ]);
    expect(picked?['url'], good);
    expect(picked?['bytes'], 57228918);

    // An upstream URL, an escaped filename and a path walk are all refused.
    expect(
      forkApk([
        {
          'name': AppUpdates.universalApk,
          'browser_download_url':
              'https://github.com/Sayandeep1013/TomeVoice/releases/download/m11-test-apk/TomeVoice-test.apk',
          'size': 1,
        },
        {
          'name': AppUpdates.universalApk,
          'browser_download_url': '${AppUpdates.downloadRoot}TomeVoice-test%2Eapk',
          'size': 1,
        },
        {'name': AppUpdates.universalApk, 'browser_download_url': '$good/../else.apk', 'size': 1},
      ]),
      isNull,
    );
  });

  test('an upstream APK download is never offered, even inside a fork release', () {
    final release = {
      'tag': '2.6.7',
      'url': AppUpdates.releasePage,
      'title': 'TomeVoice 2.6.7',
      'apk64': 'https://github.com/Sayandeep1013/TomeVoice/releases/download/v2.6.6/TomeVoice-2.6.6.apk',
      'apk32': good,
      'bytes64': 1,
      'bytes32': 57228918,
    };
    final update = AppUpdates.updateFromRelease(release, '2.6.6');
    expect(update, isNotNull);
    expect(update!.apk64, isNull, reason: 'the upstream asset is not ours');
    expect(update.apk32, good);
  });

  test('the universal APK is offered to both ABIs at the installed-version boundary', () {
    final release = {
      'tag': '2.6.7',
      'url': AppUpdates.releasePage,
      'title': 'TomeVoice 2.6.7',
      'apk64': good,
      'apk32': good,
      'bytes64': 57228918,
      'bytes32': 57228918,
    };
    expect(AppUpdates.updateFromRelease(release, '2.6.6')?.version, '2.6.7');
    expect(AppUpdates.updateFromRelease(release, '2.6.7'), isNull);
  });
}
