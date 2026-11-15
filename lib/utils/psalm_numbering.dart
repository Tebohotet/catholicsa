/// Converts a lectionary psalm reference (modern Hebrew/NABRE numbering,
/// which is what the cpbjr citation sync stores - e.g. Holy Thursday's
/// "Psalm 116:12-13, 15-16bc, 17-18") into the chapter:verse key the
/// app's synced Douay-Rheims text (Project Gutenberg #8300) actually
/// stores that same text under.
///
/// Verified verse-by-verse against the real Gutenberg text, not assumed:
///
/// * For almost every psalm, only the CHAPTER differs (Vulgate numbering
///   runs one behind Hebrew for 11-146). Verse numbers already line up,
///   because NABRE and the Douay-Rheims both count a psalm's
///   superscription as verse 1 (e.g. "Have mercy on me, O God" is
///   NABRE 51:3 and Douay-Rheims 50:3). So the flagged "superscription
///   shifts every verse by one" concern does NOT apply in general.
/// * The real verse-level shifts are confined to the psalms the two
///   traditions split or merge differently:
///   - Hebrew 9 + 10 are one Vulgate psalm 9; Hebrew 10:1 is 9:22.
///   - Hebrew 114 + 115 are one Vulgate psalm 113; Hebrew 115:1
///     ("Not to us, O Lord") is 113:9.
///   - Hebrew 116 is split into Vulgate 114 (verses 1-9) and 115.
///   - Hebrew 147 is split into Vulgate 146 (verses 1-11) and 147.
///   For the second half of 116 and 147, this particular Gutenberg
///   edition keeps the Hebrew verse numbers (it prints 115:10-19 and
///   147:12-20, not 115:1-10 and 147:1-9), so those verses map with no
///   verse offset - only the chapter changes.
class PsalmNumbering {
  PsalmNumbering._();

  /// Maps one Hebrew/NABRE psalm [chapter]:[verse] to where the
  /// Douay-Rheims data stores it. Out-of-range input (chapter < 1 or
  /// > 150) is returned unchanged rather than guessed at.
  static ({int chapter, int verse}) hebrewToDouayRheims(int chapter, int verse) {
    if (chapter < 1 || chapter > 150) return (chapter: chapter, verse: verse);
    if (chapter <= 9) return (chapter: chapter, verse: verse);
    if (chapter == 10) return (chapter: 9, verse: verse + 21);
    if (chapter <= 113) return (chapter: chapter - 1, verse: verse);
    if (chapter == 114) return (chapter: 113, verse: verse);
    if (chapter == 115) return (chapter: 113, verse: verse + 8);
    if (chapter == 116) return (chapter: verse <= 9 ? 114 : 115, verse: verse);
    if (chapter <= 146) return (chapter: chapter - 1, verse: verse);
    if (chapter == 147) return (chapter: verse <= 11 ? 146 : 147, verse: verse);
    return (chapter: chapter, verse: verse); // 148-150 re-converge
  }

  /// Chapter-only mapping, for when no specific verses are known (a
  /// whole-chapter reference). For the psalms Hebrew splits across two
  /// Vulgate chapters (116, 147) this returns the chapter holding the
  /// psalm's beginning.
  static int hebrewToDouayRheimsChapter(int chapter) =>
      hebrewToDouayRheims(chapter, 1).chapter;
}
