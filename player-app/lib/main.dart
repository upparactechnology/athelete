import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'websocket_sync.dart';
import 'api_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class AppColors {
  static const Color pink = Color(0xFFFF5C93);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color background = Color(0xFF0A0A0C);
  static const Color surface = Color(0xFF111113);
  static const Color card = Color(0xFF18181B);
  static const Gradient brandGradient = LinearGradient(
    colors: [pink, purple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

List<String> _parseVenueImages(dynamic imagesData) {
  final List<dynamic> images = imagesData is List ? imagesData : [];
  if (images.isEmpty) {
    return [
      "https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?q=80&w=800",
      "https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=800"
    ];
  }
  return images.map((i) {
    final path = i.toString();
    if (path.startsWith('data:image') || path.length > 100) return path;
    if (path.startsWith('http')) return path;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final baseUrl = ApiService.activeUrl.replaceAll('/api', '');
    return '$baseUrl$cleanPath';
  }).toList();
}

Widget _buildVenueImage(String imageStr, {required double height, double? width, required BoxFit fit}) {
  if (imageStr.startsWith('data:image') || (!imageStr.startsWith('http') && !imageStr.startsWith('/') && imageStr.length > 100)) {
    try {
      String base64Body = imageStr;
      if (imageStr.contains(',')) {
        base64Body = imageStr.split(',').last;
      }
      final bytes = base64Decode(base64Body);
      return Image.memory(
        bytes,
        height: height,
        width: width,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => Image.network(
          "https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?q=80&w=800",
          height: height,
          width: width,
          fit: fit,
        ),
      );
    } catch (_) {}
  }
  
  return Image.network(
    imageStr,
    height: height,
    width: width,
    fit: fit,
    errorBuilder: (context, error, stackTrace) => Image.network(
      "https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?q=80&w=800",
      height: height,
      width: width,
      fit: fit,
    ),
  );
}

// Theme extension for context-aware styling
extension ThemeHelper on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bgCol => isDark ? AppColors.background : const Color(0xFFF5F7FB);
  Color get cardCol => isDark ? AppColors.card : Colors.white;
  Color get textCol => isDark ? Colors.white : const Color(0xFF1A1A1A);
  Color get subtextCol => isDark ? Colors.white70 : const Color(0xFF6B7280);
  Color get borderCol => isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);
}

// Custom Premium Toast
class AppToast {
  static void show(BuildContext context, String message, {bool isError = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: isError
            ? Colors.redAccent
            : (isDark ? AppColors.pink : AppColors.purple),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.checkServerUrl();
  runApp(const AthletePOVPlayerApp());
}

class AthletePOVPlayerApp extends StatefulWidget {
  const AthletePOVPlayerApp({super.key});

  @override
  State<AthletePOVPlayerApp> createState() => _AthletePOVPlayerAppState();
}

class _AthletePOVPlayerAppState extends State<AthletePOVPlayerApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Athlete's POV",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        primaryColor: const Color(0xFF10B981),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF059669),
          surface: Colors.white,
          onSurface: Colors.black87,
        ),
        fontFamily: 'Inter',
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0C),
        primaryColor: const Color(0xFF10B981),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981),
          secondary: Color(0xFF34D399),
          surface: Color(0xFF16161A),
          onSurface: Colors.white70,
        ),
        fontFamily: 'Inter',
      ),
      home: SplashScreen(toggleTheme: toggleTheme),
    );
  }
}

