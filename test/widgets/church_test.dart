import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:catholicsa/models/church.dart';

void main() {
  group('Church.fromFirestore', () {
    test('parses a fully-populated document correctly', () {
      final church = Church.fromFirestore('vredenburg', {
        'parishId': 'st-jude-parish',
        'name': 'St Jude Catholic Church',
        'slug': 'vredenburg',
        'address': '39 Voortrekker Street, Vredenburg, 7380',
        'geopoint': const GeoPoint(-32.9077, 17.9932),
        'contactPhone': '022 713 1644',
        'contactEmail': 'stjudecatholicchurch@gmail.com',
        'socialLinks': {'facebook': 'https://facebook.com/example'},
        'supportedLanguages': ['en', 'af'],
        'buildingType': 'Church',
      });

      expect(church.id, 'vredenburg');
      expect(church.name, 'St Jude Catholic Church');
      expect(church.slug, 'vredenburg');
      expect(church.socialLinks['facebook'], 'https://facebook.com/example');
      expect(church.supportedLanguages, ['en', 'af']);
    });

    test('falls back to the document id when slug is genuinely missing - this exact bug crashed the app earlier in this project', () {
      final church = Church.fromFirestore('holy-cross-convent', {
        'parishId': 'st-jude-parish',
        'name': 'Holy Cross Convent',
        // slug intentionally omitted
        'address': 'Louwville, Saldanha Bay',
        'geopoint': const GeoPoint(-32.91, 18.01),
      });

      expect(church.slug, 'holy-cross-convent', reason: 'slug should fall back to the doc id, not throw');
    });

    test('handles a minimal document with only the required fields', () {
      final church = Church.fromFirestore('minimal-church', {
        'parishId': 'some-parish',
        'name': 'Minimal Church',
        'address': 'Somewhere',
        'geopoint': const GeoPoint(0, 0),
      });

      expect(church.contactPhone, '');
      expect(church.contactEmail, '');
      expect(church.socialLinks, isEmpty);
      expect(church.supportedLanguages, ['en']);
      expect(church.buildingType, 'Church');
    });
  });
}
