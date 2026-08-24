/// Parses a reading citation like "Genesis 1:1-5" or "1 Corinthians 9:16-19,
/// 22-23" into a book code, chapter, and verse range. Book/chapter
/// navigation is reliable; for a multi-range citation (the second
/// example), only the first range is used as the highlighted anchor -
/// an honest simplification, not a full range-set parser, since the
/// actual reading screen shows the citation text itself regardless.
class ParsedCitation {
  final String bookCode;
  final String bookName;
  final int chapter;
  final int? startVerse;
  final int? endVerse;
  const ParsedCitation({required this.bookCode, required this.bookName, required this.chapter, this.startVerse, this.endVerse});
}

class BibleCitationParser {
  /// Loaded once from the manifest and reused - matching by name is
  /// cheap, but no need to redo it per citation.
  static List<Map<String, dynamic>>? _books;

  static bool get booksLoaded => _books != null;

  static void loadBooks(List<Map<String, dynamic>> books) {
    _books = books;
  }

  /// Alternate spellings a citation might actually use instead of the
  /// manifest's plain English names - confirmed real from an actual
  /// reading in this app ("Lucam 24:1-12", the Latin accusative form of
  /// Luke). Covers the other Gospels and a few other commonly-seen
  /// alternate forms for the same reason; genuinely new names for a
  /// book already in the manifest, not new books.
  static const Map<String, String> _nameAliases = {
    'lucam': 'luke',
    'lucas': 'luke',
    'marcum': 'mark',
    'marcus': 'mark',
    'matthaeum': 'matthew',
    'matthaeus': 'matthew',
    'ioannem': 'john',
    'joannem': 'john',
    'ioannes': 'john',
    'joannes': 'john',
    'psalmo': 'psalms',
    'psalmus': 'psalms',
    'psalmi': 'psalms',
  };

  static ParsedCitation? parse(String rawCitation) {
    final books = _books;
    if (books == null) return null;

    // A citation field can genuinely hold more than one alternate
    // reading joined with "|" (confirmed from real data - the Easter
    // Vigil allows an optional alternate psalm, and both ended up
    // stored together in the same field). Only the first is used as
    // the anchor for inline scripture and navigation - showing all of
    // them would need the vigilReadings structure, not a single
    // citation string.
    final citation = rawCitation.split('|').first.trim();

    // "Genesis 1:1-5" -> book name group, chapter:verse group
    final match = RegExp(r'^(.+?)\s+(\d+):(\d+)').firstMatch(citation);
    if (match == null) return null;

    var rawName = match.group(1)!.trim().toLowerCase();
    rawName = _nameAliases[rawName] ?? rawName;
    final chapter = int.tryParse(match.group(2)!);
    final startVerse = int.tryParse(match.group(3)!);
    if (chapter == null) return null;

    // Optional end verse from the first range only, e.g. "16-19" in
    // "9:16-19, 22-23" - deliberately not parsing the comma-separated
    // second range.
    int? endVerse;
    final rangeMatch = RegExp(r'^\d+:(\d+)-(\d+)').firstMatch(citation.substring(match.group(1)!.length).trim());
    if (rangeMatch != null) endVerse = int.tryParse(rangeMatch.group(2)!);

    Map<String, dynamic>? book;
    for (final b in books) {
      final name = (b['name'] as String).toLowerCase();
      if (name == rawName || rawName.startsWith(name) || name.startsWith(rawName)) {
        book = b;
        break;
      }
    }
    if (book == null) return null;

    return ParsedCitation(
      bookCode: book['code'] as String,
      bookName: book['name'] as String,
      chapter: chapter,
      startVerse: startVerse,
      endVerse: endVerse,
    );
  }
}