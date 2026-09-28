import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:partner_app/services/location_service.dart';

/// Haversine fake so distance math is exercised without platform channels.
class FakeGeolocatorPlatform extends GeolocatorPlatform {
  @override
  double distanceBetween(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = (endLatitude - startLatitude) * math.pi / 180;
    final dLng = (endLongitude - startLongitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(startLatitude * math.pi / 180) *
            math.cos(endLatitude * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthRadiusMeters * math.asin(math.sqrt(a));
  }
}

void main() {
  setUpAll(() {
    GeolocatorPlatform.instance = FakeGeolocatorPlatform();
  });

  group('formatDistance', () {
    test('formats sub-kilometer values in meters', () {
      expect(LocationService.formatDistance(0), '0 m away');
      expect(LocationService.formatDistance(450.4), '450 m away');
      expect(LocationService.formatDistance(999.4), '999 m away');
    });

    test('formats kilometer values with one decimal', () {
      expect(LocationService.formatDistance(1000), '1.0 km away');
      expect(LocationService.formatDistance(2800), '2.8 km away');
      expect(LocationService.formatDistance(12400), '12.4 km away');
    });
  });

  group('parseCoordinate', () {
    test('accepts num and numeric strings', () {
      expect(LocationService.parseCoordinate(12.5), 12.5);
      expect(LocationService.parseCoordinate(12), 12.0);
      expect(LocationService.parseCoordinate('12.5'), 12.5);
    });

    test('rejects null and non-numeric input', () {
      expect(LocationService.parseCoordinate(null), isNull);
      expect(LocationService.parseCoordinate('abc'), isNull);
      expect(LocationService.parseCoordinate(''), isNull);
    });
  });

  group('distanceLabel', () {
    test('returns null when user fix is missing', () {
      expect(
        LocationService.distanceLabel(
          user: null,
          venueLat: 23.03,
          venueLng: 72.58,
        ),
        isNull,
      );
    });

    test('returns null when venue coordinates are missing', () {
      const user = UserCoordinates(23.03, 72.58);
      expect(
        LocationService.distanceLabel(
          user: user,
          venueLat: null,
          venueLng: 72.58,
        ),
        isNull,
      );
      expect(
        LocationService.distanceLabel(
          user: user,
          venueLat: 23.03,
          venueLng: null,
        ),
        isNull,
      );
    });

    test('returns formatted distance for valid coordinates', () {
      const user = UserCoordinates(23.03, 72.58);
      expect(
        LocationService.distanceLabel(
          user: user,
          venueLat: 23.03,
          venueLng: 72.58,
        ),
        '0 m away',
      );
      // ~1.1 km east at the equator.
      expect(
        LocationService.distanceLabel(
          user: const UserCoordinates(0, 0),
          venueLat: 0,
          venueLng: 0.01,
        ),
        '1.1 km away',
      );
    });
  });

  group('sortNearestFirst', () {
    test('sorts ascending with coordinate-less venues last', () {
      const user = UserCoordinates(0, 0);
      final venues = [
        {'name': 'far', 'latitude': 0.1, 'longitude': 0.0},
        {'name': 'no-coords'},
        {'name': 'near', 'latitude': 0.001, 'longitude': 0.0},
      ];

      final sorted = LocationService.sortNearestFirst(venues, user);

      expect(
        sorted.map((v) => (v as Map)['name']).toList(),
        ['near', 'far', 'no-coords'],
      );
      // Input list must not be mutated.
      expect((venues.first as Map)['name'], 'far');
    });
  });
}
