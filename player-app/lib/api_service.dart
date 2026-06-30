import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator to connect to localhost, fallback to localhost for desktop/web
  static const String baseUrl = 'http://192.168.29.240:4000/api';
  static const String fallbackUrl = 'http://localhost:4000/api';

  static String _activeUrl = baseUrl;

  static String get activeUrl => _activeUrl;

  static Future<void> checkServerUrl() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/content/banners')).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        _activeUrl = baseUrl;
        return;
      }
    } catch (_) {}
    _activeUrl = fallbackUrl;
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<void> setToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  static Future<Map<String, String>> _headers() async {
    final token = await getToken();
    final headers = {
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  // 1. Authentication
  static Future<Map<String, dynamic>> requestOtp(String phoneNumber) async {
    await checkServerUrl();
    final res = await http.post(
      Uri.parse('$_activeUrl/auth/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phoneNumber': phoneNumber}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> verifyOtp(String phoneNumber, String otp) async {
    await checkServerUrl();
    final res = await http.post(
      Uri.parse('$_activeUrl/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phoneNumber': phoneNumber, 'otp': otp, 'role': 'user'}),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true && data['data']?['accessToken'] != null) {
      await setToken(data['data']['accessToken']);
    }
    return data;
  }

  // 2. Profile
  static Future<Map<String, dynamic>> getProfile() async {
    final res = await http.get(Uri.parse('$_activeUrl/users/me'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateProfile(String name, String email, {String? phoneNumber}) async {
    final res = await http.patch(
      Uri.parse('$_activeUrl/users/me'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'email': email,
        if (phoneNumber != null) 'phone_number': phoneNumber,
      }),
    );
    return jsonDecode(res.body);
  }

  // 3. Wishlists
  static Future<Map<String, dynamic>> getWishlist() async {
    final res = await http.get(Uri.parse('$_activeUrl/users/me/wishlist'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> toggleWishlist(String venueId) async {
    final res = await http.post(Uri.parse('$_activeUrl/users/me/wishlist/$venueId'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 4. Venues & Slots
  static Future<Map<String, dynamic>> getVenues({String? sport, double? lat, double? lng}) async {
    String url = '$_activeUrl/venues';
    final queryParams = <String>[];
    if (sport != null && sport.isNotEmpty) {
      queryParams.add('sport=$sport');
    }
    if (lat != null && lng != null) {
      queryParams.add('lat=$lat');
      queryParams.add('lng=$lng');
    }
    if (queryParams.isNotEmpty) {
      url += '?${queryParams.join('&')}';
    }
    final res = await http.get(Uri.parse(url), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getVenueDetails(String id) async {
    final res = await http.get(Uri.parse('$_activeUrl/venues/$id'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createReview(String venueId, double rating, String comment) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/venues/$venueId/reviews'),
      headers: await _headers(),
      body: jsonEncode({
        'rating': rating.toInt(),
        'comment': comment,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> getSlots(String venueId, String date) async {
    final res = await http.get(Uri.parse('$_activeUrl/venues/$venueId/slots?date=$date'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 5. Bookings
  static Future<Map<String, dynamic>> getBookings() async {
    final res = await http.get(Uri.parse('$_activeUrl/bookings'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createBooking(String venueId, String slotId, String paymentMode, {String? couponCode}) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/bookings'),
      headers: await _headers(),
      body: jsonEncode({
        'venueId': venueId,
        'slotId': slotId,
        'paymentMode': paymentMode,
        'couponCode': couponCode,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> cancelBooking(String bookingId) async {
    final res = await http.patch(Uri.parse('$_activeUrl/bookings/$bookingId/cancel'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 6. Payments
  static Future<Map<String, dynamic>> initiatePayment(String bookingId) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/payments/initiate'),
      headers: await _headers(),
      body: jsonEncode({'bookingId': bookingId}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> verifyPayment(String bookingId, String orderId, String paymentId) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/payments/verify'),
      headers: await _headers(),
      body: jsonEncode({
        'bookingId': bookingId,
        'razorpayOrderId': orderId,
        'razorpayPaymentId': paymentId,
      }),
    );
    return jsonDecode(res.body);
  }

  // 7. Coupons
  static Future<Map<String, dynamic>> getCoupons() async {
    final res = await http.get(Uri.parse('$_activeUrl/coupons'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 8. Tournaments
  static Future<Map<String, dynamic>> getTournaments() async {
    final res = await http.get(Uri.parse('$_activeUrl/tournaments'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> registerTournament(String tournamentId, String teamName) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/tournaments/$tournamentId/register'),
      headers: await _headers(),
      body: jsonEncode({'teamName': teamName}),
    );
    return jsonDecode(res.body);
  }

  // 9. Banners
  static Future<Map<String, dynamic>> getBanners() async {
    final res = await http.get(Uri.parse('$_activeUrl/content/banners?target=user'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 10. Notifications
  static Future<Map<String, dynamic>> getNotifications() async {
    final res = await http.get(Uri.parse('$_activeUrl/notifications'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> readNotification(String id) async {
    final res = await http.patch(Uri.parse('$_activeUrl/notifications/$id/read'), headers: await _headers());
    return jsonDecode(res.body);
  }
}

