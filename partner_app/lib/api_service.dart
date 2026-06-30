import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl =  'http://192.168.29.240:4000/api';
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
      body: jsonEncode({'phoneNumber': phoneNumber, 'otp': otp, 'role': 'partner'}), // Forces Partner role
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true && data['data']?['accessToken'] != null) {
      await setToken(data['data']['accessToken']);
    }
    return data;
  }

  // 2. Profile & Settings
  static Future<Map<String, dynamic>> getProfile() async {
    final res = await http.get(Uri.parse('$_activeUrl/users/me'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updateProfile({String? fcmToken, String? phoneNumber, String? email}) async {
    final res = await http.patch(
      Uri.parse('$_activeUrl/users/me'),
      headers: await _headers(),
      body: jsonEncode({
        if (fcmToken != null) 'fcm_token': fcmToken,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (email != null) 'email': email,
      }),
    );
    return jsonDecode(res.body);
  }

  // 3. Venues Operations
  static Future<Map<String, dynamic>> getPartnerVenues() async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/venues'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createPartnerVenue({
    required String name,
    required List<String> sportTypes,
    required double basePrice,
    required String slotMode,
    required List<String> amenities,
    required List<String> images,
    required String address,
    required String contactPhone,
    double? latitude,
    double? longitude,
  }) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/venues'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'sportTypes': sportTypes,
        'basePrice': basePrice,
        'slotMode': slotMode,
        'amenities': amenities,
        'images': images,
        'address': address,
        'contactPhone': contactPhone,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> updatePartnerVenue({
    required String venueId,
    required String name,
    required List<String> sportTypes,
    required double basePrice,
    required String slotMode,
    required List<String> amenities,
    required List<String> images,
    required String address,
    required String contactPhone,
    double? latitude,
    double? longitude,
  }) async {
    final res = await http.patch(
      Uri.parse('$_activeUrl/partner/venues/$venueId'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        'sportTypes': sportTypes,
        'basePrice': basePrice,
        'slotMode': slotMode,
        'amenities': amenities,
        'images': images,
        'address': address,
        'contactPhone': contactPhone,
        'latitude': latitude,
        'longitude': longitude,
      }),
    );
    return jsonDecode(res.body);
  }

  // 4. Slots & Blocking Operations
  static Future<Map<String, dynamic>> getPartnerVenueSlots(String venueId, String date) async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/venues/$venueId/slots?date=$date'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> bulkGenerateSlots(String venueId, String date, String startTime, String endTime, double price, int durationMinutes) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/venues/$venueId/slots/bulk'),
      headers: await _headers(),
      body: jsonEncode({
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
        'price': price,
        'durationMinutes': durationMinutes,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> toggleSlotBlock(String slotId) async {
    final res = await http.patch(Uri.parse('$_activeUrl/partner/slots/$slotId/block'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 5. Bookings & Check-in
  static Future<Map<String, dynamic>> getPartnerBookings() async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/bookings'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> checkinBooking(String bookingId) async {
    final res = await http.patch(Uri.parse('$_activeUrl/partner/bookings/$bookingId/checkin'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 6. Disputes
  static Future<Map<String, dynamic>> getPartnerDisputes() async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/disputes'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> createPartnerDispute(String bookingId, String details) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/disputes'),
      headers: await _headers(),
      body: jsonEncode({
        'bookingId': bookingId,
        'details': details,
      }),
    );
    return jsonDecode(res.body);
  }

  // 7. Settlements
  static Future<Map<String, dynamic>> getPartnerSettlements() async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/settlements'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 8. Reviews
  static Future<Map<String, dynamic>> getPartnerReviews() async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/reviews'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> replyToReview(String reviewId, String reply) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/reviews/$reviewId/reply'),
      headers: await _headers(),
      body: jsonEncode({'reply': reply}),
    );
    return jsonDecode(res.body);
  }

  // 9. KYC
  static Future<Map<String, dynamic>> submitPartnerKyc(String documentType, String fileUrl) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/kyc'),
      headers: await _headers(),
      body: jsonEncode({
        'documentType': documentType,
        'fileUrl': fileUrl,
      }),
    );
    return jsonDecode(res.body);
  }

  // 10. Banners Discovery
  static Future<Map<String, dynamic>> getBanners() async {
    final res = await http.get(Uri.parse('$_activeUrl/content/banners?target=partner'), headers: await _headers());
    return jsonDecode(res.body);
  }
}
