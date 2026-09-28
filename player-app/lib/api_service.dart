import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use 10.0.2.2 for Android Emulator to connect to localhost, fallback to localhost for desktop/web
  static const String baseUrl = 'http://192.168.1.13:4000/api';
  static const String fallbackUrl = 'http://172.19.144.1:4000/api';

  static String _activeUrl = baseUrl;

  static String get activeUrl => _activeUrl;

  /// Rewrites backend media URLs so they load on-device.
  /// Uploads created via localhost admin carry a `localhost` host which is
  /// unreachable from the phone; those (and relative paths) are rebased onto
  /// the currently active API host. Already-correct URLs pass through.
  static String resolveMediaUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    try {
      final active = Uri.parse(_activeUrl);
      if (trimmed.startsWith('/')) {
        return '${active.scheme}://${active.host}:${active.port}$trimmed';
      }
      final parsed = Uri.parse(trimmed);
      if (parsed.host == 'localhost' || parsed.host == '127.0.0.1') {
        return parsed.replace(host: active.host, port: active.port).toString();
      }
    } catch (_) {}
    return trimmed;
  }

  static Future<void> checkServerUrl() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/content/banners')).timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        _activeUrl = baseUrl;
        return;
      }
    } catch (_) {}
    _activeUrl = baseUrl;
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

  /// Normalizes an Indian mobile number to E.164 (`+91XXXXXXXXXX`).
  /// Accepts 10-digit numbers with or without +91 / 91 / 0 prefixes and
  /// never duplicates the country code in the stored value.
  static String normalizeIndianPhone(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    // Strip domestic trunk zeros: 09876543210 -> 9876543210
    while (digits.startsWith('0') && digits.length > 10) {
      digits = digits.substring(1);
    }
    // Strip repeated country codes: +91 91... -> single +91
    while (digits.startsWith('91') && digits.length > 10) {
      digits = digits.substring(2);
    }
    return '+91$digits';
  }

  /// True when [input] holds exactly one 10-digit Indian mobile number.
  static bool isValidIndianPhone(String input) {
    return RegExp(r'^\+91\d{10}$').hasMatch(normalizeIndianPhone(input));
  }

  /// The 10-digit national part for display/prefill,
  /// e.g. '+919876543210' -> '9876543210'.
  static String nationalMobileNumber(String? stored) {
    if (stored == null || stored.isEmpty) return '';
    return normalizeIndianPhone(stored).replaceFirst('+91', '');
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
        'role': 'user',
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
      body: jsonEncode({'phoneNumber': phoneNumber, 'otp': otp, 'role': 'user'}),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true && data['data']?['accessToken'] != null) {
      await setToken(data['data']['accessToken']);
    }
    return data;
  }

  static Future<Map<String, dynamic>> googleLogin(String idToken) async {
    await checkServerUrl();
    final res = await http.post(
      Uri.parse('$_activeUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'idToken': idToken,
        'role': 'user',
      }),
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

  static Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? email,
    String? phoneNumber,
    String? city,
    String? state,
    String? password,
    String? fcmToken,
    String? avatarUrl,
  }) async {
    await checkServerUrl();
    final res = await http.patch(
      Uri.parse('$_activeUrl/users/me'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (email != null) 'email': email,
        if (phoneNumber != null) 'phone_number': phoneNumber.isEmpty ? phoneNumber : normalizeIndianPhone(phoneNumber),
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        if (password != null) 'password': password,
        if (fcmToken != null) 'fcm_token': fcmToken,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }),
    );
    return jsonDecode(res.body);
  }

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

  static Future<Map<String, dynamic>> reportProblem(String title, String description) async {
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

  /// Cancels a booking and releases its slot.
  ///
  /// With [pendingOnly] the server only cancels a booking that is STILL
  /// PENDING (the auto-release path used after a failed payment) and answers
  /// `success:false` with `error.code = NOT_PENDING` (plus the current status
  /// in `error.details.status`) otherwise. The response is authoritative:
  /// callers must inspect `success` and `data.bookingStatus` / `data.slotStatus`.
  static Future<Map<String, dynamic>> cancelBooking(String bookingId, {bool pendingOnly = false}) async {
    final res = await http.patch(
      Uri.parse('$_activeUrl/bookings/$bookingId/cancel'),
      headers: await _headers(),
      body: jsonEncode({'pendingOnly': pendingOnly}),
    );
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

  static Future<Map<String, dynamic>> verifyPayment(
    String bookingId,
    String orderId,
    String paymentId, {
    String? signature,
  }) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/payments/verify'),
      headers: await _headers(),
      body: jsonEncode({
        'bookingId': bookingId,
        'razorpayOrderId': orderId,
        'razorpayPaymentId': paymentId,
        if (signature != null && signature.isNotEmpty)
          'razorpaySignature': signature,
      }),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> initiateWalletPayment(double amount) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/payments/wallet/initiate'),
      headers: await _headers(),
      body: jsonEncode({'amount': amount}),
    );
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> verifyWalletDeposit(
    String orderId,
    String paymentId, {
    double? amount,
    String? signature,
  }) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/payments/wallet/verify'),
      headers: await _headers(),
      body: jsonEncode({
        'razorpayOrderId': orderId,
        'razorpayPaymentId': paymentId,
        if (amount != null) 'amount': amount,
        if (signature != null && signature.isNotEmpty)
          'razorpaySignature': signature,
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

  // 11. System Settings
  static Future<Map<String, dynamic>> getSystemSettings() async {
    final res = await http.get(Uri.parse('$_activeUrl/content/settings'), headers: await _headers());
    return jsonDecode(res.body);
  }

  // 12. Chat History
  static Future<Map<String, dynamic>> getChatHistory() async {
    final res = await http.get(Uri.parse('$_activeUrl/chat/history'), headers: await _headers());
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> sendChatMessage(String recipientId, String text) async {
    final res = await http.post(
      Uri.parse('$_activeUrl/chat/send'),
      headers: await _headers(),
      body: jsonEncode({
        'recipientId': recipientId,
        'text': text,
      }),
    );
    return jsonDecode(res.body);
  }
}

