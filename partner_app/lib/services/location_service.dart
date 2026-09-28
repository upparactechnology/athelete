import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Lightweight holder for the partner's current device coordinates.
@immutable
class UserCoordinates {
  final double latitude;
  final double longitude;

  const UserCoordinates(this.latitude, this.longitude);
}

/// Single entry point for everything location-related in the partner app.
///
/// Architecture:
///
/// ```text
/// LocationService (one GPS fix per screen/session, cached + deduplicated)
///       ↓
/// UserCoordinates
///       ↓
/// Venue list (backend latitude/longitude, already on-device)
///       ↓
/// Geolocator.distanceBetween() — local straight-line (geographic) distance
///       ↓
/// formatDistance() — "450 m away" / "1.2 km away"
/// ```
///
/// No routing engine, no map billing, no network calls for distance.
/// Never throws: every failure path returns null and logs a single line.
class LocationService {
  LocationService._();

  /// How long a cached fix is reused before GPS is consulted again.
  static const Duration cacheTtl = Duration(minutes: 5);

  static UserCoordinates? _cached;
  static DateTime? _cachedAt;
  static Future<UserCoordinates?>? _inFlight;

  /// Returns the current device coordinates.
  ///
  /// The fix is cached for [cacheTtl] and concurrent callers share a single
  /// in-flight GPS request, so venue cards never trigger per-card GPS reads.
  /// Returns null when location services are off, permission is denied
  /// (including deniedForever), or the fix times out / fails.
  static Future<UserCoordinates?> getCurrentCoordinates() {
    final cached = _cached;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < cacheTtl) {
      return Future.value(cached);
    }
    _inFlight ??= _fetchCoordinates().then((coords) {
      _inFlight = null;
      if (coords != null) {
        _cached = coords;
        _cachedAt = DateTime.now();
      }
      return coords;
    });
    return _inFlight!;
  }

  /// Drops the cached fix and fetches a fresh one (pull-to-refresh etc.).
  static Future<UserCoordinates?> refreshCoordinates() {
    _cached = null;
    _cachedAt = null;
    return getCurrentCoordinates();
  }

  /// Clears cached state (logout, tests).
  static void clearCache() {
    _cached = null;
    _cachedAt = null;
    _inFlight = null;
  }

  static Future<UserCoordinates?> _fetchCoordinates() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('LocationService: location services disabled.');
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('LocationService: location permission unavailable ($permission).');
        return null;
      }
      // whileInUse / always both reach here and are sufficient.

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return UserCoordinates(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('LocationService: failed to obtain position: $e');
      return null;
    }
  }

  /// Straight-line (geographic) distance in meters between two coordinates.
  /// Pure local math via geolocator — no routing, no network.
  static double distanceMeters(
    double userLat,
    double userLng,
    double venueLat,
    double venueLng,
  ) {
    return Geolocator.distanceBetween(userLat, userLng, venueLat, venueLng);
  }

  /// Formats a meter value for display.
  ///
  /// `< 1000 m` → meters (`450 m away`), otherwise one-decimal kilometers
  /// (`1.2 km away`). Never exposes raw float precision.
  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} m away';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km away';
  }

  /// Returns the display label for a venue, or null when no honest distance
  /// can be produced (missing user fix or missing venue coordinates).
  /// Callers render `Distance unavailable` for null — never invent a value.
  static String? distanceLabel({
    required UserCoordinates? user,
    required double? venueLat,
    required double? venueLng,
  }) {
    if (user == null || venueLat == null || venueLng == null) return null;
    return formatDistance(
      distanceMeters(user.latitude, user.longitude, venueLat, venueLng),
    );
  }

  /// Parses backend coordinate values (num or numeric String) to double.
  /// Returns null for null / non-numeric input.
  static double? parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  /// Returns a copy of [venues] sorted nearest-first by straight-line
  /// distance from [user]. Venues without coordinates sort last.
  /// Does not mutate the input list.
  static List<dynamic> sortNearestFirst(
    List<dynamic> venues,
    UserCoordinates user,
  ) {
    double distanceOf(dynamic venue) {
      final map = venue is Map ? venue : null;
      final lat = parseCoordinate(map?['latitude']);
      final lng = parseCoordinate(map?['longitude']);
      if (lat == null || lng == null) return double.infinity;
      return Geolocator.distanceBetween(
        user.latitude,
        user.longitude,
        lat,
        lng,
      );
    }

    final sorted = List<dynamic>.from(venues);
    sorted.sort((a, b) => distanceOf(a).compareTo(distanceOf(b)));
    return sorted;
  }
}
