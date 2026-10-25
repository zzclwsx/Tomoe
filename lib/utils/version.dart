import 'dart:math';
import 'package:pub_semver/pub_semver.dart';

/// App releases use SemVer; legacy rule versions keep their own comparator.
bool isNewerAppVersion(String localVersion, String remoteVersion) {
  Version parse(String value) {
    final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
    final version = Version.parse(normalized);
    // SemVer build metadata must not affect update precedence.
    return Version.parse(version.toString().split('+').first);
  }

  return parse(remoteVersion) > parse(localVersion);
}

bool needUpdate(String localVersion, String remoteVersion) {
  final localVersionList = localVersion.split('.');
  final remoteVersionList = remoteVersion.split('.');
  final maxLength = max(localVersionList.length, remoteVersionList.length);
  for (var i = 0; i < maxLength; i++) {
    final localSegment = i < localVersionList.length
        ? int.parse(localVersionList[i])
        : 0;
    final remoteSegment = i < remoteVersionList.length
        ? int.parse(remoteVersionList[i])
        : 0;
    if (remoteSegment > localSegment) {
      return true;
    } else if (remoteSegment < localSegment) {
      return false;
    }
  }
  return false;
}
