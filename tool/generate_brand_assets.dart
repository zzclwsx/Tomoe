// Copyright (c) 2026 zzclwsx. SPDX-License-Identifier: MIT
// Run: flutter test tool/generate_brand_assets.dart
// Renders our own SVG master; never reads or transforms upstream artwork.
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> render(String svg, int size) async {
  final picture = await vg.loadPicture(SvgStringLoader(svg), null);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..scale(size / 1024);
  canvas.drawPicture(picture.picture);
  final recording = recorder.endRecording();
  final image = await recording.toImage(size, size);
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  recording.dispose();
  picture.picture.dispose();
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export Tomoe native icons from the independent SVG master', () async {
    final svg = await File('assets/brand/tomoe-mark.svg').readAsString();
    final cache = <int, Uint8List>{};
    Future<Uint8List> png(int size) async =>
        cache[size] ??= await render(svg, size);
    Future<void> write(String path, int size) async {
      await File(path).writeAsBytes(await png(size));
    }

    final opaque = svg.replaceFirst('rx="232"', 'rx="0"');
    for (final name in [
      'logo_rounded.png',
      'logo_linux.png',
      'logo_android.png',
    ]) {
      await write('assets/images/logo/$name', 1024);
    }
    await File(
      'assets/images/logo/logo_ios.png',
    ).writeAsBytes(await render(opaque, 1024));
    final frames = <img.Image>[];
    for (final size in [16, 24, 32, 48, 64, 128, 256]) {
      frames.add(img.decodePng(await png(size))!);
    }
    final ico = img.IcoEncoder().encodeImages(frames);
    for (final path in [
      'assets/images/logo/logo_windows.ico',
      'assets/images/logo/logo_lanczos.ico',
      'windows/runner/resources/app_icon.ico',
    ]) {
      await File(path).writeAsBytes(ico);
    }
    const iosIcons = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final iosManifest =
        jsonDecode(await File('$iosIcons/Contents.json').readAsString()) as Map;
    for (final entry in iosManifest['images'] as List) {
      if (entry['filename'] == null) continue;
      final size =
          (double.parse((entry['size'] as String).split('x').first) *
                  double.parse((entry['scale'] as String).replaceAll('x', '')))
              .round();
      await File(
        '$iosIcons/${entry['filename']}',
      ).writeAsBytes(await render(opaque, size));
    }
    for (final file in Directory(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
      final size = int.parse(
        RegExp(r'app_icon_(\d+)').firstMatch(file.path)!.group(1)!,
      );
      await file.writeAsBytes(await png(size));
    }
    for (final density in {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    }.entries) {
      await write(
        'android/app/src/main/res/mipmap-${density.key}/ic_launcher.png',
        density.value,
      );
      final foreground = File(
        'android/app/src/main/res/drawable-${density.key}/ic_launcher_foreground.png',
      );
      // Adaptive icons have their own safe area and a system-applied mask.
      final foregroundSvg = svg
          .replaceFirst(
            '<rect width="1024" height="1024" rx="232" fill="#e5f0e2"/>',
            '',
          )
          .replaceFirst(
            '<rect x="170"',
            '<g transform="translate(128 128) scale(.75)"><rect x="170"',
          )
          .replaceFirst('</svg>', '</g></svg>');
      await foreground.writeAsBytes(
        await render(foregroundSvg, (density.value * 2.25).round()),
      );
    }
    for (final file in Directory(
      'ios/Runner/Assets.xcassets/LaunchImage.imageset',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.png'))) {
      final scale = file.path.contains('@3x')
          ? 3
          : file.path.contains('@2x')
          ? 2
          : 1;
      await file.writeAsBytes(await png(144 * scale));
    }
    for (final size in [192, 512]) {
      await write('web/icons/Icon-$size.png', size);
      await File(
        'web/icons/Icon-maskable-$size.png',
      ).writeAsBytes(await render(opaque, size));
    }
    await write('web/favicon.png', 32);
  });
}
