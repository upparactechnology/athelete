import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:4000/api';
  static const String fallbackUrl = 'http://192.168.29.240:4000/api';

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
  static Future<Map<String, dynamic>> requestOtp(String phoneNumber, {String? password, bool? isSignUp}) async {
    await checkServerUrl();
    final res = await http.post(
      Uri.parse('$_activeUrl/auth/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phoneNumber': phoneNumber,
        if (password != null) 'password': password,
        if (isSignUp != null) 'isSignUp': isSignUp,
      }),
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

  static Future<Map<String, dynamic>> googleLogin(String email, String name) async {
    await checkServerUrl();
    final res = await http.post(
      Uri.parse('$_activeUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'name': name,
        'role': 'partner',
      }),
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

  static Future<Map<String, dynamic>> updateProfile({
    String? fcmToken,
    String? phoneNumber,
    String? email,
    String? bankName,
    String? bankAccountNo,
    String? bankIfsc,
    String? avatarUrl,
  }) async {
    final res = await http.patch(
      Uri.parse('$_activeUrl/users/me'),
      headers: await _headers(),
      body: jsonEncode({
        if (fcmToken != null) 'fcm_token': fcmToken,
        if (phoneNumber != null) 'phone_number': phoneNumber,
        if (email != null) 'email': email,
        if (bankName != null) 'bank_name': bankName,
        if (bankAccountNo != null) 'bank_account_no': bankAccountNo,
        if (bankIfsc != null) 'bank_ifsc': bankIfsc,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> deleteProfile() async {
    final res = await http.delete(Uri.parse('$_activeUrl/users/me'), headers: await _headers());
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
    String? openingTime,
    String? closingTime,
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
        'openingTime': openingTime,
        'closingTime': closingTime,
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
    String? openingTime,
    String? closingTime,
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
        'openingTime': openingTime,
        'closingTime': closingTime,
      }),
    );
    return jsonDecode(res.body);
  }

  // 4. Slots & Blocking Operations
  static Future<Map<String, dynamic>> getPartnerVenueSlots(String venueId, String date) async {
    final res = await http.get(Uri.parse('$_activeUrl/partner/venues/$venueId/slots?date=$date'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> bulkGenerateSlots(String venueId, List<String> dates, String startTime, String endTime, double price, int durationMinutes) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/venues/$venueId/slots/bulk'),
      headers: await _headers(),
      body: jsonEncode({
        'dates': dates,
        'startTime': startTime,
        'endTime': endTime,
        'price': price,
        'durationMinutes': durationMinutes,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> bulkDeleteSlots(String venueId, List<String> slotIds) async {
    final res = await http.delete(
      Uri.parse('$_activeUrl/partner/venues/$venueId/slots/bulk'),
      headers: await _headers(),
      body: jsonEncode({
        'slotIds': slotIds,
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
  static Future<Map<String, dynamic>> submitPartnerKyc(
    String documentType, 
    String fileUrl, {
    String? gstNumber,
    String? panNumber,
    String? aadhaarNumber,
  }) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/partner/kyc'),
      headers: await _headers(),
      body: jsonEncode({
        'documentType': documentType,
        'fileUrl': fileUrl,
        if (gstNumber != null) 'gstNumber': gstNumber,
        if (panNumber != null) 'panNumber': panNumber,
        if (aadhaarNumber != null) 'aadhaarNumber': aadhaarNumber,
      }),
    );
    return jsonDecode(res.body);
  }

  // 10. Settings
  static Future<Map<String, dynamic>> getSettings() async {
    final res = await http.get(Uri.parse('$_activeUrl/content/settings'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 11. Banners Discovery
  static Future<Map<String, dynamic>> getBanners() async {
    final res = await http.get(Uri.parse('$_activeUrl/content/banners?target=partner'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 12. File Upload
  static Future<Map<String, dynamic>> uploadFile(String filePath) async {
    await checkServerUrl();
    final token = await getToken();
    final request = http.MultipartRequest('POST', Uri.parse('$_activeUrl/upload'));
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    
    final extension = filePath.split('.').last.toLowerCase();
    MediaType contentType;
    if (extension == 'pdf') {
      contentType = MediaType('application', 'pdf');
    } else if (extension == 'png') {
      contentType = MediaType('image', 'png');
    } else if (extension == 'jpg' || extension == 'jpeg') {
      contentType = MediaType('image', 'jpeg');
    } else {
      contentType = MediaType('application', 'octet-stream');
    }

    request.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      contentType: contentType,
    ));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    return jsonDecode(response.body);
  }

  // 13. Support Ticket
  static Future<Map<String, dynamic>> submitSupportTicket(String title, String description) async {
    await checkServerUrl();
    final res = await http.post(
      Uri.parse('$_activeUrl/reports'),
      headers: await _headers(),
      body: jsonEncode({
        'title': title,
        'description': description,
      }),
    );
    return jsonDecode(res.body);
  }
}
