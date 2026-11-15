import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/utils/psalm_numbering.dart';

// Expected values below were checked against the real Project Gutenberg
// #8300 Douay-Rheims text (as stored by syncFullBible), using verses with
// unmistakable wording on both sides.
void main() {
  ({int chapter, int verse}) map(int c, int v) => PsalmNumbering.hebrewToDouayRheims(c, v);

  group('PsalmNumbering.hebrewToDouayRheims', () {
    test('Psalms 1-9 and 148-150 are unchanged', () {
      expect(map(1, 1), (chapter: 1, verse: 1));
      expect(map(8, 2), (chapter: 8, verse: 2));
      expect(map(9, 2), (chapter: 9, verse: 2));
      expect(map(148, 1), (chapter: 148, verse: 1));
      expect(map(150, 6), (chapter: 150, verse: 6));
    });

    test('ordinary psalms shift the chapter only - superscriptions already align', () {
      // "Have mercy on me, O God" - NABRE 51:3, Douay-Rheims 50:3.
      expect(map(51, 3), (chapter: 50, verse: 3));
      // "The Lord is my shepherd" / "The Lord ruleth me".
      expect(map(23, 1), (chapter: 22, verse: 1));
      // "The stone which the builders rejected".
      expect(map(118, 22), (chapter: 117, verse: 22));
      expect(map(146, 7), (chapter: 145, verse: 7));
    });

    test('Hebrew 10 continues Vulgate 9 at verse 22', () {
      // "Why, O Lord, hast thou retired afar off?"
      expect(map(10, 1), (chapter: 9, verse: 22));
      expect(map(10, 18), (chapter: 9, verse: 39));
    });

    test('Hebrew 114 and 115 are both Vulgate 113', () {
      expect(map(114, 1), (chapter: 113, verse: 1));
      // "Not to us, O Lord, not to us".
      expect(map(115, 1), (chapter: 113, verse: 9));
      expect(map(115, 18), (chapter: 113, verse: 26));
    });

    test('Hebrew 116 splits into Vulgate 114 and 115, keeping verse numbers', () {
      // "The sorrows of death have compassed me".
      expect(map(116, 3), (chapter: 114, verse: 3));
      expect(map(116, 9), (chapter: 114, verse: 9));
      // "I have believed, therefore have I spoken" - this edition prints 115:10.
      expect(map(116, 10), (chapter: 115, verse: 10));
      // Holy Thursday: "What shall I render to the Lord".
      expect(map(116, 12), (chapter: 115, verse: 12));
    });

    test('Hebrew 147 splits into Vulgate 146 and 147, keeping verse numbers', () {
      expect(map(147, 11), (chapter: 146, verse: 11));
      // "Praise the Lord, O Jerusalem" - this edition prints 147:12.
      expect(map(147, 12), (chapter: 147, verse: 12));
    });

    test('out-of-range chapters pass through untouched', () {
      expect(map(0, 1), (chapter: 0, verse: 1));
      expect(map(151, 1), (chapter: 151, verse: 1));
    });
  });

  group('PsalmNumbering.hebrewToDouayRheimsChapter', () {
    test('whole-chapter references go to where the psalm begins', () {
      expect(PsalmNumbering.hebrewToDouayRheimsChapter(10), 9);
      expect(PsalmNumbering.hebrewToDouayRheimsChapter(51), 50);
      expect(PsalmNumbering.hebrewToDouayRheimsChapter(115), 113);
      expect(PsalmNumbering.hebrewToDouayRheimsChapter(116), 114);
      expect(PsalmNumbering.hebrewToDouayRheimsChapter(147), 146);
    });
  });
}
