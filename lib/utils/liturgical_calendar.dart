/// Computes the Catholic liturgical calendar for any date, entirely offline.
/// No network call, ever - season, Sunday cycle (A/B/C), and weekday cycle
/// (I/II) are all mathematically derived from Easter's date, which is
/// itself computed (not looked up) via the Anonymous Gregorian algorithm.
///
/// Verified before shipping: 5 known Easter dates (2024-2028), 4 known
/// Advent Sunday dates (2024-2027), and a full-year day-by-day sweep of
/// 2026 checking for classification gaps or overlaps at season boundaries
/// (this caught and fixed a real bug where Christmas Day was briefly
/// misclassified as Advent).
///
/// Known limitation: exact Ordinary Time week numbers have documented
/// edge-case irregularities in the official printed tables that a pure
/// formula doesn't fully capture. Season name, Sunday cycle, and weekday
/// cycle are solid; the week number is a reasonable estimate, not
/// guaranteed to match the official Ordo in every year.
class LiturgicalInfo {
  final String season; // Advent, Christmas, Lent, Triduum, Easter, Ordinary Time
  final int? seasonWeek;
  final String sundayCycle; // A, B, C
  final String weekdayCycle; // I, II
  final String? namedDay; // e.g. "Ash Wednesday", "Easter Sunday"

  LiturgicalInfo({
    required this.season,
    this.seasonWeek,
    required this.sundayCycle,
    required this.weekdayCycle,
    this.namedDay,
  });

  String get displayTitle {
    if (namedDay != null) return namedDay!;
    if (seasonWeek != null) return '$season, Week $seasonWeek';
    return season;
  }
}

class LiturgicalCalendar {
  static DateTime easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  static DateTime adventSunday(int year) {
    final christmas = DateTime(year, 12, 25);
    final daysSincePrevSunday = christmas.weekday % 7;
    final sundayOnOrBeforeXmas = christmas.subtract(Duration(days: daysSincePrevSunday));
    return sundayOnOrBeforeXmas.subtract(const Duration(days: 21));
  }

  static DateTime baptismOfLord(int year) {
    final epiphany = DateTime(year, 1, 6);
    final wd = epiphany.weekday % 7;
    final daysToNextSunday = wd == 0 ? 7 : (7 - wd);
    return epiphany.add(Duration(days: daysToNextSunday));
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static LiturgicalInfo infoFor(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final y = d.year;
    final easter = easterSunday(y);
    final ashWednesday = easter.subtract(const Duration(days: 46));
    final palmSunday = easter.subtract(const Duration(days: 7));
    final holyThursday = easter.subtract(const Duration(days: 3));
    final goodFriday = easter.subtract(const Duration(days: 2));
    final pentecost = easter.add(const Duration(days: 49));
    final trinitySunday = pentecost.add(const Duration(days: 7));
    final corpusChristi = pentecost.add(const Duration(days: 11));
    final christmasThis = DateTime(y, 12, 25);
    final epiphany = DateTime(y, 1, 6);
    final adventThis = adventSunday(y);
    final baptismThis = baptismOfLord(y);

    String? named;
    if (_sameDay(d, ashWednesday)) {
      named = 'Ash Wednesday';
    } else if (_sameDay(d, palmSunday)) {
      named = 'Palm Sunday';
    } else if (_sameDay(d, holyThursday)) {
      named = 'Holy Thursday';
    } else if (_sameDay(d, goodFriday)) {
      named = 'Good Friday';
    } else if (_sameDay(d, easter)) {
      named = 'Easter Sunday';
    } else if (_sameDay(d, pentecost)) {
      named = 'Pentecost';
    } else if (_sameDay(d, trinitySunday)) {
      named = 'Trinity Sunday';
    } else if (_sameDay(d, corpusChristi)) {
      named = 'Corpus Christi';
    } else if (_sameDay(d, christmasThis)) {
      named = 'Christmas Day';
    } else if (_sameDay(d, epiphany)) {
      named = 'Epiphany of the Lord';
    } else if (_sameDay(d, baptismThis)) {
      named = 'Baptism of the Lord';
    } else if (_sameDay(d, adventThis)) {
      named = 'First Sunday of Advent';
    }

    String season;
    int? week;
    if (!d.isBefore(adventThis) && d.isBefore(christmasThis)) {
      season = 'Advent';
      week = (d.difference(adventThis).inDays ~/ 7) + 1;
    } else if (!d.isBefore(christmasThis)) {
      season = 'Christmas';
      week = null;
    } else if (d.isBefore(baptismThis) && d.month <= 2) {
      season = 'Christmas';
      week = null;
    } else if (!d.isBefore(ashWednesday) && d.isBefore(holyThursday)) {
      season = 'Lent';
      week = (d.difference(ashWednesday).inDays ~/ 7) + 1;
    } else if (!d.isBefore(holyThursday) && d.isBefore(easter)) {
      season = 'Triduum';
      week = null;
    } else if (!d.isBefore(easter) && !d.isAfter(pentecost)) {
      season = 'Easter';
      week = (d.difference(easter).inDays ~/ 7) + 1;
    } else if (!d.isBefore(baptismThis) && d.isBefore(ashWednesday)) {
      season = 'Ordinary Time';
      week = (d.difference(baptismThis).inDays ~/ 7) + 1;
    } else {
      season = 'Ordinary Time';
      week = (d.difference(pentecost).inDays ~/ 7) + 8; // approximate, see class doc
    }

    final cycleStartYear = !d.isBefore(adventThis) ? y : y - 1;
    final cycleIndex = ((cycleStartYear - 2025) % 3 + 3) % 3;
    final sundayCycle = ['A', 'B', 'C'][cycleIndex];
    final weekdayCycle = y % 2 == 0 ? 'II' : 'I';

    return LiturgicalInfo(
      season: season,
      seasonWeek: week,
      sundayCycle: sundayCycle,
      weekdayCycle: weekdayCycle,
      namedDay: named,
    );
  }
}
