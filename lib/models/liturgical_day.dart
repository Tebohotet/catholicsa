/// Shared, global daily readings — one document per date, used by every
/// church in the country. Not duplicated per-church since the lectionary
/// is the same nationally regardless of which church you attend.
class LiturgicalDay {
  final String date; // "2026-08-02"
  final String liturgicalTitle; // "17th Sunday in Ordinary Time"
  final String? sundayCycle; // "A" | "B" | "C" - only meaningful on a Sunday
  final String? weekdayCycle; // "I" | "II" - only meaningful on a weekday
  final Map<String, ReadingSet> readingsByLanguage; // key: "en", "af", ...

  LiturgicalDay({
    required this.date,
    required this.liturgicalTitle,
    this.sundayCycle,
    this.weekdayCycle,
    required this.readingsByLanguage,
  });

  factory LiturgicalDay.fromFirestore(String date, Map<String, dynamic> data) {
    final rawReadings = Map<String, dynamic>.from(data['readings'] ?? {});
    // vigilReadings is a top-level sibling field on the document (same
    // for every language, since it's citations, not translated text),
    // not nested inside readings.en - it has to be merged in here
    // explicitly, or ReadingSet.fromMap never sees it at all, which was
    // the actual, confirmed bug: the save always wrote it correctly,
    // but nothing ever read it back from where it was written.
    final vigilReadingsRaw = data['vigilReadings'] as List<dynamic>? ?? [];
    return LiturgicalDay(
      date: date,
      liturgicalTitle: data['liturgicalTitle'] as String? ?? '',
      sundayCycle: data['sundayCycle'] as String?,
      weekdayCycle: data['weekdayCycle'] as String?,
      readingsByLanguage: rawReadings.map(
        (lang, value) => MapEntry(
          lang,
          ReadingSet.fromMap({
            ...Map<String, dynamic>.from(value),
            'vigilReadings': vigilReadingsRaw,
          }),
        ),
      ),
    );
  }
}

/// One reading+psalm pair for a day that has more than the standard
/// structure - the Easter Vigil is the clear example, traditionally up
/// to 7 Old Testament readings, each followed by its own responsorial
/// psalm, before the Epistle and Gospel. order controls display
/// sequence explicitly rather than relying on list position surviving
/// a round-trip through Firestore's map storage.
class VigilReadingItem {
  final int order;
  final String reading;
  final String? psalm;
  final String? psalmResponse;
  const VigilReadingItem({required this.order, required this.reading, this.psalm, this.psalmResponse});

  Map<String, dynamic> toMap() => {
        'order': order,
        'reading': reading,
        'psalm': psalm,
        'psalmResponse': psalmResponse,
      };

  factory VigilReadingItem.fromMap(Map<String, dynamic> data) => VigilReadingItem(
        order: (data['order'] as num?)?.toInt() ?? 0,
        reading: data['reading'] as String? ?? '',
        psalm: data['psalm'] as String?,
        psalmResponse: data['psalmResponse'] as String?,
      );
}

class ReadingSet {
  final String firstReading;
  final String? psalm;
  final String? psalmResponse; // the repeated "R." line, separate from the verses themselves
  final String? secondReading;
  final String? gospelAcclamation;
  final String gospel;
  final String? entranceAntiphon;
  final String? communionAntiphon;
  final String? reflectionTitle;
  final String? reflectionBody;
  // A second, differently-themed reflection box (matching the missal's
  // "Lord of All Generations"-style callout) - genuinely optional,
  // separate from the main Reflection above it.
  final String? themedBoxTitle;
  final String? themedBoxBody;
  final String? prayersIntro;
  final String? prayersResponse; // e.g. "Lord, hear our prayer"
  final List<String> petitions;
  final String? prayersClosing;
  final String? verseForTheDay;
  final String? verseForTheDayCitation;
  final String source; // "USCCB API" | "manual"
  // Field keys currently hidden from regular users by an editor (e.g.
  // ['entranceAntiphon']) - the underlying text is kept, not deleted, so
  // un-hiding restores it instantly rather than needing re-entry.
  final List<String> hiddenFields;
  // Empty on every ordinary day - only populated for a liturgy that
  // genuinely needs more readings than firstReading/secondReading
  // cover, sorted by their own order field before display.
  final List<VigilReadingItem> vigilReadings;

  ReadingSet({
    required this.firstReading,
    this.psalm,
    this.psalmResponse,
    this.secondReading,
    this.gospelAcclamation,
    required this.gospel,
    this.entranceAntiphon,
    this.communionAntiphon,
    this.reflectionTitle,
    this.reflectionBody,
    this.themedBoxTitle,
    this.themedBoxBody,
    this.prayersIntro,
    this.prayersResponse,
    this.petitions = const [],
    this.prayersClosing,
    this.verseForTheDay,
    this.verseForTheDayCitation,
    this.source = 'manual',
    this.hiddenFields = const [],
    this.vigilReadings = const [],
  });

  factory ReadingSet.fromMap(Map<String, dynamic> data) => ReadingSet(
        firstReading: data['firstReading'] as String? ?? '',
        psalm: data['psalm'] as String?,
        psalmResponse: data['psalmResponse'] as String?,
        secondReading: data['secondReading'] as String?,
        gospelAcclamation: data['gospelAcclamation'] as String?,
        gospel: data['gospel'] as String? ?? '',
        entranceAntiphon: data['entranceAntiphon'] as String?,
        communionAntiphon: data['communionAntiphon'] as String?,
        reflectionTitle: data['reflectionTitle'] as String?,
        reflectionBody: data['reflectionBody'] as String?,
        themedBoxTitle: data['themedBoxTitle'] as String?,
        themedBoxBody: data['themedBoxBody'] as String?,
        prayersIntro: data['prayersIntro'] as String?,
        prayersResponse: data['prayersResponse'] as String?,
        petitions: List<String>.from(data['petitions'] ?? []),
        prayersClosing: data['prayersClosing'] as String?,
        verseForTheDay: data['verseForTheDay'] as String?,
        verseForTheDayCitation: data['verseForTheDayCitation'] as String?,
        source: data['source'] as String? ?? 'manual',
        hiddenFields: List<String>.from(data['hiddenFields'] ?? []),
        vigilReadings: (data['vigilReadings'] as List<dynamic>? ?? [])
            .map((v) => VigilReadingItem.fromMap(Map<String, dynamic>.from(v)))
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order)),
      );
}