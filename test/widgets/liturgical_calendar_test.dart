import 'package:flutter_test/flutter_test.dart';
import 'package:catholicsa/utils/liturgical_calendar.dart';

void main() {
  group('LiturgicalCalendar.easterSunday', () {
    final knownEaster = {
      2024: DateTime(2024, 3, 31),
      2025: DateTime(2025, 4, 20),
      2026: DateTime(2026, 4, 5),
      2027: DateTime(2027, 3, 28),
      2028: DateTime(2028, 4, 16),
    };

    knownEaster.forEach((year, expected) {
      test('Easter $year is $expected', () {
        expect(LiturgicalCalendar.easterSunday(year), expected);
      });
    });
  });

  group('LiturgicalCalendar.adventSunday', () {
    final knownAdvent = {
      2024: DateTime(2024, 12, 1),
      2025: DateTime(2025, 11, 30),
      2026: DateTime(2026, 11, 29),
      2027: DateTime(2027, 11, 28),
    };

    knownAdvent.forEach((year, expected) {
      test('Advent Sunday $year is $expected', () {
        expect(LiturgicalCalendar.adventSunday(year), expected);
      });
    });
  });

  group('LiturgicalCalendar.infoFor - season boundaries', () {
    test('Christmas Day 2026 is Christmas, not Advent', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 12, 25));
      expect(info.season, 'Christmas');
      expect(info.namedDay, 'Christmas Day');
    });

    test('Ash Wednesday 2026 starts Lent', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 2, 18));
      expect(info.season, 'Lent');
      expect(info.namedDay, 'Ash Wednesday');
    });

    test('Easter Sunday 2026 starts the Easter season', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 4, 5));
      expect(info.season, 'Easter');
      expect(info.namedDay, 'Easter Sunday');
    });

    test('First Sunday of Advent 2026 starts Advent', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 11, 29));
      expect(info.season, 'Advent');
      expect(info.namedDay, 'First Sunday of Advent');
    });

    test('A random midwinter Ordinary Time date classifies correctly', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 7, 29));
      expect(info.season, 'Ordinary Time');
    });

    test('Every day of 2026 gets exactly one season with no gaps', () {
      final validSeasons = {'Advent', 'Christmas', 'Lent', 'Triduum', 'Easter', 'Ordinary Time'};
      var date = DateTime(2026, 1, 1);
      final end = DateTime(2026, 12, 31);
      while (!date.isAfter(end)) {
        final info = LiturgicalCalendar.infoFor(date);
        expect(validSeasons.contains(info.season), true, reason: 'Unrecognised season "${info.season}" on $date');
        date = date.add(const Duration(days: 1));
      }
    });
  });

  group('LiturgicalCalendar.infoFor - Sunday Cycle A/B/C', () {
    test('Liturgical year starting Advent 2025 is Cycle A', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 7, 29));
      expect(info.sundayCycle, 'A');
    });

    test('Liturgical year starting Advent 2026 is Cycle B', () {
      final info = LiturgicalCalendar.infoFor(DateTime(2026, 12, 25));
      expect(info.sundayCycle, 'B');
    });
  });

  group('LiturgicalCalendar.infoFor - Weekday Cycle I/II', () {
    test('2025 (odd) is Weekday Cycle I', () {
      expect(LiturgicalCalendar.infoFor(DateTime(2025, 6, 1)).weekdayCycle, 'I');
    });

    test('2026 (even) is Weekday Cycle II', () {
      expect(LiturgicalCalendar.infoFor(DateTime(2026, 6, 1)).weekdayCycle, 'II');
    });
  });
}
