// The app's interface face belongs to the chosen theme, not to the device.
// Switching theme changes every chrome style built from Skin.ui(); the book's
// own page face is deliberately outside this contract.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomevoice_spike/theme.dart';

void main() {
  late Palette original;

  setUp(() => original = Skin.palette);
  tearDown(() => Skin.palette = original);

  test('the interface face follows the selected theme', () {
    Skin.palette = Palette.obsidianBlack;
    expect(Skin.uiFamilyNow, 'Cinzel');
    expect(Skin.ui().fontFamily, 'Cinzel');

    Skin.palette = Palette.dungeon;
    expect(Skin.uiFamilyNow, Skin.uiFamily);
    expect(Skin.ui().fontFamily, Skin.uiFamily);

    Skin.palette = Palette.ocean;
    expect(Skin.uiFamilyNow, Skin.uiFamily);
    expect(Skin.ui().fontFamily, Skin.uiFamily);
  });

  test('theme data carries the theme face', () {
    final obsidian = Skin.themeFor(Palette.obsidianBlack, Brightness.dark);
    expect(obsidian.textTheme.bodyMedium?.fontFamily, 'Cinzel');
    final plain = Skin.themeFor(Palette.ocean, Brightness.light);
    expect(plain.textTheme.bodyMedium?.fontFamily, Skin.uiFamily);
  });
}