// -------------------------------------------------------------
// Splash Screen
// -------------------------------------------------------------
class SplashScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const SplashScreen({super.key, required this.toggleTheme});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    final token = await ApiService.getToken();
    if (!mounted) return;
    if (token != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
        ),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => LoginScreen(toggleTheme: widget.toggleTheme),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_soccer, size: 80, color: Color(0xFF10B981)),
            SizedBox(height: 20),
            Text(
              "Athlete's POV",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            SizedBox(height: 10),
            Text("Let's Play!", style: TextStyle(color: Colors.grey, fontSize: 16)),
            SizedBox(height: 30),
            CircularProgressIndicator(color: Color(0xFF10B981)),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Login Screen
// -------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const LoginScreen({super.key, required this.toggleTheme});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpRequested = false;
  bool _isLoading = false;

  void _requestOtp() async {
    if (_phoneController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final response = await ApiService.requestOtp(_phoneController.text.trim());
    if (mounted) setState(() => _isLoading = false);

    if (response['success'] == true) {
      setState(() => _otpRequested = true);
      AppToast.show(context, response['data']['message'] ?? 'OTP Sent!');
    } else {
      AppToast.show(context, 'Failed to request OTP', isError: true);
    }
  }

  void _verifyOtp() async {
    if (_otpController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final response = await ApiService.verifyOtp(_phoneController.text.trim(), _otpController.text.trim());
    if (mounted) setState(() => _isLoading = false);

    if (response['success'] == true) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
        ),
      );
    } else {
      if (!mounted) return;
      AppToast.show(context, response['error']?['message'] ?? 'Verification failed', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: context.bgCol,
      body: Stack(
        children: [
          // Background subtle gradients
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.pink.withOpacity(0.12),
              ),
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container()),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.purple.withOpacity(0.12),
              ),
              child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80), child: Container()),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28.0),
                child: GlassContainer(
                  padding: const EdgeInsets.all(28.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(
                        child: CircleAvatar(
                          radius: 36,
                          backgroundColor: Colors.white12,
                          child: Icon(Icons.sports_soccer_rounded, size: 40, color: AppColors.pink),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _otpRequested ? "Verify OTP" : "Let's Get Started",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sora(fontSize: 24, fontWeight: FontWeight.bold, color: textCol),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _otpRequested ? "Enter the 6-digit code sent to you" : "Enter your phone number to login or register",
                        textAlign: TextAlign.center,
                        style: GoogleFonts.sora(color: subtextCol, fontSize: 13),
                      ),
                      const SizedBox(height: 32),
                      if (!_otpRequested) ...[
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.sora(color: textCol),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.phone_iphone_rounded, color: AppColors.pink),
                            hintText: "Phone Number",
                            hintStyle: GoogleFonts.sora(color: Colors.grey),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _requestOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text("Request OTP", style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.sora(color: textCol),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.pink),
                            hintText: "Enter OTP (e.g. 123456)",
                            hintStyle: GoogleFonts.sora(color: Colors.grey),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _verifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text("Verify & Login", style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => setState(() => _otpRequested = false),
                          child: Text("Change Phone Number", style: GoogleFonts.sora(color: AppColors.pink, fontWeight: FontWeight.bold)),
                        )
                      ]
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Dashboard & Tabs Screen
// -------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const DashboardScreen({super.key, required this.toggleTheme});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  String _currentLocation = "📍 Select Location";
  bool _isLocationDialogOpen = false;
  bool _isPermissionDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _detectLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _detectLocation();
    }
  }

  void _detectLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _currentLocation = "📍 Select Location");
        _showLocationDisabledDialog();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        _showPermissionRequiredDialog();
        return;
      }
      
      if (permission == LocationPermission.deniedForever) {
        setState(() => _currentLocation = "📍 Select Location");
        _showPermissionDeniedForeverDialog();
        return;
      }

      _fetchPositionAndLoad();
    } catch (e) {
      debugPrint("Geolocator Error: $e");
      setState(() => _currentLocation = "📍 Select Location");
    }
  }

  void _fetchPositionAndLoad() async {
    try {
      Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      }
      final area = await _getAreaName(position.latitude, position.longitude);
      setState(() {
        _currentLocation = area;
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("user_last_location", area);
      await prefs.setDouble("user_latitude", position.latitude);
      await prefs.setDouble("user_longitude", position.longitude);
    } catch (e) {
      debugPrint("Position fetch error: $e");
    }
  }

  Future<String> _getAreaName(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=14');
      final response = await http.get(url, headers: {'User-Agent': 'athlete_player_app'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] ?? {};
        final suburb = address['suburb'] ?? address['neighbourhood'] ?? address['village'] ?? address['subdivision'] ?? '';
        final city = address['city'] ?? address['town'] ?? address['state'] ?? '';
        if (suburb.isNotEmpty && city.isNotEmpty) {
          return "$suburb, $city";
        } else if (city.isNotEmpty) {
          return city;
        } else if (suburb.isNotEmpty) {
          return suburb;
        }
      }
    } catch (_) {}
    return "Ahmedabad, Gujarat";
  }

  void _showGlassDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
    required String primaryText,
    required VoidCallback onPrimary,
    required String secondaryText,
    required VoidCallback onSecondary,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
        final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: GlassContainer(
            radius: 24,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: iconColor.withOpacity(0.15),
                  child: Icon(icon, color: iconColor, size: 32),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: GoogleFonts.sora(fontSize: 13, color: subtextCol, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onSecondary,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text(secondaryText, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: textCol)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ElevatedButton(
                          onPressed: onPrimary,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: Text(primaryText, style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLocationDisabledDialog() {
    if (_isLocationDialogOpen) return;
    _isLocationDialogOpen = true;
    _showGlassDialog(
      icon: Icons.location_off_rounded,
      iconColor: Colors.orangeAccent,
      title: "Enable Location",
      description: "Turn on your device location to discover nearby sports venues, accurate distances, and personalized recommendations.",
      secondaryText: "Not Now",
      onSecondary: () {
        _isLocationDialogOpen = false;
        Navigator.pop(context);
      },
      primaryText: "Turn On Location",
      onPrimary: () {
        _isLocationDialogOpen = false;
        Navigator.pop(context);
        Geolocator.openLocationSettings();
      },
    );
  }

  void _showPermissionRequiredDialog() {
    if (_isPermissionDialogOpen) return;
    _isPermissionDialogOpen = true;
    _showGlassDialog(
      icon: Icons.my_location_rounded,
      iconColor: AppColors.pink,
      title: "Allow Location Access",
      description: "We use your location to:\n• Find nearby venues\n• Show accurate distances\n• Improve search results\n• Recommend sports facilities\n\nWe never share your location with third parties.",
      secondaryText: "Skip for Now",
      onSecondary: () {
        _isPermissionDialogOpen = false;
        Navigator.pop(context);
      },
      primaryText: "Allow Access",
      onPrimary: () async {
        _isPermissionDialogOpen = false;
        Navigator.pop(context);
        LocationPermission permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showPermissionDeniedDialog();
        } else if (permission == LocationPermission.deniedForever) {
          _showPermissionDeniedForeverDialog();
        } else {
          _fetchPositionAndLoad();
        }
      },
    );
  }

  void _showPermissionDeniedDialog() {
    _showGlassDialog(
      icon: Icons.gpp_maybe_rounded,
      iconColor: Colors.redAccent,
      title: "Location Permission Needed",
      description: "Without location access, nearby venues and distance calculations won't work correctly.",
      secondaryText: "Skip",
      onSecondary: () => Navigator.pop(context),
      primaryText: "Try Again",
      onPrimary: () async {
        Navigator.pop(context);
        LocationPermission permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
          _fetchPositionAndLoad();
        }
      },
    );
  }

  void _showPermissionDeniedForeverDialog() {
    _showGlassDialog(
      icon: Icons.lock_outline_rounded,
      iconColor: Colors.red,
      title: "Location Permission Disabled",
      description: "Location permission has been permanently disabled. Please enable it from App Settings.",
      secondaryText: "Cancel",
      onSecondary: () => Navigator.pop(context),
      primaryText: "Open Settings",
      onPrimary: () {
        Navigator.pop(context);
        Geolocator.openAppSettings();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      HomeTab(toggleTheme: widget.toggleTheme, currentLocation: _currentLocation),
      const BookingsTab(),
      const TournamentsTab(),
      const CouponsTab(),
      ProfileTab(toggleTheme: widget.toggleTheme),
    ];

    return Scaffold(
      backgroundColor: context.bgCol,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: tabs,
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GlassContainer(
              useBlur: true,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 54,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildNavItem(0, Icons.home_rounded, "Home"),
                      _buildNavItem(1, Icons.calendar_month_rounded, "Bookings"),
                      _buildNavItem(2, Icons.sports_rounded, "Events"),
                      _buildNavItem(3, Icons.percent_rounded, "Coupons"),
                      _buildNavItem(4, Icons.person_rounded, "Profile"),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.pink;
    final inactiveColor = isDark ? Colors.white.withOpacity(0.6) : const Color(0xFF4B5563);

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentIndex = index;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isSelected ? activeColor.withOpacity(0.12) : Colors.transparent,
          border: Border.all(
            color: isSelected ? activeColor.withOpacity(0.2) : Colors.transparent,
            width: 1.0,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: activeColor.withOpacity(0.15),
              blurRadius: 16,
              spreadRadius: -2,
            )
          ] : null,
        ),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 280),
          scale: isSelected ? 1.06 : 1.0,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? activeColor : inactiveColor,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? activeColor : inactiveColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// -------------------------------------------------------------
// Home Tab
// -------------------------------------------------------------
class HomeTab extends StatefulWidget {
  final VoidCallback toggleTheme;
  final String currentLocation;
  const HomeTab({super.key, required this.toggleTheme, required this.currentLocation});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<dynamic> _venues = [];
  List<dynamic> _banners = [];
  String _selectedSport = "All";
  late String _selectedCity;
  bool _isLoading = true;
  List<dynamic> _notifications = [];
  final FocusNode _searchFocusNode = FocusNode();
  bool _isSearchFocused = false;

  // Filter params
  double _maxPrice = 5000;
  double _minRating = 0.0;

  final Map<String, Map<String, double>> _cityCoords = {
    "Madhupura, Gujarat": {"lat": 23.03, "lng": 72.58},
    "Bengaluru": {"lat": 12.97, "lng": 77.59},
    "Mumbai": {"lat": 19.07, "lng": 72.87},
    "Delhi": {"lat": 28.61, "lng": 77.23},
  };

  void _loadNotifications() async {
    try {
      final res = await ApiService.getNotifications();
      if (res['success'] == true) {
        setState(() {
          _notifications = res['data'] ?? [];
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _selectedCity = widget.currentLocation;
    if (_selectedCity == "📍 Select Location" || _selectedCity.contains("Select")) {
      _selectedCity = "Madhupura, Gujarat";
    }
    _searchFocusNode.addListener(() {
      setState(() {
        _isSearchFocused = _searchFocusNode.hasFocus;
      });
    });
    _loadData();
  }

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation != widget.currentLocation) {
      setState(() {
        _selectedCity = widget.currentLocation;
        if (_selectedCity == "📍 Select Location" || _selectedCity.contains("Select")) {
          _selectedCity = "Madhupura, Gujarat";
        }
      });
      _loadData();
    }
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _loadData() async {
    _loadNotifications();
    setState(() => _isLoading = true);
    final bannerResponse = await ApiService.getBanners();
    final coords = _cityCoords[_selectedCity] ?? {"lat": 23.03, "lng": 72.58};
    final venueResponse = await ApiService.getVenues(
      sport: _selectedSport == "All" ? null : _selectedSport,
      lat: coords['lat'],
      lng: coords['lng'],
    );
    
    // Apply client-side filters
    final rawVenues = venueResponse['data'] as List<dynamic>? ?? [];
    final filtered = rawVenues.where((v) {
      final price = double.tryParse(v['base_price']?.toString() ?? '0') ?? 0.0;
      final rating = double.tryParse(v['avg_rating']?.toString() ?? '0') ?? 0.0;
      return price <= _maxPrice && rating >= _minRating;
    }).toList();

    setState(() {
      _banners = bannerResponse['data'] ?? [];
      _venues = filtered;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final borderCol = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);

    return Scaffold(
      backgroundColor: context.bgCol,
      appBar: AppBar(
        leading: const SizedBox(width: 0),
        leadingWidth: 0,
        title: Row(
          children: [
            const Icon(Icons.location_on_rounded, color: AppColors.pink, size: 20),
            const SizedBox(width: 6),
            DropdownButton<String>(
              value: _selectedCity,
              underline: const SizedBox(),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: textCol, size: 20),
              style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: textCol),
              dropdownColor: context.cardCol,
              items: { "Madhupura, Gujarat", "Bengaluru", "Mumbai", "Delhi", _selectedCity }.map((city) {
                return DropdownMenuItem(value: city, child: Text(city));
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedCity = val);
                  _loadData();
                }
              },
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.notifications_outlined, color: textCol),
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const NotificationBottomSheet(),
                  );
                },
              ),
              if (_notifications.any((n) => n['is_read'] != true))
                Positioned(
                  right: 12,
                  top: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.pink,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          )
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hero Section
                  Text("Good Morning 👋", style: GoogleFonts.sora(fontSize: 14, color: subtextCol)),
                  const SizedBox(height: 4),
                  Text(
                    "Let's Play",
                    style: GoogleFonts.sora(fontSize: 30, fontWeight: FontWeight.bold, color: textCol, height: 1.1),
                  ),
                  const SizedBox(height: 6),
                  Text("Find your perfect turf today", style: GoogleFonts.sora(color: subtextCol, fontSize: 13)),
                  const SizedBox(height: 16),
                  
                  // 2. Weather & Location Chips
                  Row(
                    children: [
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderCol),
                        ),
                        child: Row(
                          children: [
                            const Text("☀️", style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text("28°C Sunny", style: GoogleFonts.sora(fontSize: 12, color: textCol, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: borderCol),
                        ),
                        child: Row(
                          children: [
                            const Text("📍", style: TextStyle(fontSize: 14)),
                            const SizedBox(width: 6),
                            Text("Near You", style: GoogleFonts.sora(fontSize: 12, color: textCol, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // 3. Search Bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isSearchFocused ? AppColors.pink : borderCol,
                        width: _isSearchFocused ? 1.5 : 1.0,
                      ),
                      boxShadow: _isSearchFocused
                          ? [BoxShadow(color: AppColors.pink.withOpacity(0.12), blurRadius: 10, spreadRadius: 1)]
                          : null,
                    ),
                    child: TextField(
                      focusNode: _searchFocusNode,
                      style: GoogleFonts.sora(color: textCol, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: "Search turfs, sports or locations",
                        hintStyle: GoogleFonts.sora(color: Colors.grey, fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.pink, size: 22),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.tune_rounded, color: AppColors.pink, size: 20),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => FiltersBottomSheet(
                                currentMaxPrice: _maxPrice,
                                currentMinRating: _minRating,
                                currentSport: _selectedSport,
                                onApply: (maxP, minR, sport) {
                                  setState(() {
                                    _maxPrice = maxP;
                                    _minRating = minR;
                                  });
                                  _loadData();
                                },
                              ),
                            );
                          },
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 4. Sports Categories
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildSportChip("All", Icons.grid_view_rounded),
                        _buildSportChip("Football", Icons.sports_soccer_rounded),
                        _buildSportChip("Cricket", Icons.sports_cricket_rounded),
                        _buildSportChip("Badminton", Icons.sports_tennis_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // 5. Nearby Venues Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Nearby Venues", style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
                          const SizedBox(height: 2),
                          Text("${_venues.length} venues nearby", style: GoogleFonts.sora(fontSize: 12, color: subtextCol)),
                        ],
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ViewAllVenuesScreen(venues: _venues),
                            ),
                          );
                        },
                        child: Text("View All →", style: GoogleFonts.sora(color: AppColors.pink, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // 6. Venue Cards (Major Improvement) & Banners
                  _venues.isEmpty
                      ? _buildEmptyState(textCol, subtextCol)
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _venues.length,
                          itemBuilder: (context, index) {
                            final venue = _venues[index];
                            final widgetCard = _buildVenueCard(venue, isDark, textCol, subtextCol, borderCol);

                            // Insert featured banner below the first two cards (index == 1)
                            if (index == 1) {
                              return Column(
                                children: [
                                  widgetCard,
                                  const SizedBox(height: 8),
                                  _buildFeaturedBanner(isDark, textCol, subtextCol),
                                  const SizedBox(height: 20),
                                ],
                              );
                            }

                            return widgetCard;
                          },
                        )
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyState(Color textCol, Color subtextCol) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          children: [
            const Icon(Icons.location_off_rounded, size: 72, color: AppColors.pink),
            const SizedBox(height: 16),
            Text("No venues nearby", style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: textCol)),
            const SizedBox(height: 4),
            Text("Try changing location", style: GoogleFonts.sora(fontSize: 13, color: subtextCol)),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturedBanner(bool isDark, Color textCol, Color subtextCol) {
    return GlassContainer(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [AppColors.pink.withOpacity(0.15), AppColors.purple.withOpacity(0.15)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("🔥 Flat 20% OFF", style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.pink)),
                  const SizedBox(height: 4),
                  Text("Use code PLAY20 • Book today", style: GoogleFonts.sora(fontSize: 12, color: textCol)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => AppToast.show(context, "Code PLAY20 applied at checkout!"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text("Claim", style: GoogleFonts.sora(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueCard(dynamic venue, bool isDark, Color textCol, Color subtextCol, Color borderCol) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: GlassContainer(
        radius: 24,
        padding: const EdgeInsets.all(0),
        child: InkWell(
          onTap: () {
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(
                builder: (context) => VenueDetailScreen(venueId: venue['venue_id']),
              ),
            );
          },
          borderRadius: BorderRadius.circular(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Image Header
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                      ),
                      child: _buildVenueImage(
                        _parseVenueImages(venue['images']).first,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  // Trending Badge
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "TRENDING 🔥",
                        style: GoogleFonts.sora(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  // Rating Overlay
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.65),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            venue['avg_rating']?.toString() ?? '4.5',
                            style: GoogleFonts.sora(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Favorite & Verified Button
                  Positioned(
                    top: 14,
                    right: 14,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified_rounded, color: Colors.blueAccent, size: 16),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => AppToast.show(context, "Added to wishlist!"),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_rounded, color: AppColors.pink, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue['name'] ?? '',
                                style: GoogleFonts.sora(fontSize: 17, fontWeight: FontWeight.bold, color: textCol),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, color: Colors.grey, size: 13),
                                  const SizedBox(width: 4),
                                  Text(
                                    "${venue['address']?.toString().split(',').first ?? _selectedCity.split(',')[0]} • ${venue['distance']?.toString() ?? '0.8'} km",
                                    style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Price tag
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "₹${venue['base_price']}/hr",
                              style: GoogleFonts.sora(color: AppColors.pink, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text("Starting from", style: GoogleFonts.sora(color: Colors.grey, fontSize: 10)),
                          ],
                        )
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Quick Info
                    Row(
                      children: [
                        const Icon(Icons.sports_soccer_rounded, color: Colors.grey, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          _selectedSport == 'All' ? 'Football' : _selectedSport,
                          style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.access_time_rounded, color: Colors.grey, size: 14),
                        const SizedBox(width: 4),
                        Text("Open until 11 PM", style: GoogleFonts.sora(color: subtextCol, fontSize: 12)),
                        const SizedBox(width: 12),
                        const Icon(Icons.local_parking_rounded, color: Colors.grey, size: 14),
                        const SizedBox(width: 4),
                        Text("Parking", style: GoogleFonts.sora(color: subtextCol, fontSize: 12)),
                      ],
                    ),
                    const Divider(height: 24),
                    // Card footer small chips
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 6,
                            children: [
                              _buildMiniChip("Flood Lights", isDark),
                              _buildMiniChip("Parking", isDark),
                              _buildMiniChip("Changing Room", isDark),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context, rootNavigator: true).push(
                                MaterialPageRoute(
                                  builder: (context) => VenueDetailScreen(venueId: venue['venue_id']),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              minimumSize: const Size(90, 36),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                            ),
                            child: Text("Book Now", style: GoogleFonts.sora(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        )
                      ],
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniChip(String label, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.grey)),
    );
  }

  Widget _buildSportChip(String sport, IconData icon) {
    final isSelected = _selectedSport == sport;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSport = sport;
          _loadData();
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.brandGradient : null,
          color: isSelected ? null : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.transparent : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.grey),
            const SizedBox(width: 6),
            Text(
              sport,
              style: GoogleFonts.sora(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GlassSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;
  const GlassSkeleton({super.key, required this.width, required this.height, this.borderRadius = 16});

  @override
  State<GlassSkeleton> createState() => _GlassSkeletonState();
}

class _GlassSkeletonState extends State<GlassSkeleton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: lerpDouble(0.12, 0.35, _controller.value) ?? 0.2,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}

class VenueDetailScreen extends StatefulWidget {
  final String venueId;
  const VenueDetailScreen({super.key, required this.venueId});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  Map<String, dynamic> _venue = {};
  List<dynamic> _slots = [];
  List<dynamic> _similarVenues = [];
  bool _isLoading = true;
  String _selectedDate = "";
  dynamic _selectedSlot;
  bool _isFavorite = false;
  bool _isAboutExpanded = false;
  final PageController _imagePageController = PageController();
  int _currentImageIndex = 0;
  String _supportPhone = "9427961426";

  @override
  void initState() {
    super.initState();
    final dates = _generateDates();
    _selectedDate = dates.first;
    _loadVenueDetails();
    _loadSupportPhone();
  }

  List<String> _generateDates() {
    final List<String> dates = [];
    final today = DateTime.now();
    for (int i = 0; i < 8; i++) {
      final date = today.add(Duration(days: i));
      final yr = date.year;
      final mo = date.month.toString().padLeft(2, '0');
      final dy = date.day.toString().padLeft(2, '0');
      dates.add("$yr-$mo-$dy");
    }
    return dates;
  }

  void _loadSupportPhone() async {
    try {
      final res = await ApiService.getSystemSettings();
      if (res['success'] == true && res['data']?['supportPhone'] != null) {
        setState(() {
          _supportPhone = res['data']['supportPhone'];
        });
      }
    } catch (_) {}
  }

  void _loadVenueDetails() async {
    setState(() => _isLoading = true);
    final detailResponse = await ApiService.getVenueDetails(widget.venueId);
    final slotsResponse = await ApiService.getSlots(widget.venueId, _selectedDate);
    
    // Check favorite status
    final token = await ApiService.getToken();
    if (token != null) {
      try {
        final wishRes = await ApiService.getWishlist();
        if (wishRes['success'] == true) {
          final wishlists = wishRes['data'] as List<dynamic>? ?? [];
          _isFavorite = wishlists.any((w) => w['venue_id'] == widget.venueId);
        }
      } catch (_) {}
    }

    try {
      final simRes = await ApiService.getVenues();
      if (simRes['success'] == true) {
        final all = simRes['data'] as List<dynamic>? ?? [];
        _similarVenues = all.where((v) => v['venue_id'] != widget.venueId).take(5).toList();
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _venue = detailResponse['data'] ?? {};
        _slots = slotsResponse['data'] ?? [];
        _isLoading = false;
      });
    }
  }

  void _checkAuthAndExecute(VoidCallback onSuccess) async {
    final token = await ApiService.getToken();
    if (token == null) {
      _showLoginSheet(context, onSuccess);
    } else {
      onSuccess();
    }
  }

  void _toggleFavorite() async {
    _checkAuthAndExecute(() async {
      final res = await ApiService.toggleWishlist(widget.venueId);
      if (res['success'] == true) {
        setState(() {
          _isFavorite = !_isFavorite;
        });
        AppToast.show(context, _isFavorite ? "Saved to favorites!" : "Removed from favorites!");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = const Color(0xFF131722);
    final textCol = Colors.white;
    final subtextCol = const Color(0xFF9AA4B2);
    final borderCol = Colors.white.withOpacity(0.08);

    final List<String> displayImages = _parseVenueImages(_venue['images']);

    final String aboutText = _venue['description'] ?? "No description provided by host.";
    final List<dynamic> amenities = _venue['amenities'] ?? [];
    final List<dynamic> rules = _venue['rules'] ?? [];
    final List<dynamic> reviews = _venue['reviews'] ?? [];

    // Slots status check
    bool isClosed = _venue['status'] == 'suspended';
    bool allSlotsBooked = _slots.isNotEmpty && _slots.every((s) => s['status'] == 'booked');

    return Scaffold(
      backgroundColor: const Color(0xFF090B10),
      body: _isLoading
          ? _buildShimmerLoading()
          : Stack(
              children: [
                // Immersive Scroll View
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Hero Image Section
                      Stack(
                        children: [
                          SizedBox(
                            height: 310,
                            child: PageView.builder(
                              controller: _imagePageController,
                              onPageChanged: (index) {
                                setState(() {
                                  _currentImageIndex = index;
                                });
                              },
                              itemCount: displayImages.length,
                              itemBuilder: (context, idx) {
                                return _buildVenueImage(
                                    displayImages[idx],
                                    height: 310,
                                    fit: BoxFit.cover,
                                  );
                              },
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.5),
                                      Colors.transparent,
                                      const Color(0xFF090B10),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Float Buttons overlay
                          Positioned(
                            top: 48,
                            left: 16,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: GlassContainer(
                                radius: 20,
                                padding: EdgeInsets.zero,
                                child: CircleAvatar(
                                  backgroundColor: Colors.transparent,
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 48,
                            right: 16,
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: GlassContainer(
                                    radius: 20,
                                    padding: EdgeInsets.zero,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.transparent,
                                      child: IconButton(
                                        icon: const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                                        onPressed: () {
                                          final name = _venue['name'] ?? 'Sports Turf';
                                          final address = _venue['address'] ?? 'Ahmedabad, Gujarat';
                                          final box = context.findRenderObject() as RenderBox?;
                                          Share.share(
                                            "Check out $name located at $address! Book your slot now on Athlete's POV:\nhttps://athletepov.com/venue/${widget.venueId}",
                                            sharePositionOrigin: box != null
                                                ? box.localToGlobal(Offset.zero) & box.size
                                                : null,
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: GlassContainer(
                                    radius: 20,
                                    padding: EdgeInsets.zero,
                                    child: CircleAvatar(
                                      backgroundColor: Colors.transparent,
                                      child: IconButton(
                                        icon: Icon(
                                          _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                          color: _isFavorite ? AppColors.pink : Colors.white,
                                          size: 18,
                                        ),
                                        onPressed: _toggleFavorite,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Image carousel counter
                          Positioned(
                            bottom: 20,
                            right: 20,
                            child: GlassContainer(
                              radius: 12,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              child: Text(
                                "${_currentImageIndex + 1}/${displayImages.length}",
                                style: GoogleFonts.sora(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 2. Venue Information Card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    _venue['name'] ?? 'Sports Turf',
                                    style: GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.bold, color: textCol),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3DDC84).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified_rounded, color: Color(0xFF3DDC84), size: 13),
                                      const SizedBox(width: 4),
                                      Text("VERIFIED", style: GoogleFonts.sora(color: const Color(0xFF3DDC84), fontSize: 9, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                const SizedBox(width: 4),
                                Text(
                                  double.tryParse(_venue['avg_rating']?.toString() ?? '0.0')?.toStringAsFixed(1) ?? '0.0',
                                  style: GoogleFonts.sora(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  "•  ${reviews.length} Reviews",
                                  style: GoogleFonts.sora(color: subtextCol, fontSize: 13),
                                ),
                                const SizedBox(width: 12),
                                Text("•", style: TextStyle(color: borderCol)),
                                const SizedBox(width: 12),
                                const Icon(Icons.location_on_rounded, color: AppColors.pink, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  "2.4 km away",
                                  style: GoogleFonts.sora(color: subtextCol, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const Icon(Icons.location_city_rounded, color: Colors.grey, size: 14),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _venue['address'] ?? 'Madhupura, Ahmedabad, Gujarat',
                                    style: GoogleFonts.sora(color: subtextCol, fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(radius: 4, backgroundColor: isClosed ? Colors.red : const Color(0xFF3DDC84)),
                                    const SizedBox(width: 8),
                                    Text(
                                      isClosed ? "Suspended / Closed" : "Open until 11:00 PM",
                                      style: GoogleFonts.sora(color: isClosed ? Colors.redAccent : const Color(0xFF3DDC84), fontSize: 13, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text("Starting From ", style: GoogleFonts.sora(fontSize: 10, color: subtextCol)),
                                    Text(
                                      "₹${_venue['base_price'] ?? '1500'}/hr",
                                      style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.pink),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 3. Quick Action Buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            _buildQuickAction(Icons.phone_rounded, "Call", Colors.green, () {
                              if (_supportPhone.isEmpty) {
                                AppToast.show(context, "Support number unavailable", isError: true);
                              } else {
                                launchUrl(Uri.parse("tel:$_supportPhone"));
                              }
                            }),
                            const SizedBox(width: 8),
                            _buildQuickAction(Icons.chat_bubble_rounded, "Chat", const Color(0xFF3DDC84), () {
                              _checkAuthAndExecute(() {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => _SupportChatSheet(partnerId: _venue['partner_id']),
                                );
                              });
                            }),
                            const SizedBox(width: 8),
                            _buildQuickAction(Icons.directions_rounded, "Directions", Colors.blue, () {
                              final address = _venue['address'] ?? 'Madhupura, Ahmedabad, Gujarat';
                              final url = Uri.parse("https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(address)}");
                              launchUrl(url, mode: LaunchMode.externalApplication);
                            }),
                            const SizedBox(width: 8),
                            _buildQuickAction(
                              _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              "Save",
                              AppColors.pink,
                              _toggleFavorite,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 4. About Venue Card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GlassContainer(
                          radius: 24,
                          useBlur: false,
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("About this Venue", style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol)),
                                    const SizedBox(height: 8),
                                    Text(
                                      aboutText,
                                      style: GoogleFonts.sora(fontSize: 12, color: subtextCol, height: 1.5),
                                      maxLines: _isAboutExpanded ? null : 3,
                                      overflow: _isAboutExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                                    ),
                                    if (aboutText.length > 100) ...[
                                      const SizedBox(height: 8),
                                      GestureDetector(
                                        onTap: () => setState(() => _isAboutExpanded = !_isAboutExpanded),
                                        child: Text(
                                          _isAboutExpanded ? "Read Less" : "Read More",
                                          style: GoogleFonts.sora(fontSize: 11, color: AppColors.pink, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 5. Amenities Section (Show only if partner configured amenities)
                      if (amenities.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GlassContainer(
                            radius: 24,
                            useBlur: false,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text("Amenities", style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol)),
                                    GestureDetector(
                                      onTap: () => AppToast.show(context, "All amenities dynamic!"),
                                      child: Text("View All", style: GoogleFonts.sora(fontSize: 12, color: AppColors.pink, fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: amenities.map((item) {
                                    final aStr = item.toString();
                                    IconData icon = Icons.check_circle_outline_rounded;
                                    if (aStr.toLowerCase().contains('light')) icon = Icons.lightbulb_outline_rounded;
                                    if (aStr.toLowerCase().contains('park')) icon = Icons.local_parking_rounded;
                                    if (aStr.toLowerCase().contains('room')) icon = Icons.shower_outlined;
                                    if (aStr.toLowerCase().contains('wifi')) icon = Icons.wifi_rounded;
                                    if (aStr.toLowerCase().contains('cafe')) icon = Icons.local_cafe_outlined;
                                    return _buildAmenityTile(icon, aStr);
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 6. Review Panel
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GlassContainer(
                          radius: 24,
                          useBlur: false,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
                                      const SizedBox(width: 6),
                                      Text(
                                        double.tryParse(_venue['avg_rating']?.toString() ?? '0.0')?.toStringAsFixed(1) ?? '0.0',
                                        style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol),
                                      ),
                                      const SizedBox(width: 6),
                                      Text("(${reviews.length} Reviews)", style: GoogleFonts.sora(fontSize: 12, color: subtextCol)),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          _checkAuthAndExecute(() {
                                            showModalBottomSheet(
                                              context: context,
                                              isScrollControlled: true,
                                              backgroundColor: Colors.transparent,
                                              builder: (context) => _ReviewSheet(venueId: widget.venueId, onSubmitted: _loadVenueDetails),
                                            );
                                          });
                                        },
                                        child: Text("Write Review", style: GoogleFonts.sora(fontSize: 12, color: AppColors.purple, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 12),
                                      GestureDetector(
                                        onTap: () => AppToast.show(context, "Latest reviews shown first"),
                                        child: Text("View All", style: GoogleFonts.sora(fontSize: 12, color: AppColors.pink, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Latest Review Display
                              reviews.isEmpty
                                  ? Center(child: Text("No reviews yet. Be the first to review!", style: GoogleFonts.sora(fontSize: 12, color: subtextCol)))
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: Colors.white10,
                                              child: Text(
                                                reviews.last['user']?['name']?.toString().substring(0, 1).toUpperCase() ?? "U",
                                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        reviews.last['user']?['name'] ?? "User",
                                                        style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.bold, color: textCol),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text("Verified user", style: GoogleFonts.sora(fontSize: 9, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Row(
                                                    children: List.generate(
                                                      reviews.last['rating'] ?? 5,
                                                      (i) => const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                                    ),
                                                  )
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          reviews.last['comment'] ?? '',
                                          style: GoogleFonts.sora(fontSize: 12, color: subtextCol, height: 1.4),
                                        ),
                                      ],
                                    ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 7. Venue Rules Section (Hide if empty)
                      if (rules.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: GlassContainer(
                            radius: 24,
                            useBlur: false,
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Venue Rules", style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol)),
                                const SizedBox(height: 12),
                                ...rules.map((r) => _buildBulletRule(r.toString())),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // 8. Date Selection Slider
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "Select Date",
                          style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 76,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          children: _generateDates().map((date) {
                            final isSelected = _selectedDate == date;
                            final parsedDate = DateTime.parse(date);
                            final isWeekend = parsedDate.weekday == DateTime.saturday || parsedDate.weekday == DateTime.sunday;
                            final days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
                            
                            // Correct Today date text calculation
                            final now = DateTime.now();
                            final isToday = parsedDate.year == now.year && parsedDate.month == now.month && parsedDate.day == now.day;
                            final dayLabel = isToday ? "Today" : days[parsedDate.weekday - 1];

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedDate = date;
                                  _selectedSlot = null;
                                  _loadVenueDetails();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                width: 68,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  gradient: isSelected ? AppColors.brandGradient : null,
                                  color: isSelected ? null : cardBg,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelected ? Colors.transparent : (isWeekend ? Colors.redAccent.withOpacity(0.3) : borderCol),
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      dayLabel,
                                      style: GoogleFonts.sora(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isSelected ? Colors.white70 : (isWeekend ? Colors.redAccent : subtextCol),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      date.substring(8),
                                      style: GoogleFonts.sora(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: isSelected ? Colors.white : (isWeekend ? Colors.redAccent : textCol),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 9. Time Slot Selection Grid
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          "Select Time Slot",
                          style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _slots.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(28.0),
                                  child: Column(
                                    children: [
                                      Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
                                      const SizedBox(height: 12),
                                      Text("No slots available for this date", style: GoogleFonts.sora(color: subtextCol, fontSize: 13)),
                                    ],
                                  ),
                                ),
                              )
                            : GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 1.8,
                                ),
                                itemCount: _slots.length,
                                itemBuilder: (context, index) {
                                  final slot = _slots[index];
                                  final isBooked = slot['status'] == 'booked';
                                  final isBlocked = slot['status'] == 'blocked_by_partner';
                                  final isSelected = _selectedSlot != null && _selectedSlot['slot_id'] == slot['slot_id'];

                                  Color slotBg = cardBg;
                                  Color txtCol = textCol;
                                  String statusText = "Available";
                                  Color statusColor = const Color(0xFF3DDC84);
                                  Border border = Border.all(color: borderCol);

                                  if (isBooked) {
                                    slotBg = const Color(0xFFFF5A5F).withOpacity(0.1);
                                    txtCol = const Color(0xFFFF5A5F);
                                    statusText = "Booked";
                                    statusColor = const Color(0xFFFF5A5F);
                                    border = Border.all(color: const Color(0xFFFF5A5F).withOpacity(0.3));
                                  } else if (isBlocked) {
                                    slotBg = Colors.white.withOpacity(0.04);
                                    txtCol = Colors.grey;
                                    statusText = "Unavailable";
                                    statusColor = Colors.grey;
                                  } else if (isSelected) {
                                    slotBg = Colors.transparent;
                                    txtCol = Colors.white;
                                    statusText = "Selected";
                                    statusColor = Colors.white;
                                    border = Border.all(color: Colors.transparent);
                                  }

                                  return GestureDetector(
                                    onTap: (isBooked || isBlocked)
                                        ? null
                                        : () => setState(() => _selectedSlot = slot),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      decoration: BoxDecoration(
                                        gradient: isSelected ? AppColors.brandGradient : null,
                                        color: isSelected ? null : slotBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border: border,
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            slot['start_time'] ?? '',
                                            style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: txtCol, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            isBooked ? "❌ Booked" : (isSelected ? "✅ Selected" : "₹${slot['price']}"),
                                            style: GoogleFonts.sora(fontSize: 10, color: isSelected ? Colors.white : statusColor, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 24),

                      // 10. Cancellation Policy Card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GlassContainer(
                          radius: 24,
                          useBlur: false,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Cancellation Policy", style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol)),
                              const SizedBox(height: 8),
                              Text(
                                "Free cancellation up to 2 hours before your booking. Late cancellations may incur full or partial slot charges depending on host settings.",
                                style: GoogleFonts.sora(fontSize: 12, color: subtextCol, height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // 12. Similar Venues Slider
                      if (_similarVenues.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            "Similar Venues Nearby",
                            style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 160,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: _similarVenues.length,
                            itemBuilder: (context, index) {
                              final item = _similarVenues[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(builder: (context) => VenueDetailScreen(venueId: item['venue_id'])),
                                  );
                                },
                                child: Container(
                                  width: 150,
                                  margin: const EdgeInsets.only(right: 12),
                                  child: GlassContainer(
                                    radius: 20,
                                    useBlur: false,
                                    padding: EdgeInsets.zero,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          height: 80,
                                          decoration: BoxDecoration(
                                            color: Colors.white10,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                                            image: const DecorationImage(
                                              image: NetworkImage("https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?q=80&w=150"),
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item['name'] ?? 'Turf',
                                                style: GoogleFonts.sora(fontSize: 11, fontWeight: FontWeight.bold, color: textCol),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                "Starting from ₹${item['base_price']}",
                                                style: GoogleFonts.sora(fontSize: 9, color: AppColors.pink, fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // 13. Sticky Floating Bottom Booking Bar
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: GlassContainer(
                    useBlur: true,
                    radius: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedSlot != null ? "Selected Slot" : "Choose a Slot",
                                style: GoogleFonts.sora(fontSize: 10, color: subtextCol, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedSlot != null
                                    ? "${_selectedSlot['start_time']} • ₹${_selectedSlot['price']}"
                                    : "No slot selected",
                                style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: textCol),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            gradient: (_selectedSlot != null && !isClosed && !allSlotsBooked) ? AppColors.brandGradient : null,
                            color: (_selectedSlot == null || isClosed || allSlotsBooked) ? Colors.white10 : null,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ElevatedButton(
                            onPressed: (_selectedSlot == null || isClosed || allSlotsBooked)
                                ? null
                                : () {
                                    _checkAuthAndExecute(() {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => CheckoutScreen(
                                            venue: _venue,
                                            slot: _selectedSlot,
                                          ),
                                        ),
                                      );
                                    });
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isClosed
                                      ? "Currently Closed"
                                      : (allSlotsBooked ? "Fully Booked" : "Book Now"),
                                  style: GoogleFonts.sora(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                if (!isClosed && !allSlotsBooked)
                                  Text(
                                    "Instant Confirmation",
                                    style: GoogleFonts.sora(fontSize: 8, color: Colors.white70),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildShimmerLoading() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 30),
          const GlassSkeleton(width: double.infinity, height: 260),
          const SizedBox(height: 20),
          const GlassSkeleton(width: 250, height: 32),
          const SizedBox(height: 10),
          const GlassSkeleton(width: 180, height: 18),
          const SizedBox(height: 24),
          Row(
            children: List.generate(4, (idx) => const Expanded(child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.0),
              child: GlassSkeleton(width: double.infinity, height: 60),
            ))),
          ),
          const SizedBox(height: 24),
          const GlassSkeleton(width: double.infinity, height: 120),
        ],
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: GlassContainer(
          radius: 16,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.sora(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmenityTile(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.pink, size: 14),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.sora(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletRule(String rule) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(color: AppColors.pink, fontSize: 14)),
          Expanded(child: Text(rule, style: GoogleFonts.sora(fontSize: 12, color: const Color(0xFF9AA4B2)))),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Write Review Bottom Sheet
// -------------------------------------------------------------
class _ReviewSheet extends StatefulWidget {
  final String venueId;
  final VoidCallback onSubmitted;
  const _ReviewSheet({required this.venueId, required this.onSubmitted});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  double _rating = 5.0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _submitReview() async {
    final comment = _commentController.text.trim();
    if (comment.isEmpty) {
      AppToast.show(context, "Review text cannot be empty", isError: true);
      return;
    }
    setState(() => _submitting = true);
    final res = await ApiService.createReview(widget.venueId, _rating, comment);
    setState(() => _submitting = false);

    if (res['success'] == true) {
      AppToast.show(context, "Review submitted successfully!");
      widget.onSubmitted();
      Navigator.pop(context);
    } else {
      AppToast.show(context, res['message'] ?? "Failed to submit review", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = Colors.white;
    final cardBg = const Color(0xFF131722);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF090B10),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Write a Review", style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
            const SizedBox(height: 16),
            Text("Select Rating", style: GoogleFonts.sora(fontSize: 13, color: textCol)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starIdx = index + 1;
                return GestureDetector(
                  onTap: () => setState(() => _rating = starIdx.toDouble()),
                  child: Icon(
                    starIdx <= _rating ? Icons.star_rounded : Icons.star_border_rounded,
                    color: Colors.amber,
                    size: 38,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentController,
              maxLines: 3,
              style: GoogleFonts.sora(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: "Write your feedback...",
                hintStyle: GoogleFonts.sora(color: Colors.grey, fontSize: 13),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _submitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text("Submit Review", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// In-App Customer Support Chat Sheet
// -------------------------------------------------------------
class _SupportChatSheet extends StatefulWidget {
  final String partnerId;
  const _SupportChatSheet({required this.partnerId});

  @override
  State<_SupportChatSheet> createState() => _SupportChatSheetState();
}

class _SupportChatSheetState extends State<_SupportChatSheet> {
  final List<dynamic> _messages = [];
  final _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _loadingHistory = true;
  java_timer_support? _timer;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Auto-refresh chat every 3 seconds for mock real-time feel
    _timer = java_timer_support_periodic(const Duration(seconds: 3), (timer) {
      _loadHistory(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadHistory({bool quiet = false}) async {
    if (!quiet) setState(() => _loadingHistory = true);
    try {
      final res = await ApiService.getChatHistory();
      if (res['success'] == true) {
        final logs = res['data'] as List<dynamic>? ?? [];
        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(logs);
            _loadingHistory = false;
          });
          if (!quiet) _scrollToBottom();
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  void _sendMessage() async {
    final txt = _msgController.text.trim();
    if (txt.isEmpty) return;
    _msgController.clear();
    
    // Optimistic UI updates
    setState(() {
      _messages.add({
        'sender_role': 'user',
        'text': txt,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    _scrollToBottom();

    await ApiService.sendChatMessage(widget.partnerId, txt);
    _loadHistory(quiet: true);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textCol = Colors.white;
    final subtextCol = const Color(0xFF9AA4B2);

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Color(0xFF090B10),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Indicator & Header
          const SizedBox(height: 8),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              children: [
                const CircleAvatar(radius: 20, backgroundColor: AppColors.pink, child: Icon(Icons.support_agent_rounded, color: Colors.white)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Chat with Support", style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: textCol)),
                    Row(
                      children: [
                        const CircleAvatar(radius: 3, backgroundColor: Color(0xFF3DDC84)),
                        const SizedBox(width: 6),
                        Text("Online", style: GoogleFonts.sora(fontSize: 10, color: const Color(0xFF3DDC84))),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white10),
          
          // Message Logs
          Expanded(
            child: _loadingHistory
                ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['sender_role'] == 'user';
                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: isMe ? AppColors.brandGradient : null,
                            color: isMe ? null : Colors.white10,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(msg['text'] ?? '', style: GoogleFonts.sora(fontSize: 12, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text(
                                msg['created_at'] != null
                                    ? DateTime.parse(msg['created_at']).toLocal().toString().substring(11, 16)
                                    : '',
                                style: GoogleFonts.sora(fontSize: 8, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          
          // Send Input Panel
          Container(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).viewInsets.bottom),
            color: const Color(0xFF131722),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    style: GoogleFonts.sora(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: GoogleFonts.sora(color: Colors.grey, fontSize: 13),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send_rounded, color: AppColors.pink), onPressed: _sendMessage),
              ],
            ),
          )
        ],
      ),
    );
  }
}

typedef java_timer_support = dynamic;
dynamic java_timer_support_periodic(Duration duration, void Function(dynamic timer) callback) {
  return Stream.periodic(duration).listen((_) => callback(null));
}

// -------------------------------------------------------------
// In-App Glassmorphic Inline Login Bottom Sheet
// -------------------------------------------------------------
void _showLoginSheet(BuildContext context, VoidCallback onLoginSuccess) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _LoginModalSheet(onSuccess: onLoginSuccess),
  );
}

class _LoginModalSheet extends StatefulWidget {
  final VoidCallback onSuccess;
  const _LoginModalSheet({required this.onSuccess});

  @override
  State<_LoginModalSheet> createState() => _LoginModalSheetState();
}

class _LoginModalSheetState extends State<_LoginModalSheet> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      AppToast.show(context, "Please enter phone number", isError: true);
      return;
    }
    setState(() => _loading = true);
    final res = await ApiService.requestOtp(phone);
    setState(() => _loading = false);

    if (res['success'] == true) {
      setState(() => _otpSent = true);
      AppToast.show(context, "OTP Sent successfully!");
    } else {
      AppToast.show(context, res['message'] ?? "Failed to request OTP", isError: true);
    }
  }

  void _verifyOtp() async {
    final phone = _phoneController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      AppToast.show(context, "Please enter OTP", isError: true);
      return;
    }
    setState(() => _loading = true);
    final res = await ApiService.verifyOtp(phone, otp);
    setState(() => _loading = false);

    if (res['success'] == true) {
      AppToast.show(context, "Login Successful!");
      Navigator.pop(context);
      widget.onSuccess();
    } else {
      AppToast.show(context, res['message'] ?? "OTP Verification Failed", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textCol = Colors.white;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF090B10),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Login Required", style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
            const SizedBox(height: 8),
            Text("Please login to proceed with this action.", style: GoogleFonts.sora(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 20),
            if (!_otpSent) ...[
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.sora(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Enter Phone Number (e.g. +91...)",
                  hintStyle: GoogleFonts.sora(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text("Send OTP", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.sora(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: "Enter OTP Verification Code",
                  hintStyle: GoogleFonts.sora(color: Colors.grey, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pink,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text("Verify & Login", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Checkout & Payment Screen
// -------------------------------------------------------------
class CheckoutScreen extends StatefulWidget {
  final Map<String, dynamic> venue;
  final Map<String, dynamic> slot;
  const CheckoutScreen({super.key, required this.venue, required this.slot});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  final _couponController = TextEditingController();
  bool _payOnline = true;
  bool _isLoading = false;
  double _discount = 0.0;
  String? _appliedCouponCode;

  late Razorpay _razorpay;
  String? _currentBookingId;
  String? _currentOrderId;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  @override
  void dispose() {
    _couponController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  void _handlePaymentSuccess(PaymentSuccessResponse response) async {
    final bookingId = _currentBookingId;
    final orderId = _currentOrderId ?? response.orderId;
    if (bookingId == null || orderId == null) return;

    setState(() => _isLoading = true);
    final verifyRes = await ApiService.verifyPayment(bookingId, orderId, response.paymentId ?? '');
    if (verifyRes['success'] == true) {
      final finalBooking = verifyRes['data'];
      finalBooking['slot'] = widget.slot;
      finalBooking['venue'] = widget.venue;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ConfirmationScreen(booking: finalBooking),
        ),
      );
    } else {
      AppToast.show(context, "Payment verification failed", isError: true);
    }
    setState(() => _isLoading = false);
  }

  void _handlePaymentError(PaymentFailureResponse response) async {
    final bookingId = _currentBookingId;
    if (bookingId != null) {
      setState(() => _isLoading = true);
      await ApiService.cancelBooking(bookingId);
      setState(() => _isLoading = false);
    }
    AppToast.show(context, "Payment Failed/Cancelled: ${response.message ?? ''}", isError: true);
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    AppToast.show(context, "External wallet selected: ${response.walletName}");
  }

  void _applyCoupon() async {
    final code = _couponController.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _discount = double.parse(widget.slot['price'].toString()) * 0.1; // 10% mock discount
      _appliedCouponCode = code;
    });
    AppToast.show(context, 'Coupon "$code" applied! 10% Discount');
  }

  void _processPayment() async {
    setState(() => _isLoading = true);

    final mode = _payOnline ? "online" : "pay_at_venue";
    final bookingRes = await ApiService.createBooking(
      widget.venue['venue_id'],
      widget.slot['slot_id'],
      mode,
      couponCode: _appliedCouponCode,
    );

    if (bookingRes['success'] != true) {
      setState(() => _isLoading = false);
      AppToast.show(context, "Failed to lock slot and create booking.", isError: true);
      return;
    }

    final booking = bookingRes['data'];
    final bookingId = booking['booking_id'];
    _currentBookingId = bookingId;

    final payInit = await ApiService.initiatePayment(bookingId);
    final orderId = payInit['data']?['orderId'] ?? 'order_${MathUtils.randomString(12)}';
    final razorpayKey = payInit['data']?['key'] ?? 'rzp_test_Lp542L8X1v9n5R';
    _currentOrderId = orderId;

    // Load profile for prefill info
    String email = "athlete@example.com";
    String phone = "9999999999";
    try {
      final profile = await ApiService.getProfile();
      if (profile['success'] == true && profile['data'] != null) {
        email = profile['data']['email'] ?? email;
        phone = profile['data']['phone_number'] ?? phone;
      }
    } catch (_) {}

    setState(() => _isLoading = false);

    final options = {
      'key': razorpayKey,
      'amount': (double.parse(booking['online_amount'].toString()) * 100).toInt(),
      'name': 'Athlete App',
      'description': widget.venue['name'] ?? 'Booking Payment',
      'order_id': orderId,
      'prefill': {
        'contact': phone,
        'email': email,
      },
      'external': {
        'wallets': ['paytm']
      }
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      AppToast.show(context, "Error opening Razorpay: $e", isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final borderCol = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);

    final price = double.parse(widget.slot['price'].toString());
    final finalPrice = price - _discount;
    final convenience = finalPrice * 0.04;
    final gst = finalPrice * 0.03 * 0.18;
    final total = finalPrice + convenience + gst;

    final deposit = total * 0.3;
    final outstanding = total * 0.7;

    return Scaffold(
      backgroundColor: context.bgCol,
      appBar: AppBar(
        title: Text("Checkout", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Venue details card
                  GlassContainer(
                    radius: 20,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.sports_soccer_rounded, color: AppColors.pink, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.venue['name'] ?? '',
                                style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Time: ${widget.slot['start_time']} - ${widget.slot['end_time']}",
                                style: GoogleFonts.sora(color: subtextCol, fontSize: 13),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Coupon Code
                  Text("Have a coupon code?", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 14)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponController,
                          style: GoogleFonts.sora(color: textCol),
                          decoration: InputDecoration(
                            hintText: "Enter code (e.g. PLAY10)",
                            hintStyle: GoogleFonts.sora(color: Colors.grey, fontSize: 13),
                            filled: true,
                            fillColor: isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        decoration: BoxDecoration(
                          gradient: AppColors.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ElevatedButton(
                          onPressed: _applyCoupon,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text("Apply", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 28),

                  // Payment options split
                  Text("Payment Options", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 14)),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () => setState(() => _payOnline = true),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: _payOnline ? AppColors.pink.withOpacity(0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _payOnline ? AppColors.pink.withOpacity(0.3) : borderCol),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            _payOnline ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: _payOnline ? AppColors.pink : subtextCol,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Pay Online (Full Amount)", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text("Pay now and enjoy your game", style: GoogleFonts.sora(color: subtextCol, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _payOnline = false),
                    child: Container(
                      decoration: BoxDecoration(
                        color: !_payOnline ? AppColors.pink.withOpacity(0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: !_payOnline ? AppColors.pink.withOpacity(0.3) : borderCol),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            !_payOnline ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                            color: !_payOnline ? AppColors.pink : subtextCol,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Pay at Venue (Split Deposit)", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text("Pay 30% online now & 70% cash at court", style: GoogleFonts.sora(color: subtextCol, fontSize: 12)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Detailed price breakdown
                  GlassContainer(
                    radius: 20,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildPriceRow("Slot Price", "₹${price.toStringAsFixed(2)}", textCol),
                        if (_discount > 0) _buildPriceRow("Discount Applied", "-₹${_discount.toStringAsFixed(2)}", Colors.green),
                        _buildPriceRow("Convenience Fee (4%)", "₹${convenience.toStringAsFixed(2)}", textCol),
                        _buildPriceRow("GST (18% on commission)", "₹${gst.toStringAsFixed(2)}", textCol),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Total Amount", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 15)),
                            Text("₹${total.toStringAsFixed(2)}", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: AppColors.pink, fontSize: 16)),
                          ],
                        ),
                        if (!_payOnline) ...[
                          const Divider(height: 24),
                          _buildPriceRow("Payable Now (30%)", "₹${deposit.toStringAsFixed(2)}", Colors.green),
                          _buildPriceRow("Pay at Venue (70%)", "₹${outstanding.toStringAsFixed(2)}", Colors.amber),
                        ]
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),

                  Container(
                    decoration: BoxDecoration(
                      gradient: AppColors.brandGradient,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: _processPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text(
                        _payOnline ? "Proceed to Pay: ₹${total.toStringAsFixed(2)}" : "Proceed with Deposit: ₹${deposit.toStringAsFixed(2)}",
                        style: GoogleFonts.sora(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildPriceRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.sora(fontSize: 13, color: Colors.grey)),
          Text(value, style: GoogleFonts.sora(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Confirmation Screen & E-Ticket
// -------------------------------------------------------------
class ConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> booking;
  const ConfirmationScreen({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: context.bgCol,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Large animated-like success icon
              Center(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green.withOpacity(0.3), width: 2),
                  ),
                  child: const Icon(Icons.check_circle_outline_rounded, size: 54, color: Colors.green),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                "Booking Confirmed!",
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(fontSize: 26, fontWeight: FontWeight.bold, color: textCol),
              ),
              const SizedBox(height: 8),
              Text(
                "Your slot is locked and confirmed.",
                textAlign: TextAlign.center,
                style: GoogleFonts.sora(color: subtextCol, fontSize: 14),
              ),
              const SizedBox(height: 32),

              // Glass Ticket Card
              GlassContainer(
                radius: 24,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      booking['eticket_code'] ?? 'APV-2026-XXXXXX',
                      style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1, color: textCol),
                    ),
                    const SizedBox(height: 20),
                    // QR Code
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: QrImageView(
                        data: booking['eticket_code'] ?? '',
                        version: QrVersions.auto,
                        size: 160.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Show this QR at the venue for check-in",
                      style: GoogleFonts.sora(color: Colors.grey, fontSize: 12),
                    ),
                    const Divider(height: 36),
                    _buildTicketRow("Venue", booking['venue']?['name'] ?? 'Sports Turf', textCol, subtextCol),
                    _buildTicketRow("Sport", booking['venue']?['sport_type'] ?? 'Football', textCol, subtextCol),
                    _buildTicketRow("Date & Time", "${booking['slot']?['start_time']} - ${booking['slot']?['end_time']}", textCol, subtextCol),
                    _buildTicketRow("Status", "CONFIRMED", Colors.green, subtextCol),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Online Paid", style: GoogleFonts.sora(color: subtextCol, fontSize: 13)),
                        Text("₹${booking['online_amount']}", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                      ],
                    ),
                    if (double.parse((booking['venue_amount'] ?? 0).toString()) > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Pay at Venue", style: GoogleFonts.sora(color: subtextCol, fontSize: 13)),
                          Text("₹${booking['venue_amount']}", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 15)),
                        ],
                      ),
                    ]
                  ],
                ),
              ),
              const SizedBox(height: 40),

              // Actions
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ElevatedButton(
                  onPressed: () {
                    // Navigate back to the home dashboard (first screen)
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    "Back to Home",
                    style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketRow(String label, String value, Color valueCol, Color labelCol) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.sora(color: labelCol, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: GoogleFonts.sora(color: valueCol, fontSize: 13, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}


// -------------------------------------------------------------
// Bookings Tab
// -------------------------------------------------------------
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  void _loadBookings() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getBookings();
    if (mounted) {
      setState(() {
        _bookings = res['data'] ?? [];
        _isLoading = false;
      });
    }
  }

  void _cancel(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Cancel Booking", style: GoogleFonts.sora(fontWeight: FontWeight.bold)),
        content: Text("Are you sure you want to cancel this booking? This will release your slot.", style: GoogleFonts.sora()),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text("No", style: GoogleFonts.sora())),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text("Yes, Cancel", style: GoogleFonts.sora(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await ApiService.cancelBooking(bookingId);
      _loadBookings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: context.bgCol,
      appBar: AppBar(
        title: Text("My Bookings", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : _bookings.isEmpty
              ? Center(child: Text("You have no booking records yet.", style: GoogleFonts.sora(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _bookings.length,
                  itemBuilder: (context, index) {
                    final booking = _bookings[index];
                    final isCancelled = booking['status'] == "CANCELLED";

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    booking['venue']?['name'] ?? 'Sports Turf',
                                    style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCancelled ? Colors.red.withOpacity(0.15) : AppColors.pink.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    booking['status'] ?? 'PENDING',
                                    style: GoogleFonts.sora(
                                      color: isCancelled ? Colors.redAccent : AppColors.pink,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(Icons.access_time_rounded, size: 14, color: AppColors.pink),
                                const SizedBox(width: 6),
                                Text(
                                  "Slot: ${booking['slot']?['start_time']} - ${booking['slot']?['end_time']}",
                                  style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.qr_code_rounded, size: 14, color: AppColors.pink),
                                const SizedBox(width: 6),
                                Text(
                                  "Code: ${booking['eticket_code']}",
                                  style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Paid: ₹${booking['online_amount']}",
                                  style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 14),
                                ),
                                if (!isCancelled) ...[
                                  Row(
                                    children: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (context) => ConfirmationScreen(booking: booking),
                                            ),
                                          );
                                        },
                                        child: Text("View Ticket", style: GoogleFonts.sora(color: AppColors.pink, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () => _cancel(booking['booking_id']),
                                        child: Text("Cancel", style: GoogleFonts.sora(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                                      ),
                                    ],
                                  )
                                ]
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// -------------------------------------------------------------
// Tournaments Tab
// -------------------------------------------------------------
class TournamentsTab extends StatefulWidget {
  const TournamentsTab({super.key});

  @override
  State<TournamentsTab> createState() => _TournamentsTabState();
}

class _TournamentsTabState extends State<TournamentsTab> {
  List<dynamic> _tournaments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTournaments();
  }

  void _loadTournaments() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getTournaments();
    setState(() {
      _tournaments = res['data'] ?? [];
      _isLoading = false;
    });
  }

  void _register(String tournamentId) async {
    final teamController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Register for Tournament"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Enter your team name to complete registration:"),
            const SizedBox(height: 12),
            TextField(
              controller: teamController,
              decoration: const InputDecoration(hintText: "Team Name", border: OutlineInputBorder()),
            )
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            child: const Text("Register", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && teamController.text.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      await ApiService.registerTournament(tournamentId, teamController.text.trim());
      _loadTournaments();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Active Tournaments")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _tournaments.isEmpty
              ? const Center(child: Text("No upcoming tournaments hosted right now."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tournaments.length,
                  itemBuilder: (context, index) {
                    final item = _tournaments[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text("Sport: ${item['sport_type']}", style: const TextStyle(color: Colors.grey)),
                            Text("Fee: ₹${item['registration_fee']}", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Max Teams: ${item['max_participants']}"),
                                ElevatedButton(
                                  onPressed: () => _register(item['tournament_id']),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                  child: const Text("Join Now", style: TextStyle(color: Colors.white)),
                                )
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// -------------------------------------------------------------
// Coupons Tab
// -------------------------------------------------------------
class CouponsTab extends StatefulWidget {
  const CouponsTab({super.key});

  @override
  State<CouponsTab> createState() => _CouponsTabState();
}

class _CouponsTabState extends State<CouponsTab> {
  List<dynamic> _coupons = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  void _loadCoupons() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getCoupons();
    if (mounted) {
      setState(() {
        _coupons = res['data'] ?? [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: context.bgCol,
      appBar: AppBar(
        title: Text("My Coupons", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : _coupons.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.pink.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.confirmation_num_outlined, size: 48, color: AppColors.pink),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          "No coupons available",
                          style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Check back later for exclusive deals & discounts",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.sora(fontSize: 13, color: subtextCol),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  itemCount: _coupons.length,
                  itemBuilder: (context, index) {
                    final item = _coupons[index];
                    final code = item['code'] ?? 'SUMMER20';
                    final discount = "${item['discount_value'] ?? '20'}%";

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: GlassContainer(
                        radius: 20,
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Icon Indicator
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: AppColors.pink.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.percent_rounded, color: AppColors.pink, size: 22),
                            ),
                            const SizedBox(width: 16),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "$discount OFF",
                                        style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.pink),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.pink.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          "ACTIVE",
                                          style: GoogleFonts.sora(color: AppColors.pink, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    code,
                                    style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: textCol),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Save $discount on your next booking",
                                    style: GoogleFonts.sora(fontSize: 12, color: subtextCol),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Valid until 30 July 2026",
                                    style: GoogleFonts.sora(fontSize: 11, color: Colors.grey),
                                  ),
                                  const SizedBox(height: 16),
                                  // Copy button
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: code));
                                      AppToast.show(context, "Coupon code copied: $code");
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.pink),
                                    label: Text(
                                      "Copy Code",
                                      style: GoogleFonts.sora(fontSize: 12, color: AppColors.pink, fontWeight: FontWeight.bold),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: AppColors.pink, width: 0.8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    ),
                                  )
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// -------------------------------------------------------------
// Profile Tab
// -------------------------------------------------------------
class ProfileTab extends StatefulWidget {
  final VoidCallback toggleTheme;
  const ProfileTab({super.key, required this.toggleTheme});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  Map<String, dynamic> _profile = {};
  bool _isLoading = true;

  // Notification toggles state
  bool _notifBooking = true;
  bool _notifOffers = true;
  bool _notifEvents = false;
  bool _notifTournaments = true;
  bool _notifReminders = true;
  bool _notifEmails = false;

  // Selected sports state
  final Set<String> _selectedSports = {"Football", "Badminton"};

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getProfile();
    if (mounted) {
      setState(() {
        _profile = res['data'] ?? {};
        _isLoading = false;
      });
    }
  }

  void _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => SplashScreen(toggleTheme: widget.toggleTheme)),
      (route) => false,
    );
  }

  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Account"),
        content: const Text("Are you sure you want to permanently delete your account? This action cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              AppToast.show(context, "Account deletion initiated.");
              _logout();
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.card : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final borderCol = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);

    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bgCol,
        body: const Center(child: CircularProgressIndicator(color: AppColors.pink)),
      );
    }

    final pId = _profile['user_id'] ?? 'PID-12847-XYZ';

    return Scaffold(
      backgroundColor: context.bgCol,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Profile Header (Compact Premium Hero Section)
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(24),
                  bottomRight: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 36,
                    backgroundColor: Colors.white24,
                    child: CircleAvatar(
                      radius: 33,
                      backgroundColor: Colors.white,
                      child: Icon(Icons.person, size: 38, color: AppColors.pink),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _profile['name'] ?? 'Athlete User',
                    style: GoogleFonts.sora(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "@athlete_user",
                    style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "Player ID: ${pId.substring(0, 8)}...",
                        style: GoogleFonts.sora(fontSize: 14, color: Colors.white70),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: pId));
                          AppToast.show(context, "Player ID copied to clipboard!");
                        },
                        child: const Icon(Icons.copy, size: 14, color: Colors.white70),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on, size: 14, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text("Ahmedabad, Gujarat", style: GoogleFonts.sora(fontSize: 15, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("Member since Jan 2025", style: GoogleFonts.sora(fontSize: 13, color: Colors.white54)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "⭐ Level 5 Player",
                          style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {
                          AppToast.show(context, "Edit profile screen coming soon!");
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.15),
                          elevation: 0,
                          fixedSize: const Size(130, 36),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text("Edit Profile", style: GoogleFonts.sora(color: Colors.white, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. Sports Preferences
                  _buildSectionHeader(textCol, "Sports Preferences ⭐"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _buildSportChip("⚽ Football"),
                          _buildSportChip("🏏 Cricket"),
                          _buildSportChip("🏸 Badminton"),
                          _buildSportChip("🎾 Tennis"),
                          _buildSportChip("🏀 Basketball"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3. Player Statistics
                  _buildSectionHeader(textCol, "Player Statistics"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildStatRow(textCol, subtextCol, "Bookings Placed", "26"),
                          const Divider(),
                          _buildStatRow(textCol, subtextCol, "Matches Played", "14"),
                          const Divider(),
                          _buildStatRow(textCol, subtextCol, "Events Joined", "8"),
                          const Divider(),
                          _buildStatRow(textCol, subtextCol, "Favorite Sport", "Football"),
                          const Divider(),
                          _buildStatRow(textCol, subtextCol, "Money Saved", "₹3,450"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 4. Achievements & Rewards
                  _buildSectionHeader(textCol, "Achievements & Rewards"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildAchievementRow(textCol, subtextCol, "🏆 First Booking", "Earned on day 1"),
                          const Divider(),
                          _buildAchievementRow(textCol, subtextCol, "🥈 Played 10 Matches", "Active player"),
                          const Divider(),
                          _buildAchievementRow(textCol, subtextCol, "🥇 Weekend Warrior", "Saturday morning specialist"),
                          const Divider(),
                          _buildAchievementRow(textCol, subtextCol, "🔥 Booked 5 Weeks in Row", "High consistency streak"),
                          const Divider(),
                          _buildAchievementRow(textCol, subtextCol, "⭐ VIP Player", "Exclusive rewards activated"),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. Wallet
                  _buildSectionHeader(textCol, "Wallet"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildWalletStatCol(textCol, subtextCol, "₹350", "Wallet Balance"),
                              _buildWalletStatCol(textCol, subtextCol, "480", "Reward Points"),
                              _buildWalletStatCol(textCol, subtextCol, "₹200", "Referral Earnings"),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => AppToast.show(context, "Wallet deposits coming soon!"),
                                  style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  child: Text("Add Money", style: GoogleFonts.sora(color: AppColors.pink)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () => AppToast.show(context, "No transactions to show."),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.pink,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text("History", style: GoogleFonts.sora(color: Colors.white)),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 6. Coupons
                  _buildSectionHeader(textCol, "Coupons"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildCouponRow(textCol, subtextCol, "PLAY20", "Get 20% off up to ₹100"),
                          _buildCouponRow(textCol, subtextCol, "WELCOME50", "Flat ₹50 off on first turf"),
                          const Divider(),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text("Refer & Earn", style: GoogleFonts.sora(color: textCol, fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text("Get ₹100 for every friend who books", style: GoogleFonts.sora(color: subtextCol, fontSize: 12)),
                            trailing: const Icon(Icons.share, color: AppColors.pink),
                            onTap: () => AppToast.show(context, "Referral code: ATHLETE100"),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 7. Saved Venues
                  _buildSectionHeader(textCol, "Saved Venues ❤️"),
                  SizedBox(
                    height: 100,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _buildSavedVenueCard(cardBg, textCol, subtextCol, borderCol, "Kickoff Arena", "⚽ Football"),
                        _buildSavedVenueCard(cardBg, textCol, subtextCol, borderCol, "Elite Turf", "🏸 Badminton"),
                        _buildSavedVenueCard(cardBg, textCol, subtextCol, borderCol, "Cricket World", "🏏 Cricket"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 8. Booking History
                  _buildSectionHeader(textCol, "Booking History"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.history, color: AppColors.pink),
                          title: Text("Past Bookings", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "No past bookings."),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.receipt_long, color: AppColors.pink),
                          title: Text("Invoices & Receipts", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "No invoices available to download."),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 9. Notification Settings
                  _buildSectionHeader(textCol, "Notification Settings"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Column(
                      children: [
                        _buildSwitchRow("Booking Updates", _notifBooking, (val) => setState(() => _notifBooking = val)),
                        _buildSwitchRow("Offers & Promo Alerts", _notifOffers, (val) => setState(() => _notifOffers = val)),
                        _buildSwitchRow("Local Events & Matches", _notifEvents, (val) => setState(() => _notifEvents = val)),
                        _buildSwitchRow("Tournament Announcements", _notifTournaments, (val) => setState(() => _notifTournaments = val)),
                        _buildSwitchRow("Reminder Notifications", _notifReminders, (val) => setState(() => _notifReminders = val)),
                        _buildSwitchRow("Email Updates", _notifEmails, (val) => setState(() => _notifEmails = val)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 10. Privacy & Security
                  _buildSectionHeader(textCol, "Privacy & Security"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Column(
                      children: [
                        ListTile(
                          title: Text("Change Password", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "Change password modal triggered."),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: Text("Manage Connected Devices", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "1 connected device (Active)"),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: Text("Login Activity logs", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "Last login Ahmedabad, India"),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 11. App Settings
                  _buildSectionHeader(textCol, "App Settings"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.dark_mode, color: AppColors.pink),
                          title: Text("Dark Theme Mode", style: TextStyle(color: textCol)),
                          trailing: Switch(
                            value: isDark,
                            activeColor: AppColors.pink,
                            onChanged: (_) => widget.toggleTheme(),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.language, color: AppColors.pink),
                          title: Text("App Language", style: TextStyle(color: textCol)),
                          trailing: Text("English", style: TextStyle(color: subtextCol)),
                          onTap: () => AppToast.show(context, "English, Hindi, Gujarati supported."),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.monetization_on, color: AppColors.pink),
                          title: Text("Display Currency", style: TextStyle(color: textCol)),
                          trailing: Text("INR (₹)", style: TextStyle(color: subtextCol)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Location Settings
                  _buildSectionHeader(textCol, "Location Settings"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.location_on_rounded, color: AppColors.pink),
                          title: Text("Current Location Status", style: TextStyle(color: textCol)),
                          subtitle: const Text("Allowed", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          title: Text("Manage Location Permission", style: TextStyle(color: textCol, fontWeight: FontWeight.bold)),
                          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.pink),
                          onTap: () {
                            AppToast.show(context, "Opening App Settings...");
                            Geolocator.openAppSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 12. Support & Help
                  _buildSectionHeader(textCol, "Support & Help"),
                  Card(
                    color: cardBg,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: borderCol)),
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.chat_bubble_outline, color: AppColors.pink),
                          title: Text("Live Support Chat", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => const _AdminChatWidget(venueName: "General Support"),
                            );
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.phone_iphone, color: AppColors.pink),
                          title: Text("WhatsApp Support", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "Opening WhatsApp chat support..."),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.phone, color: AppColors.pink),
                          title: Text("Call Support", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "Dialing +91 99999 88888..."),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.bug_report, color: AppColors.pink),
                          title: Text("Report a Problem", style: TextStyle(color: textCol)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => AppToast.show(context, "Problem report logs sent!"),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 13. Logout & Delete Account
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _deleteAccount,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text("Delete Account", style: GoogleFonts.sora(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _logout,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text("Logout", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 60), // Navigation spacing
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(Color color, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildSportChip(String sport) {
    final name = sport.substring(2).trim();
    final isSelected = _selectedSports.contains(name);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedSports.remove(name);
          } else {
            _selectedSports.add(name);
          }
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.brandGradient : null,
          color: isSelected ? null : (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? Colors.transparent : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08)),
          ),
          boxShadow: isSelected
              ? [BoxShadow(color: AppColors.pink.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 3))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              const Icon(Icons.check_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 6),
            ],
            Text(
              sport,
              style: GoogleFonts.sora(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildStatRow(Color textCol, Color subtextCol, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.sora(color: subtextCol, fontSize: 13)),
          Text(value, style: GoogleFonts.sora(color: textCol, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildAchievementRow(Color textCol, Color subtextCol, String label, String desc) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: GoogleFonts.sora(color: textCol, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(desc, style: GoogleFonts.sora(color: subtextCol, fontSize: 12)),
      trailing: const Icon(Icons.verified, color: AppColors.pink, size: 20),
    );
  }

  Widget _buildWalletStatCol(Color textCol, Color subtextCol, String val, String label) {
    return Column(
      children: [
        Text(val, style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.pink)),
        const SizedBox(height: 4),
        Text(label, style: GoogleFonts.sora(fontSize: 11, color: subtextCol)),
      ],
    );
  }

  Widget _buildCouponRow(Color textCol, Color subtextCol, String code, String benefit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.pink.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.pink.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(code, style: GoogleFonts.sora(color: AppColors.pink, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(benefit, style: GoogleFonts.sora(color: textCol, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSavedVenueCard(Color cardBg, Color textCol, Color subtextCol, Color borderCol, String name, String sport) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        border: Border.all(color: borderCol),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(name, style: GoogleFonts.sora(color: textCol, fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(sport, style: GoogleFonts.sora(color: subtextCol, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String label, bool value, ValueChanged<bool> onChange) {
    return SwitchListTile(
      value: value,
      onChanged: onChange,
      activeColor: AppColors.pink,
      title: Text(label, style: GoogleFonts.sora(fontSize: 13)),
    );
  }
}


// -------------------------------------------------------------
// Math & Text Utilities
// -------------------------------------------------------------
class MathUtils {
  static String randomString(int len) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(len, (i) => chars[DateTime.now().microsecondsSinceEpoch % chars.length]).join();
  }
}

class GlassContainer extends StatelessWidget {
  final Widget child;
  final double radius;
  final BorderRadiusGeometry? borderRadius;
  final double blur;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final AlignmentGeometry? alignment;
  final BoxBorder? border;
  final Gradient? gradient;
  final bool useBlur;

  const GlassContainer({
    super.key,
    required this.child,
    this.radius = 24,
    this.borderRadius,
    this.blur = 30,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.alignment,
    this.border,
    this.gradient,
    this.useBlur = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(radius);
    final effectiveBlur = isDark ? 28.0 : 18.0;

    final effectiveBorder = border ?? Border.all(
      color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.65),
      width: 1.0,
    );

    final effectiveGradient = gradient ?? LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              Colors.white.withOpacity(0.08),
              Colors.white.withOpacity(0.03),
            ]
          : [
              Colors.white.withOpacity(0.70),
              Colors.white.withOpacity(0.45),
            ],
    );

    final effectiveShadows = isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
            BoxShadow(
              color: const Color(0xFF8B5CF6).withOpacity(0.04),
              blurRadius: 40,
              offset: const Offset(0, 15),
            ),
          ]
        : [
            const BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              spreadRadius: 0,
              offset: Offset(0, 8),
            ),
          ];

    return Container(
      margin: margin,
      width: width,
      height: height,
      alignment: alignment,
      decoration: BoxDecoration(
        borderRadius: effectiveBorderRadius,
        boxShadow: effectiveShadows,
      ),
      child: ClipRRect(
        borderRadius: effectiveBorderRadius,
        child: useBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
                child: Container(
                  padding: padding,
                  decoration: BoxDecoration(
                    borderRadius: effectiveBorderRadius,
                    border: effectiveBorder,
                    gradient: effectiveGradient,
                  ),
                  child: child,
                ),
              )
            : Container(
                padding: padding,
                decoration: BoxDecoration(
                  borderRadius: effectiveBorderRadius,
                  border: effectiveBorder,
                  gradient: effectiveGradient,
                ),
                child: child,
              ),
      ),
    );
  }
}

class NotificationBottomSheet extends StatefulWidget {
  const NotificationBottomSheet({super.key});

  @override
  State<NotificationBottomSheet> createState() => _NotificationBottomSheetState();
}

class _NotificationBottomSheetState extends State<NotificationBottomSheet> {
  List<dynamic> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  void _loadNotifications() async {
    try {
      final res = await ApiService.getNotifications();
      if (res['success'] == true) {
        setState(() {
          _notifications = res['data'] ?? [];
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _markAsRead(String notifId) async {
    try {
      await ApiService.readNotification(notifId);
      _loadNotifications();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surface : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF1A1A1A);

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Notifications",
                style: GoogleFonts.sora(fontSize: 20, fontWeight: FontWeight.bold, color: text),
              ),
              IconButton(
                icon: Icon(Icons.close, color: text),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppColors.pink))
                : _notifications.isEmpty
                    ? Center(
                        child: Text(
                          "No notifications yet",
                          style: GoogleFonts.sora(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notif = _notifications[index];
                          final isRead = notif['is_read'] == true;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              notif['title'] ?? 'Alert',
                              style: GoogleFonts.sora(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                color: text,
                              ),
                            ),
                            subtitle: Text(
                              notif['body'] ?? '',
                              style: GoogleFonts.sora(color: isRead ? Colors.grey : text.withOpacity(0.8)),
                            ),
                            trailing: !isRead
                                ? TextButton(
                                    onPressed: () => _markAsRead(notif['notif_id']),
                                    child: const Text("Read"),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _AdminChatWidget extends StatefulWidget {
  final String venueName;
  const _AdminChatWidget({required this.venueName});

  @override
  State<_AdminChatWidget> createState() => _AdminChatWidgetState();
}

class _AdminChatWidgetState extends State<_AdminChatWidget> {
  final List<Map<String, dynamic>> _messages = [];
  final _msgController = TextEditingController();
  final _scrollController = ScrollController();
  String? _myUserId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initChat();
    WebSocketSyncManager.subscribe('chat_message', _onNewMessage);
  }

  @override
  void dispose() {
    WebSocketSyncManager.unsubscribe('chat_message', _onNewMessage);
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNewMessage() {
    _loadChatHistory();
  }

  void _initChat() async {
    try {
      final res = await ApiService.getProfile();
      if (res['success'] == true) {
        _myUserId = res['data']?['user_id'];
      }
    } catch (_) {}
    _loadChatHistory();
  }

  void _loadChatHistory() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiService.activeUrl}/chat/history'),
        headers: {
          'Authorization': 'Bearer ${await ApiService.getToken()}',
          'Content-Type': 'application/json',
        },
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final list = data['data'] as List;
        if (mounted) {
          setState(() {
            _messages.clear();
            for (var item in list) {
              _messages.add({
                'sender': item['sender_role'],
                'text': item['text'],
                'time': 'Just now',
              });
            }
            _isLoading = false;
          });
          _scrollToBottom();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.card : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final borderCol = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : const Color(0xFFF5F7FB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(bottom: BorderSide(color: borderCol)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.pink.withOpacity(0.1),
                  child: const Icon(Icons.support_agent, color: AppColors.pink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Admin Support",
                        style: TextStyle(color: textCol, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        "Replies instantly • ${widget.venueName}",
                        style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: isDark ? Colors.white70 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
          ),
          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isAdmin = msg['sender'] == 'admin';
                      return Align(
                        alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: isAdmin ? cardBg : AppColors.pink,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(16),
                              topRight: const Radius.circular(16),
                              bottomLeft: isAdmin ? Radius.zero : const Radius.circular(16),
                              bottomRight: isAdmin ? const Radius.circular(16) : Radius.zero,
                            ),
                            border: isAdmin ? Border.all(color: borderCol) : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg['text'],
                                style: TextStyle(color: isAdmin ? textCol : Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // Input box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(top: BorderSide(color: borderCol)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surface : const Color(0xFFF5F7FB),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderCol),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _msgController,
                      style: TextStyle(color: textCol),
                      decoration: InputDecoration(
                        hintText: "Type your message...",
                        hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.grey),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: AppColors.pink,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: () {
                      final text = _msgController.text.trim();
                      if (text.isEmpty || _myUserId == null) return;
                      _msgController.clear();
                      
                      WebSocketSyncManager.send('chat_message', {
                        'senderId': _myUserId,
                        'senderRole': 'user',
                        'recipientId': '00000000-0000-0000-0000-000000000000',
                        'text': text
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// View All Venues Screen
// -------------------------------------------------------------
class ViewAllVenuesScreen extends StatelessWidget {
  final List<dynamic> venues;
  const ViewAllVenuesScreen({super.key, required this.venues});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final borderCol = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);

    return Scaffold(
      backgroundColor: context.bgCol,
      appBar: AppBar(
        title: Text("All Venues", style: GoogleFonts.sora(color: textCol, fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textCol),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: venues.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.sports_soccer_rounded, size: 72, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text("No venues listed", style: GoogleFonts.sora(fontSize: 16, color: textCol, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: venues.length,
              itemBuilder: (context, index) {
                final venue = venues[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  child: GlassContainer(
                    radius: 24,
                    padding: const EdgeInsets.all(0),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute(
                            builder: (context) => VenueDetailScreen(venueId: venue['venue_id']),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Container(
                                height: 160,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                                ),
                                child: const Center(child: Icon(Icons.sports_soccer_rounded, size: 64, color: AppColors.pink)),
                              ),
                              Positioned(
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.65),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        venue['avg_rating']?.toString() ?? '4.5',
                                        style: GoogleFonts.sora(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        venue['name'] ?? '',
                                        style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                                      ),
                                      Row(
                                        children: [
                                          const Icon(Icons.location_on_rounded, color: Colors.grey, size: 13),
                                          const SizedBox(width: 4),
                                          Text(
                                            "${venue['address']?.toString().split(',').first ?? 'Ahmedabad'} • ${venue['distance']?.toString() ?? '0.8'} km",
                                            style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        "₹${venue['base_price']}/hr Starting from",
                                        style: GoogleFonts.sora(color: AppColors.pink, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: AppColors.brandGradient,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.of(context, rootNavigator: true).push(
                                        MaterialPageRoute(
                                          builder: (context) => VenueDetailScreen(venueId: venue['venue_id']),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    ),
                                    child: Text("Book Now", style: GoogleFonts.sora(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                )
                              ],
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// -------------------------------------------------------------
// Filters Bottom Sheet
// -------------------------------------------------------------
class FiltersBottomSheet extends StatefulWidget {
  final Function(double maxPrice, double minRating, String sport) onApply;
  final double currentMaxPrice;
  final double currentMinRating;
  final String currentSport;

  const FiltersBottomSheet({
    super.key,
    required this.onApply,
    required this.currentMaxPrice,
    required this.currentMinRating,
    required this.currentSport,
  });

  @override
  State<FiltersBottomSheet> createState() => _FiltersBottomSheetState();
}

class _FiltersBottomSheetState extends State<FiltersBottomSheet> {
  late double _maxPrice;
  late double _minRating;
  late String _sport;

  @override
  void initState() {
    super.initState();
    _maxPrice = widget.currentMaxPrice;
    _minRating = widget.currentMinRating;
    _sport = widget.currentSport;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final cardBg = isDark ? AppColors.card : Colors.white;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surface : const Color(0xFFF5F7FB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Filters", style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const Divider(),
          const SizedBox(height: 16),
          Text("Max Price (per hour): ₹${_maxPrice.toInt()}", style: GoogleFonts.sora(fontSize: 14, color: textCol, fontWeight: FontWeight.bold)),
          Slider(
            value: _maxPrice,
            min: 500,
            max: 5000,
            divisions: 9,
            activeColor: AppColors.pink,
            onChanged: (val) => setState(() => _maxPrice = val),
          ),
          const SizedBox(height: 16),
          Text("Minimum Rating: ${_minRating.toStringAsFixed(1)} ★", style: GoogleFonts.sora(fontSize: 14, color: textCol, fontWeight: FontWeight.bold)),
          Slider(
            value: _minRating,
            min: 0.0,
            max: 5.0,
            divisions: 10,
            activeColor: AppColors.purple,
            onChanged: (val) => setState(() => _minRating = val),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _maxPrice = 5000;
                      _minRating = 0.0;
                    });
                  },
                  child: Text("Reset", style: GoogleFonts.sora(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppColors.brandGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(_maxPrice, _minRating, _sport);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    child: Text("Apply Filters", style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}


