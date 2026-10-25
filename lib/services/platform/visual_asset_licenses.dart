import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

void registerVisualAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'Noto Sans SC': 'licenses/fonts/OFL-NotoSansSC.txt',
      'Material Icons': 'licenses/material-icons/LICENSE',
      'Tomoe shared-frames artwork': 'licenses/tomoe-art/LICENSE',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
}
