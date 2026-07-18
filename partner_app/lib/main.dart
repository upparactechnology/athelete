import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'websocket_sync.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'widgets/glass_container.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:webview_flutter/webview_flutter.dart';

// -------------------------------------------------------------
// Brand Theme & Colors
// -------------------------------------------------------------
class AppColors {
  static const background = Color(0xff090B10);
  static const surface = Color(0xff131722);
  static const card = Color(0xff181D2A);
  static const pink = Color(0xffFF5C93);
  static const purple = Color(0xff8B5CF6);
  static const success = Color(0xff3DDC84);
  static const orange = Color(0xffFF8A3D);
  static const text = Colors.white;
  static const secondary = Color(0xff9AA4B2);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xffFF5C93),
      Color(0xff8B5CF6),
    ],
  );
}

String formatLocalDate(dynamic dateVal) {
  if (dateVal == null) return "";
  try {
    final parsed = DateTime.parse(dateVal.toString()).toLocal();
    return "${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}";
  } catch (_) {
    final str = dateVal.toString();
    if (str.length >= 10) {
      return str.substring(0, 10);
    }
    return str;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.checkServerUrl();
  runApp(const PartnerPOVApp());
}

class PartnerPOVApp extends StatefulWidget {
  const PartnerPOVApp({super.key});

  @override
  State<PartnerPOVApp> createState() => _PartnerPOVAppState();
}

class _PartnerPOVAppState extends State<PartnerPOVApp> {
  ThemeMode _themeMode = ThemeMode.dark;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    final lightTextTheme = GoogleFonts.soraTextTheme(ThemeData.light().textTheme);
    final darkTextTheme = GoogleFonts.soraTextTheme(ThemeData.dark().textTheme);

    return MaterialApp(
      title: "Partner's POV",
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
        primaryColor: AppColors.pink,
        colorScheme: const ColorScheme.light(
          primary: AppColors.pink,
          secondary: AppColors.purple,
          surface: Colors.white,
          onSurface: const Color(0xFF1A1A1A),
        ),
        textTheme: lightTextTheme,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        primaryColor: AppColors.pink,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.pink,
          secondary: AppColors.purple,
          surface: AppColors.surface,
          onSurface: Colors.white,
        ),
        textTheme: darkTextTheme,
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
      try {
        final profileRes = await ApiService.getProfile();
        if (profileRes['success'] == true) {
          final profile = profileRes['data'] ?? {};
          final phoneNumber = profile['phone_number'] ?? '';
          if (phoneNumber.contains('@')) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => PhoneCollectionScreen(toggleTheme: widget.toggleTheme),
              ),
            );
            return;
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
            ),
          );
          return;
        } else {
          await ApiService.clearToken();
        }
      } catch (e) {
        debugPrint("Error fetching profile: $e");
        // Safe fallback when server is unreachable or offline but we have a token
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
          ),
        );
        return;
      }
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LoginScreen(toggleTheme: widget.toggleTheme),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', width: 96, height: 96),
            const SizedBox(height: 20),
            const Text(
              "Partner's POV",
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            const Text("Manage Your Turf Facilities", style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: AppColors.pink),
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
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpRequested = false;
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _passwordVisible = false;
  bool _isGoogleSignInInitialized = false;
  String? _receivedOtp;
  int _resendCountdown = 0;
  Timer? _countdownTimer;

  void _startResendTimer() {
    setState(() => _resendCountdown = 30);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCountdown == 0) {
        timer.cancel();
      } else {
        if (mounted) {
          setState(() => _resendCountdown--);
        }
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _requestOtp() async {
    FocusScope.of(context).unfocus();
    final email = _phoneController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }
    if (password.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters long')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _receivedOtp = null;
    });
    try {
      final response = await ApiService.requestOtp(
        email, 
        password: password, 
        isSignUp: _isSignUp
      );
      if (response['success'] == true) {
        setState(() {
          _otpRequested = true;
        });
        _startResendTimer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['data']?['message'] ?? response['message'] ?? 'OTP Sent!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['message'] ?? 'Failed to request OTP')),
        );
      }
    } catch (e) {
      debugPrint("Error requesting OTP: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _verifyOtp() async {
    FocusScope.of(context).unfocus();
    if (_otpController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.verifyOtp(_phoneController.text.trim(), _otpController.text.trim());
      if (response['success'] == true) {
        if (!mounted) return;
        final profileRes = await ApiService.getProfile();
        final profile = profileRes['data'] ?? {};
        final phoneNumber = profile['phone_number'] ?? '';
        
        if (phoneNumber.contains('@')) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => PhoneCollectionScreen(toggleTheme: widget.toggleTheme),
            ),
          );
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(response['error']?['message'] ?? response['message'] ?? 'Verification failed')),
        );
      }
    } catch (e) {
      debugPrint("Error verifying OTP: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    try {
      if (!_isGoogleSignInInitialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: '239542933796-07n2hl6ehh9sioac43ljhetai1a3jhgu.apps.googleusercontent.com',
        );
        _isGoogleSignInInitialized = true;
      }
      
      final GoogleSignInAccount account = await GoogleSignIn.instance.authenticate();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Center(
            child: Card(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.pink),
                    const SizedBox(height: 16),
                    Text(
                      "Connecting with Athlete POV...",
                      style: TextStyle(
                        fontSize: 14, 
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      );

      final response = await ApiService.googleLogin(
        account.email, 
        account.displayName ?? 'Google User'
      );
      
      if (mounted) {
        Navigator.pop(context);
      }

      if (response['success'] == true) {
        if (!mounted) return;
        final profileRes = await ApiService.getProfile();
        final profile = profileRes['data'] ?? {};
        final phoneNumber = profile['phone_number'] ?? '';
        
        if (phoneNumber.contains('@')) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => PhoneCollectionScreen(toggleTheme: widget.toggleTheme),
            ),
          );
          return;
        }

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response['message'] ?? 'Google Sign-In failed')),
          );
        }
      }
    } catch (e) {
      debugPrint("GOOGLE SIGN IN EXCEPTION: $e");
      if (mounted) {
        String msg = 'Google Sign-In error: $e';
        if (e is GoogleSignInException) {
          msg = 'Google Sign-In Exception (${e.code}): ${e.description ?? "No message"}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 72,
                    height: 72,
                    errorBuilder: (context, error, stackTrace) => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.pink.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.sports_soccer_rounded, size: 48, color: AppColors.pink),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _otpRequested 
                      ? "Verify OTP" 
                      : (_isSignUp ? "Create Partner Account" : "Partner Portal Login"),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _otpRequested 
                      ? "Enter the 6-digit code sent to you" 
                      : (_isSignUp 
                          ? "Register with email and password, then verify OTP" 
                          : "Enter your email address and password to log in"),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 32),
                if (!_otpRequested) ...[
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.mail_outline_rounded, color: AppColors.pink),
                      hintText: "Email Address",
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_passwordVisible,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline_rounded, color: AppColors.pink),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _passwordVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                      ),
                      hintText: "Password",
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _requestOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            _isSignUp ? "Sign Up & Verify" : "Sign In", 
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
                          ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _isSignUp = !_isSignUp;
                        _passwordController.clear();
                      }),
                      child: Text(
                        _isSignUp 
                            ? "Already have an account? Sign In" 
                            : "Don't have an account? Sign Up",
                        style: const TextStyle(color: AppColors.pink, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: Colors.white10)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text("OR", style: TextStyle(color: Colors.grey[500], fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      const Expanded(child: Divider(color: Colors.white10)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _handleGoogleSignIn,
                    icon: const Icon(Icons.g_mobiledata_rounded, color: AppColors.pink, size: 24),
                    label: Text(
                      _isSignUp ? "Sign up with Google" : "Continue with Google",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white10),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock, color: AppColors.pink),
                      hintText: "Enter OTP (e.g. 123456)",
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("Verify & Login", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: (_isLoading || _resendCountdown > 0) ? null : _requestOtp,
                      child: Text(
                        _resendCountdown > 0 ? "Resend OTP in ${_resendCountdown}s" : "Resend OTP",
                        style: TextStyle(
                          color: (_isLoading || _resendCountdown > 0) ? Colors.grey : AppColors.pink,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _otpRequested = false),
                      child: const Text("Back to Login", style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.bold)),
                    ),
                  )
                ]
              ],
            ),
          ),
        ),
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

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      HomeTab(toggleTheme: widget.toggleTheme),
      const BookingsTab(),
      const VenuesTab(),
      const PaymentsTab(),
      ProfileTab(toggleTheme: widget.toggleTheme),
    ];

    return Scaffold(
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
                      _buildNavItem(2, Icons.sports_rounded, "Venues"),
                      _buildNavItem(3, Icons.payments_rounded, "Payments"),
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
    final activeColor = const Color(0xFFFF5C93);
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
  const HomeTab({super.key, required this.toggleTheme});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> with WidgetsBindingObserver {
  Map<String, dynamic> _profile = {};
  List<dynamic> _bookings = [];
  List<dynamic> _reviews = [];
  bool _isLoading = true;
  String _currentLocation = "Detecting location...";
  bool _isLocationDialogOpen = false;
  bool _isPermissionDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detectLocation();
      _requestAppPermissions();
    });
    WebSocketSyncManager.subscribe('bookings', _loadData);
  }

  void _requestAppPermissions() async {
    try {
      await [
        Permission.camera,
        Permission.photos,
        Permission.storage,
      ].request();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WebSocketSyncManager.unsubscribe('bookings', _loadData);
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
        setState(() => _currentLocation = "Location disabled");
        _showLocationDisabledDialog();
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _currentLocation = "Permission denied");
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _currentLocation = "Permission denied");
        _showPermissionDeniedForeverDialog();
        return;
      }

      // Try instant last known position first
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
    } catch (e) {
      debugPrint("Geolocator Error: $e");
      setState(() => _currentLocation = "Location Unavailable");
    }
  }

  void _showLocationDisabledDialog() {
    if (_isLocationDialogOpen) return;
    _isLocationDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.location_off, color: AppColors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Location Services Disabled",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          "Location services are turned off on your device. Please enable location or open Settings.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isLocationDialogOpen = false;
              Navigator.pop(context);
            },
            child: const Text("Skip", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              _isLocationDialogOpen = false;
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.pink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Open Settings", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPermissionDeniedForeverDialog() {
    if (_isPermissionDialogOpen) return;
    _isPermissionDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.gpp_maybe, color: AppColors.orange),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Location Permission Denied",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          "Location permission is permanently denied. Please enable location permission in settings to use location features.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _isPermissionDialogOpen = false;
              Navigator.pop(context);
            },
            child: const Text("Skip", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              _isPermissionDialogOpen = false;
              Navigator.pop(context);
              Geolocator.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.pink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Open Settings", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<String> _getAreaName(double lat, double lon) async {
    try {
      final url = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=14');
      final response = await http.get(url, headers: {'User-Agent': 'apov_partner_app'});
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
    return "Bengaluru, KA";
  }



  void _loadData() async {
    setState(() => _isLoading = true);
    try {
      final profileRes = await ApiService.getProfile();
      final bookingsRes = await ApiService.getPartnerBookings();
      final reviewsRes = await ApiService.getPartnerReviews();
      setState(() {
        _profile = profileRes['data'] ?? {};
        _bookings = bookingsRes['data'] ?? [];
        _reviews = reviewsRes['data'] ?? [];
      });
    } catch (e) {
      debugPrint("Error loading dashboard data: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final secondaryTextColor = isDark ? const Color(0xFF9AA4B2) : const Color(0xFF6B7280);

    // Dynamic Calculations
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));
    final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";

    double todayEarnings = 0.0;
    double yesterdayEarnings = 0.0;
    int todayBookingsCount = 0;
    int todayCheckinsCount = 0;
    int todayPendingCount = 0;

    for (var b in _bookings) {
      final slotDate = formatLocalDate(b['slot']?['date']);
      final isConfirmed = b['status'] == "CONFIRMED";
      final isPending = b['status'] == "PENDING";
      final amt = double.tryParse(b['online_amount']?.toString() ?? '0') ?? 0.0;

      if (slotDate == todayStr) {
        todayBookingsCount++;
        if (isConfirmed) {
          todayEarnings += amt;
          todayCheckinsCount++;
        } else if (isPending) {
          todayPendingCount++;
        }
      } else if (slotDate == yesterdayStr) {
        if (isConfirmed) {
          yesterdayEarnings += amt;
        }
      }
    }

    double percentageGrowth = 0.0;
    if (yesterdayEarnings > 0) {
      percentageGrowth = ((todayEarnings - yesterdayEarnings) / yesterdayEarnings) * 100;
    } else if (todayEarnings > 0) {
      percentageGrowth = 100.0;
    }

    double avgRating = 0.0;
    if (_reviews.isNotEmpty) {
      double sum = 0.0;
      for (var r in _reviews) {
        sum += double.tryParse(r['rating']?.toString() ?? '0') ?? 0.0;
      }
      avgRating = sum / _reviews.length;
    }

    return Scaffold(
      body: Stack(
        children: [
          // Background blobs for visual depth (Liquid Glass/VisionOS style)
          Positioned(
            top: -120,
            left: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFFFF5C93).withOpacity(isDark ? 0.18 : 0.08),
                    const Color(0xFFFF5C93).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 120,
            right: -100,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF8B5CF6).withOpacity(isDark ? 0.15 : 0.06),
                    const Color(0xFF8B5CF6).withOpacity(0.0),
                  ],
                ),
              ),
            ),
          ),
          // Main Scroll View
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
              : RefreshIndicator(
                  onRefresh: () async {
                    _loadData();
                    await Future.delayed(const Duration(milliseconds: 600));
                  },
                  color: AppColors.pink,
                  child: SafeArea(
                    bottom: false,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                      // Premium App Bar with rounded designs and Location / Theme actions
                      SliverAppBar(
                        expandedHeight: 70,
                        floating: true,
                        backgroundColor: Colors.transparent,
                        elevation: 0,
                        automaticallyImplyLeading: false,
                        flexibleSpace: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 20, color: AppColors.pink),
                                  const SizedBox(width: 6),
                                  Text(
                                    _currentLocation,
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: Icon(
                                  isDark ? Icons.dark_mode_rounded : Icons.wb_sunny_rounded,
                                  color: isDark ? Colors.white70 : const Color(0xFF4B5563),
                                ),
                                onPressed: widget.toggleTheme,
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.only(left: 20, right: 20, bottom: 190), // Spaced for both buttons
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            // 1. Large Greeting Section
                            Text(
                              "Hello, ${_profile['name'] ?? 'Partner'}! 👋",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.5,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Here's your facility summary today.",
                              style: TextStyle(
                                color: secondaryTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 2. Large Earnings Card (GlassContainer)
                            GlassContainer(
                              radius: 28,
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "TODAY'S EARNINGS",
                                        style: TextStyle(
                                          color: secondaryTextColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      // Green growth badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3DDC84).withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: const Color(0xFF3DDC84).withOpacity(0.2),
                                            width: 1.0,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.arrow_upward_rounded, size: 14, color: Color(0xFF3DDC84)),
                                            const SizedBox(width: 4),
                                            Text(
                                              "${percentageGrowth.abs().toStringAsFixed(1)}%",
                                              style: const TextStyle(
                                                color: Color(0xFF3DDC84),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "₹${todayEarnings.toStringAsFixed(0)}",
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  // Curved Bezier Chart
                                  SizedBox(
                                    height: 70,
                                    child: CustomPaint(
                                      painter: LineChartPainter(theme.brightness == Brightness.dark),
                                      child: Container(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 3. Three Statistics Cards (Apple Health Style)
                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    CupertinoIcons.calendar,
                                    "Bookings",
                                    "$todayBookingsCount",
                                    "${_bookings.length} Total",
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    CupertinoIcons.checkmark_seal,
                                    "Check-ins",
                                    "$todayCheckinsCount",
                                    "Pending: $todayPendingCount",
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildStatCard(
                                    CupertinoIcons.star,
                                    "Reviews",
                                    avgRating > 0 ? avgRating.toStringAsFixed(1) : "0.0",
                                    "${_reviews.length} Reviews",
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),

                            // 4. Today's Bookings Title
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Today's Bookings",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    "View all",
                                    style: TextStyle(
                                      color: AppColors.pink,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 5. Today's Bookings List
                            (() {
                              final todayBookings = _bookings.where((b) {
                                final slotDate = formatLocalDate(b['slot']?['date']);
                                return slotDate == todayStr;
                              }).toList();

                              return todayBookings.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: Center(
                                        child: Text(
                                          "No bookings for today.",
                                          style: TextStyle(color: secondaryTextColor),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: todayBookings.length > 3 ? 3 : todayBookings.length,
                                      itemBuilder: (context, index) {
                                        final b = todayBookings[index];
                                        final isConfirmed = b['status'] == "CONFIRMED";
                                        return GlassContainer(
                                          radius: 20,
                                          margin: const EdgeInsets.only(bottom: 12),
                                          padding: const EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: isConfirmed 
                                                      ? const Color(0xFF3DDC84).withOpacity(0.12)
                                                      : const Color(0xFFFFB03A).withOpacity(0.12),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isConfirmed 
                                                        ? const Color(0xFF3DDC84).withOpacity(0.2)
                                                        : const Color(0xFFFFB03A).withOpacity(0.2),
                                                  ),
                                                ),
                                                child: Icon(
                                                  isConfirmed ? Icons.check_circle_rounded : Icons.pending_rounded,
                                                  color: isConfirmed ? const Color(0xFF3DDC84) : const Color(0xFFFFB03A),
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      b['venue']?['name'] ?? 'Facility',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: textColor,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      "${b['slot']?['start_time'] ?? ''} - ${b['slot']?['end_time'] ?? ''}",
                                                      style: TextStyle(
                                                        color: secondaryTextColor,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Text(
                                                "₹${b['online_amount']}",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: textColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    );
                            })(),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
      ),
          // Floating Scan E-Ticket CTA button (Always visible, sits above Bottom Navigation)
          if (!_isLoading)
            Positioned(
              right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 66,
              child: StatefulBuilder(
                builder: (context, setBtnState) {
                  bool isPressed = false;
                  return Listener(
                    onPointerDown: (_) => setBtnState(() => isPressed = true),
                    onPointerUp: (_) => setBtnState(() => isPressed = false),
                    child: AnimatedScale(
                      scale: isPressed ? 0.95 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF5C93),
                              Color(0xFFFF6FB2),
                              Color(0xFFD946EF),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF5C93).withOpacity(0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ScanTicketScreen()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: const CircleBorder(),
                          ),
                          child: const Icon(CupertinoIcons.qrcode_viewfinder, color: Colors.white, size: 26),
                        ),
                      ),
                    ),
                  );
                }
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(IconData icon, String label, String value, String subtext) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final secondaryTextColor = isDark ? const Color(0xFF9AA4B2) : const Color(0xFF6B7280);

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.pink),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtext,
            style: TextStyle(
              color: secondaryTextColor,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class LineChartPainter extends CustomPainter {
  final bool isDark;
  LineChartPainter(this.isDark);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [
          Color(0xFFFF5C93),
          Color(0xFF8B5CF6),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFFF5C93).withOpacity(0.24),
          const Color(0xFF8B5CF6).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, size.height * 0.85);
    
    // Smooth cubic bezier curves
    path.cubicTo(
      size.width * 0.25, size.height * 0.90,
      size.width * 0.35, size.height * 0.30,
      size.width * 0.50, size.height * 0.40,
    );
    path.cubicTo(
      size.width * 0.65, size.height * 0.50,
      size.width * 0.75, size.height * 0.10,
      size.width, size.height * 0.15,
    );

    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);

    // Draw glowing points at the end
    final pointPaint = Paint()
      ..color = const Color(0xFFFF5C93)
      ..style = PaintingStyle.fill;
    final pointOuterPaint = Paint()
      ..color = const Color(0xFFFF5C93).withOpacity(0.4)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width, size.height * 0.15), 8, pointOuterPaint);
    canvas.drawCircle(Offset(size.width, size.height * 0.15), 4, pointPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -------------------------------------------------------------
// Bookings Tab Screen
// -------------------------------------------------------------
class BookingsTab extends StatefulWidget {
  const BookingsTab({super.key});

  @override
  State<BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<BookingsTab> {
  List<dynamic> _bookings = [];
  bool _isLoading = true;
  String _selectedFilter = "Today"; // All, Today, Upcoming, Completed
  late String _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().toIso8601String().substring(0, 10);
    _loadBookings();
    WebSocketSyncManager.subscribe('bookings', _loadBookings);
  }

  @override
  void dispose() {
    WebSocketSyncManager.unsubscribe('bookings', _loadBookings);
    super.dispose();
  }

  void _loadBookings() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getPartnerBookings();
      setState(() {
        _bookings = res['data'] ?? [];
      });
    } catch (e) {
      debugPrint("Error loading bookings: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<dynamic> _getFilteredBookings() {
    if (_selectedFilter == "Today") {
      return _bookings.where((b) {
        final slotDate = formatLocalDate(b['slot']?['date']);
        return slotDate == _selectedDate;
      }).toList();
    }
    // Filter logic for upcoming and completed
    if (_selectedFilter == "Upcoming") {
      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      return _bookings.where((b) {
        final slotDate = formatLocalDate(b['slot']?['date']);
        return slotDate.compareTo(todayStr) > 0;
      }).toList();
    }
    if (_selectedFilter == "Completed") {
      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      return _bookings.where((b) {
        final slotDate = formatLocalDate(b['slot']?['date']);
        return slotDate.compareTo(todayStr) < 0 || b['status'] == 'CONFIRMED';
      }).toList();
    }
    return _bookings;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _getFilteredBookings();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bookings", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Filter Chips
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: ["All", "Today", "Upcoming", "Completed"].map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedFilter = filter;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            gradient: isSelected ? AppColors.brandGradient : null,
                            color: isSelected ? null : const Color(0xFF1A1E29),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected ? Colors.transparent : Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              filter,
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.grey.shade400,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),

                // Date Picker Slider (If Today filter is selected)
                if (_selectedFilter == "Today") ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      height: 54,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: List.generate(7, (i) {
                          final date = DateTime.now().add(Duration(days: i - 3));
                          final dateStr = date.toIso8601String().substring(0, 10);
                          final isSelected = _selectedDate == dateStr;
                          final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                          final monthStr = months[date.month - 1];

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDate = dateStr;
                              });
                            },
                            child: Container(
                              width: 74,
                              margin: const EdgeInsets.only(right: 12),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.pink : theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    date.day.toString().padLeft(2, '0'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? Colors.white : null,
                                    ),
                                  ),
                                  Text(
                                    monthStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isSelected ? Colors.white70 : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      _loadBookings();
                      await Future.delayed(const Duration(milliseconds: 600));
                    },
                    color: AppColors.pink,
                    child: filtered.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: const Center(
                                  child: Text("No bookings matching this filter."),
                                ),
                              )
                            ],
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final b = filtered[index];
                            final isConfirmed = b['status'] == "CONFIRMED";
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          b['venue']?['name'] ?? 'Venue Pitch',
                                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isConfirmed ? const Color(0x2010B981) : const Color(0x20F59E0B),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            b['status'] ?? 'PENDING',
                                            style: TextStyle(
                                              color: isConfirmed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text("Slot: ${b['slot']?['start_time'] ?? ''} - ${b['slot']?['end_time'] ?? ''}"),
                                    Text("Client: ${b['user']?['name'] ?? 'Guest Player'}"),
                                    const Divider(height: 24),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Amount: ₹${b['online_amount']}",
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        ElevatedButton(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (context) => BookingDetailsScreen(booking: b)),
                                            );
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.pink,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                          child: const Text("Details", style: TextStyle(color: Colors.white)),
                                        )
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                  ),
                )
              ],
            ),
    );
  }
}

// -------------------------------------------------------------
// Booking Details Screen
// -------------------------------------------------------------
class BookingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> booking;
  const BookingDetailsScreen({super.key, required this.booking});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  bool _isLoading = false;

  void _checkin() async {
    setState(() => _isLoading = true);
    final res = await ApiService.checkinBooking(widget.booking['booking_id']);
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player successfully checked in!')),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message'] ?? 'Failed to check in player')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.booking;
    final isConfirmed = b['status'] == "CONFIRMED";

    return Scaffold(
      appBar: AppBar(title: const Text("Booking Details")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Booking ID", style: TextStyle(color: Colors.grey)),
                              Text(
                                b['eticket_code'] ?? 'APV-2026-000000',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              )
                            ],
                          ),
                          const Divider(height: 32),
                          _buildDetailRow("Client Name", b['user']?['name'] ?? 'Athlete Player'),
                          _buildDetailRow("Phone Number", b['user']?['phone_number'] ?? '+91 XXXXX XXXXX'),
                          _buildDetailRow("Sport", b['venue']?['sport_types']?.join(', ') ?? 'Sports'),
                          _buildDetailRow("Venue", b['venue']?['name'] ?? 'Sports Arena'),
                          _buildDetailRow("Date", formatLocalDate(b['slot']?['date'])),
                          _buildDetailRow("Time Interval", "${b['slot']?['start_time'] ?? ''} - ${b['slot']?['end_time'] ?? ''}"),
                          _buildDetailRow("Paid Mode", b['payment_mode']?.toUpperCase() ?? 'ONLINE'),
                          const Divider(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Online Paid", style: TextStyle(fontSize: 16)),
                              Text(
                                "₹${b['online_amount']}",
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.pink),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: isConfirmed ? _checkin : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Check-In Player", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () {
                      // Simulated chat channel trigger
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Send Message", style: TextStyle(color: AppColors.pink, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      // Cancel flow
                    },
                    child: const Text("Cancel Booking", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Scan Ticket Screen
// -------------------------------------------------------------
class ScanTicketScreen extends StatefulWidget {
  const ScanTicketScreen({super.key});

  @override
  State<ScanTicketScreen> createState() => _ScanTicketScreenState();
}

class _ScanTicketScreenState extends State<ScanTicketScreen> with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _hasScanned = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _verifyTicketCode(String code) async {
    if (_hasScanned) return;
    setState(() {
      _hasScanned = true;
      _isVerifying = true;
    });
    final bookingsRes = await ApiService.getPartnerBookings();
    setState(() => _isVerifying = false);

    final List bookings = bookingsRes['data'] ?? [];
    dynamic matchedBooking;
    for (var b in bookings) {
      if (b['eticket_code']?.toString().toUpperCase() == code.toUpperCase()) {
        matchedBooking = b;
        break;
      }
    }

    if (!mounted) return;
    if (matchedBooking != null) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text("Valid Ticket"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Player: ${matchedBooking['user']?['name'] ?? 'Athlete'}"),
              Text("Slot: ${matchedBooking['slot']?['start_time']} - ${matchedBooking['slot']?['end_time']}"),
              const SizedBox(height: 12),
              const Text("Player can be checked in.", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context); // Close dialog
                setState(() => _isVerifying = true);
                await ApiService.checkinBooking(matchedBooking['booking_id']);
                setState(() => _isVerifying = false);
                if (mounted) Navigator.pop(context); // Back to dashboard
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
              child: const Text("Confirm Check-In", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ).then((_) {
        setState(() => _hasScanned = false);
      });
    } else {
      setState(() => _hasScanned = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid E-Ticket Code.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan E-Ticket")),
      body: _isVerifying
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : Stack(
              children: [
                // 1. Real Camera Viewfinder
                Positioned.fill(
                  child: MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                        final code = barcodes.first.rawValue!;
                        _verifyTicketCode(code);
                      }
                    },
                  ),
                ),
                // 2. Dark Overlay with Transparent Cutout Box
                Positioned.fill(
                  child: CustomPaint(
                    painter: ScannerOverlayPainter(),
                  ),
                ),
                // 3. Pink Border Box and Align Text
                Center(
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.pink, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        const Center(
                          child: Text(
                            "Align QR Code",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                            ),
                          ),
                        ),
                        // 4. Scanning laser line animation
                        AnimatedBuilder(
                          animation: _animationController,
                          builder: (context, child) {
                            return Positioned(
                              top: _animationController.value * 230 + 10,
                              left: 10,
                              right: 10,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppColors.pink,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.pink.withOpacity(0.8),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    )
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // 5. Manual Input Card
                Positioned(
                  bottom: 50,
                  left: 20,
                  right: 20,
                  child: Card(
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Manual E-Ticket Entry", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _codeController,
                                  style: const TextStyle(color: Colors.white),
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    hintText: "Enter Code (e.g. APV-2026-123456)",
                                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                                    enabledBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(color: Colors.white24),
                                    ),
                                    focusedBorder: const OutlineInputBorder(
                                      borderSide: BorderSide(color: AppColors.pink),
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _verifyTicketCode(_codeController.text.trim()),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.pink,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                                child: const Text("Verify", style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black;
    
    // Screen rectangle path
    final screenPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    // Cutout path in the center
    final cutoutWidth = 250.0;
    final cutoutHeight = 250.0;
    final left = (size.width - cutoutWidth) / 2;
    final top = (size.height - cutoutHeight) / 2;
    
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, cutoutWidth, cutoutHeight),
        const Radius.circular(16),
      ));
      
    // Combine path to cut out the center
    final combinedPath = Path.combine(PathOperation.difference, screenPath, cutoutPath);
    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// -------------------------------------------------------------
// My Venues Tab Screen
// -------------------------------------------------------------
class VenuesTab extends StatefulWidget {
  const VenuesTab({super.key});

  @override
  State<VenuesTab> createState() => _VenuesTabState();
}

class _VenuesTabState extends State<VenuesTab> {
  List<dynamic> _venues = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  void _loadVenues() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getPartnerVenues();
    setState(() {
      _venues = res['data'] ?? [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Venues", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70.0),
        child: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => AddVenueWizardScreen(onComplete: _loadVenues)),
            );
          },
          backgroundColor: AppColors.pink,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadVenues();
          await Future.delayed(const Duration(milliseconds: 600));
        },
        color: AppColors.pink,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
            : _venues.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: const Center(
                          child: Text("You have no venues created yet. Tap '+' to add one."),
                        ),
                      )
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 90),
                    itemCount: _venues.length,
                  itemBuilder: (context, index) {
                    final v = _venues[index];
                    final isListed = v['status'] == "listed";
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SlotSchedulingScreen(
                                venueId: v['venue_id'], 
                                venueName: v['name'],
                                slotMode: v['slot_mode'] ?? '60m',
                                openingTime: v['opening_time'] ?? '09:00 AM',
                                closingTime: v['closing_time'] ?? '09:00 PM',
                              ),
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              height: 140,
                              width: double.infinity,
                              child: v['images'] != null && (v['images'] as List).isNotEmpty
                                  ? (() {
                                      final String firstImg = v['images'][0];
                                      if (firstImg.startsWith('http')) {
                                        return Image.network(
                                          firstImg,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: Colors.grey.shade800,
                                            child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                                          ),
                                        );
                                      } else if (firstImg.startsWith('data:')) {
                                        try {
                                          final base64Part = firstImg.split(',').last;
                                          return Image.memory(
                                            base64Decode(base64Part),
                                            fit: BoxFit.cover,
                                            errorBuilder: (context, error, stackTrace) => Container(
                                              color: Colors.grey.shade800,
                                              child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                                            ),
                                          );
                                        } catch (_) {
                                          return Container(
                                            color: Colors.grey.shade800,
                                            child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                                          );
                                        }
                                      } else {
                                        return Image.file(
                                          File(firstImg),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            color: Colors.grey.shade800,
                                            child: const Center(child: Icon(Icons.broken_image, size: 50, color: Colors.grey)),
                                          ),
                                        );
                                      }
                                    })()
                                  : Container(
                                      color: Colors.grey.shade800,
                                      child: const Center(child: Icon(Icons.image, size: 50, color: Colors.grey)),
                                    ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(v['name'] ?? 'Turf Ground', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                      ),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, color: Colors.white70, size: 20),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) => AddVenueWizardScreen(
                                                    venueToEdit: v,
                                                    onComplete: _loadVenues,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          const SizedBox(width: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isListed ? const Color(0x2010B981) : const Color(0x20F59E0B),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              isListed ? "Active" : "Unlisted",
                                              style: TextStyle(color: isListed ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text("Sport: ${v['sport_types']?.join(', ') ?? 'N/A'}", style: const TextStyle(color: Colors.grey)),
                                  Text("Base Price: ₹${v['base_price']}", style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.pink)),
                                ],
                              ),
                            )
                          ],
                        ),
                      ),
                    );
                  },
                ),
      ),
    );
  }
}

// -------------------------------------------------------------
// Add Venue 8-Step Wizard Screen
// -------------------------------------------------------------
class AddVenueWizardScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final Map<String, dynamic>? venueToEdit;
  const AddVenueWizardScreen({super.key, required this.onComplete, this.venueToEdit});

  @override
  State<AddVenueWizardScreen> createState() => _AddVenueWizardScreenState();
}

class _AddVenueWizardScreenState extends State<AddVenueWizardScreen> {
  int _currentStep = 1;
  
  // Step 1 Controllers
  final _nameController = TextEditingController();
  
  // Step 2 Fields (Multi-select list)
  final List<String> _availableSports = ["Football", "Cricket", "Badminton", "Tennis", "Basketball"];
  String _selectedSport = "";
  bool _isOtherSelected = false;
  final _customSportController = TextEditingController();
  
  // Step 3 Controllers (Pricing & Custom/Typed Duration)
  final _priceController = TextEditingController();
  final _slotModeController = TextEditingController(text: "60m");
  bool _isCustomSlotMode = false;
  final _customSlotController = TextEditingController();

  // Step 4 Controllers (Location Details)
  final _streetController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _zipController = TextEditingController();
  
  // Address Autocomplete states
  bool _isSearchingAddress = false;
  List<dynamic> _addressSuggestions = [];
  double? _userLat;
  double? _userLng;

  final List<Map<String, String>> _localFallbacks = [
    {
      "display_name": "Sector 62, Noida, Uttar Pradesh, 201301",
      "street": "Sector 62",
      "city": "Noida",
      "state": "Uttar Pradesh",
      "postcode": "201301"
    },
    {
      "display_name": "Indiranagar, Bengaluru, Karnataka, 560038",
      "street": "100 Feet Road, Indiranagar",
      "city": "Bengaluru",
      "state": "Karnataka",
      "postcode": "560038"
    },
    {
      "display_name": "Koramangala, Bengaluru, Karnataka, 560034",
      "street": "80 Feet Road, Koramangala",
      "city": "Bengaluru",
      "state": "Karnataka",
      "postcode": "560034"
    },
    {
      "display_name": "Bandra West, Mumbai, Maharashtra, 400050",
      "street": "Linking Road, Bandra West",
      "city": "Mumbai",
      "state": "Maharashtra",
      "postcode": "400050"
    },
    {
      "display_name": "HSR Layout, Bengaluru, Karnataka, 560102",
      "street": "Sector 3, HSR Layout",
      "city": "Bengaluru",
      "state": "Karnataka",
      "postcode": "560102"
    },
    {
      "display_name": "Sector 18, Noida, Uttar Pradesh, 201301",
      "street": "Sector 18 Market",
      "city": "Noida",
      "state": "Uttar Pradesh",
      "postcode": "201301"
    }
  ];

  // Step 5 Controllers (Contact Information)
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _websiteController = TextEditingController();

  // Step 6 State (Operating Hours)
  String _openingTime = "09:00 AM";
  String _closingTime = "09:00 PM";

  // Step 7 State (Amenities)
  bool _hasWifi = false;
  bool _hasParking = false;
  bool _hasShowers = false;
  bool _hasLockers = false;

  // Step 8 Controllers (Images)
  final _imgController1 = TextEditingController();
  final _imgController2 = TextEditingController();
  final _imgController3 = TextEditingController();
  final _imgController4 = TextEditingController();
  final _imgController5 = TextEditingController();

  bool _isLoading = false;

  String _to12Hour(String timeStr) {
    try {
      final clean = timeStr.trim().toUpperCase();
      if (clean.contains("AM") || clean.contains("PM")) {
        return clean;
      }
      final parts = clean.split(':');
      int hour = int.parse(parts[0]);
      final minute = parts[1];
      String ampm = "AM";
      if (hour >= 12) {
        ampm = "PM";
        if (hour > 12) {
          hour -= 12;
        }
      } else if (hour == 0) {
        hour = 12;
      }
      return "${hour.toString().padLeft(2, '0')}:${minute.padLeft(2, '0')} $ampm";
    } catch (_) {
      return "09:00 AM";
    }
  }

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    if (widget.venueToEdit != null) {
      final v = widget.venueToEdit!;
      _nameController.text = v['name'] ?? '';
      _priceController.text = v['base_price']?.toString() ?? '';
      
      final String mode = v['slot_mode'] ?? '60m';
      if (["30m", "45m", "60m", "90m", "120m"].contains(mode)) {
        _slotModeController.text = mode;
        _isCustomSlotMode = false;
      } else {
        _isCustomSlotMode = true;
        _customSlotController.text = mode.replaceAll('m', '');
      }

      // Sports offered parsing (Single selection)
      final sports = List<String>.from(v['sport_types'] ?? []);
      if (sports.isNotEmpty) {
        final sport = sports.first;
        if (_availableSports.contains(sport)) {
          _selectedSport = sport;
          _isOtherSelected = false;
        } else {
          _isOtherSelected = true;
          _selectedSport = "";
          _customSportController.text = sport;
        }
      }

      // Address details
      final address = v['address']?.toString() ?? '';
      if (address.isNotEmpty) {
        final parts = address.split(',');
        if (parts.length >= 3) {
          _streetController.text = parts[0].trim();
          _cityController.text = parts[1].trim();
          final stateZip = parts[2].trim().split(' ');
          if (stateZip.isNotEmpty) {
            _stateController.text = stateZip[0].trim();
            if (stateZip.length > 1) {
              _zipController.text = stateZip[1].trim();
            }
          }
        } else {
          _streetController.text = address;
        }
      }

      _contactPhoneController.text = v['contact_phone'] ?? '';
      _openingTime = _to12Hour(v['opening_time'] ?? '09:00 AM');
      _closingTime = _to12Hour(v['closing_time'] ?? '09:00 PM');
      
      // Images
      final imgs = List<String>.from(v['images'] ?? []);
      if (imgs.isNotEmpty) _imgController1.text = imgs[0];
      if (imgs.length > 1) _imgController2.text = imgs[1];
      if (imgs.length > 2) _imgController3.text = imgs[2];
      if (imgs.length > 3) _imgController4.text = imgs[3];
      if (imgs.length > 4) _imgController5.text = imgs[4];

      // Amenities
      final ams = List<String>.from(v['amenities'] ?? []);
      _hasWifi = ams.contains("Wi-Fi");
      _hasParking = ams.contains("Parking");
      _hasShowers = ams.contains("Showers");
      _hasLockers = ams.contains("Lockers");
    } else {
      // Leave image controllers empty by default for user upload
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customSportController.dispose();
    _priceController.dispose();
    _slotModeController.dispose();
    _customSlotController.dispose();
    _streetController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _websiteController.dispose();
    _imgController1.dispose();
    _imgController2.dispose();
    _imgController3.dispose();
    _imgController4.dispose();
    _imgController5.dispose();
    super.dispose();
  }

  void _getUserLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always || permission == LocationPermission.whileInUse) {
          Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.low);
          _userLat = position.latitude;
          _userLng = position.longitude;
        }
      }
    } catch (_) {}
  }

  void _searchAddress(String query) async {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.length < 3) {
      setState(() => _addressSuggestions = []);
      return;
    }

    setState(() => _isSearchingAddress = true);

    // 1. Gather offline/local matches
    final localMatches = _localFallbacks.where((item) {
      final name = item['display_name']!.toLowerCase();
      return name.contains(cleanQuery);
    }).toList();

    try {
      // 2. Query Photon Komoot API (covers the whole of India and the entire globe)
      String urlStr = 'https://photon.komoot.io/api/?q=${Uri.encodeComponent(query)}&limit=10';
      if (_userLat != null && _userLng != null) {
        urlStr += '&lat=$_userLat&lon=$_userLng';
      }
      final url = Uri.parse(urlStr);
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final features = data['features'] as List? ?? [];
        
        // Filter results to ensure they belong to India (for cleanliness and focus)
        final indiaFeatures = features.where((f) {
          final props = f['properties'] ?? {};
          final country = props['country']?.toString().toLowerCase() ?? '';
          final state = props['state']?.toString().toLowerCase() ?? '';
          // Keep if country is India, or if it has an Indian state name, or if country is empty
          return country.contains('india') || 
                 country.contains('ind') || 
                 state.isNotEmpty || 
                 country.isEmpty;
        }).take(5).toList();
        
        setState(() {
          // Combine local fallbacks and India-filtered online results
          _addressSuggestions = [...localMatches, ...indiaFeatures];
        });
      } else {
        setState(() {
          _addressSuggestions = localMatches;
        });
      }
    } catch (_) {
      // Offline fallback
      setState(() {
        _addressSuggestions = localMatches;
      });
    }
    setState(() => _isSearchingAddress = false);
  }

  void _selectAddress(dynamic item) {
    if (item is Map && item.containsKey('properties')) {
      // Photon format parsing
      final props = item['properties'] ?? {};
      final name = props['name']?.toString() ?? '';
      final street = props['street']?.toString() ?? '';
      final city = props['city']?.toString() ?? '';
      final state = props['state']?.toString() ?? '';
      final postcode = props['postcode']?.toString() ?? '';
      
      final fullStreet = street.isNotEmpty ? "$name, $street" : name;

      setState(() {
        _streetController.text = fullStreet;
        if (city.isNotEmpty) _cityController.text = city;
        if (state.isNotEmpty) _stateController.text = state;
        if (postcode.isNotEmpty) _zipController.text = postcode;
        _addressSuggestions = [];
      });
    } else if (item is Map && item.containsKey('display_name')) {
      // Local/Offline format parsing
      setState(() {
        _streetController.text = item['street'] ?? '';
        _cityController.text = item['city'] ?? '';
        _stateController.text = item['state'] ?? '';
        _zipController.text = item['postcode'] ?? '';
        _addressSuggestions = [];
      });
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 1:
        if (_nameController.text.trim().isEmpty) {
          _showValidationError("Venue name is required");
          return false;
        }
        break;
      case 2:
        if (_selectedSport.isEmpty && (!_isOtherSelected || _customSportController.text.trim().isEmpty)) {
          _showValidationError("Please select a sport category");
          return false;
        }
        break;
      case 3:
        if (_priceController.text.trim().isEmpty) {
          _showValidationError("Base price is required");
          return false;
        }
        final price = double.tryParse(_priceController.text.trim());
        if (price == null || price <= 0) {
          _showValidationError("Please enter a valid base price greater than 0");
          return false;
        }
        if (_isCustomSlotMode && _customSlotController.text.trim().isEmpty) {
          _showValidationError("Please enter a custom slot duration");
          return false;
        }
        break;
      case 8:
        final imgCount = [
          _imgController1.text,
          _imgController2.text,
          _imgController3.text,
          _imgController4.text,
          _imgController5.text
        ].where((img) => img.trim().isNotEmpty).length;
        if (imgCount < 2) {
          _showValidationError("At least 2 venue images are required");
          return false;
        }
        break;
      case 5:
        if (_contactPhoneController.text.trim().isEmpty) {
          _showValidationError("Contact phone number is required");
          return false;
        }
        break;
    }
    return true;
  }

  void _showValidationError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  void _nextStep() async {
    if (!_validateCurrentStep()) return;
    
    if (_currentStep < 9) {
      setState(() {
        _currentStep++;
      });
    } else {
      setState(() => _isLoading = true);
      
      final activeAmenities = [
        if (_hasWifi) "Wi-Fi",
        if (_hasParking) "Parking",
        if (_hasShowers) "Showers",
        if (_hasLockers) "Lockers"
      ];

      final imageList = [
        _imgController1.text.trim(),
        _imgController2.text.trim(),
        _imgController3.text.trim(),
        _imgController4.text.trim(),
        _imgController5.text.trim()
      ].where((url) => url.isNotEmpty).toList();

      final fullAddress = "${_streetController.text.trim()}, ${_cityController.text.trim()}, ${_stateController.text.trim()} ${_zipController.text.trim()}";

      final finalSports = <String>[];
      if (_isOtherSelected && _customSportController.text.trim().isNotEmpty) {
        finalSports.add(_customSportController.text.trim());
      } else if (_selectedSport.isNotEmpty) {
        finalSports.add(_selectedSport);
      }

      final double basePrice = double.tryParse(_priceController.text.trim()) ?? 1000.0;
      final String slotMode = _isCustomSlotMode ? "${_customSlotController.text.trim()}m" : _slotModeController.text.trim();

      dynamic res;
      if (widget.venueToEdit != null) {
        res = await ApiService.updatePartnerVenue(
          venueId: widget.venueToEdit!['venue_id'],
          name: _nameController.text.trim(),
          sportTypes: finalSports,
          basePrice: basePrice,
          slotMode: slotMode,
          amenities: activeAmenities,
          images: imageList,
          address: fullAddress,
          contactPhone: _contactPhoneController.text.trim(),
          latitude: _userLat,
          longitude: _userLng,
          openingTime: _openingTime,
          closingTime: _closingTime,
        );
      } else {
        res = await ApiService.createPartnerVenue(
          name: _nameController.text.trim(),
          sportTypes: finalSports,
          basePrice: basePrice,
          slotMode: slotMode,
          amenities: activeAmenities,
          images: imageList,
          address: fullAddress,
          contactPhone: _contactPhoneController.text.trim(),
          latitude: _userLat,
          longitude: _userLng,
          openingTime: _openingTime,
          closingTime: _closingTime,
        );
      }
      setState(() => _isLoading = false);

      if (res['success'] == true) {
        widget.onComplete();
        if (mounted) {
          if (widget.venueToEdit != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Venue updated successfully. Pending admin approval to list it."),
                backgroundColor: Colors.amber,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Venue created successfully!"),
                backgroundColor: Colors.green,
              ),
            );
          }
          Navigator.pop(context);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to submit venue.')),
        );
      }
    }
  }

  void _prevStep() {
    if (_currentStep > 1) {
      setState(() {
        _currentStep--;
      });
    }
  }

  List<String> _getActiveImages() {
    return [
      _imgController1.text.trim(),
      _imgController2.text.trim(),
      _imgController3.text.trim(),
      _imgController4.text.trim(),
      _imgController5.text.trim()
    ].where((url) => url.isNotEmpty).toList();
  }

  void _syncControllersFromActive(List<String> active) {
    final controllers = [_imgController1, _imgController2, _imgController3, _imgController4, _imgController5];
    for (int i = 0; i < 5; i++) {
      if (i < active.length) {
        controllers[i].text = active[i];
      } else {
        controllers[i].text = "";
      }
    }
  }

  void _handleImageUpload(int index) {
    final controllers = [_imgController1, _imgController2, _imgController3, _imgController4, _imgController5];
    final controller = controllers[index];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Add Photo", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: AppColors.pink),
                title: const Text("Take Photo (Camera)", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  _simulateUpload(controller, isCamera: true);
                },
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.photo, color: AppColors.pink),
                title: const Text("Upload from Gallery", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  _simulateUpload(controller, isCamera: false);
                },
              ),
              const Divider(color: Colors.white10),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.orange),
                title: const Text("Choose from Premium Presets", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _showPresetPicker(controller);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _simulateUpload(TextEditingController controller, {required bool isCamera}) async {
    try {
      if (isCamera) {
        final status = await Permission.camera.request();
        if (status != PermissionStatus.granted) {
          _showValidationError("Camera permission is required to capture photos.");
          return;
        }
      } else {
        final status = await Permission.photos.request();
        final storageStatus = await Permission.storage.request();
        if (status != PermissionStatus.granted && storageStatus != PermissionStatus.granted) {
          _showValidationError("Gallery access permission is required to select photos.");
          return;
        }
      }

      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: isCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 60,
      );
      if (image != null) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator(color: AppColors.pink)),
        );
        final uploadRes = await ApiService.uploadFile(image.path);
        if (mounted) Navigator.pop(context);

        if (uploadRes['success'] == true) {
          setState(() {
            controller.text = uploadRes['data']['url'];
          });
        } else {
          _showValidationError(uploadRes['error']?['message'] ?? uploadRes['message'] ?? 'Failed to upload image');
        }
      }
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _showPresetPicker(TextEditingController controller) {
    final presets = [
      "https://images.unsplash.com/photo-1587280501635-68a0e82cd5ff?q=80&w=800",
      "https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=800",
      "https://images.unsplash.com/photo-1529900748604-07564a03e7a6?q=80&w=800",
      "https://images.unsplash.com/photo-1546519638-68e109498ffc?q=80&w=800",
      "https://images.unsplash.com/photo-1595435934249-5df7ed86e1c0?q=80&w=800",
    ];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text("Select Preset", style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 320,
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: presets.length,
            itemBuilder: (context, idx) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    controller.text = presets[idx];
                  });
                  Navigator.pop(context);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(presets[idx], fit: BoxFit.cover),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.venueToEdit != null ? "Edit Venue" : "Add New Venue";
    return Scaffold(
      appBar: AppBar(title: Text(titleText)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text("Step $_currentStep of 9", style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.pink)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _currentStep / 9,
                    color: AppColors.pink,
                    backgroundColor: Colors.grey.shade800,
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: SingleChildScrollView(
                      child: _buildStepContent(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentStep > 1)
                        OutlinedButton(
                          onPressed: _prevStep,
                          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 50)),
                          child: const Text("Back"),
                        )
                      else
                        const SizedBox(),
                      ElevatedButton(
                        onPressed: _nextStep,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.pink,
                          minimumSize: const Size(120, 50),
                        ),
                        child: Text(_currentStep == 9 ? "Submit" : "Next", style: const TextStyle(color: Colors.white)),
                      )
                    ],
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 1:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Basic Venue Details *", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "Venue Name *", border: OutlineInputBorder()),
            )
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Sport Category Offered *", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Select a sport category for this venue.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ..._availableSports.map((sport) {
                  final isSelected = _selectedSport == sport;
                  IconData sportIcon = Icons.sports;
                  if (sport == "Football") sportIcon = Icons.sports_soccer;
                  if (sport == "Cricket") sportIcon = Icons.sports_cricket;
                  if (sport == "Badminton") sportIcon = Icons.sports_tennis;
                  if (sport == "Tennis") sportIcon = Icons.sports_tennis;
                  if (sport == "Basketball") sportIcon = Icons.sports_basketball;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (isSelected) {
                          _selectedSport = "";
                        } else {
                          _selectedSport = sport;
                          _isOtherSelected = false;
                        }
                      });
                    },
                    child: Container(
                      width: 140,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.pink.withOpacity(0.08) : AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? AppColors.pink : Colors.white.withOpacity(0.08),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(sportIcon, color: isSelected ? AppColors.pink : Colors.white60, size: 28),
                          const SizedBox(height: 8),
                          Text(sport, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.white70)),
                        ],
                      ),
                    ),
                  );
                }),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (_isOtherSelected) {
                        _isOtherSelected = false;
                      } else {
                        _isOtherSelected = true;
                        _selectedSport = "";
                      }
                    });
                  },
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isOtherSelected ? AppColors.pink.withOpacity(0.08) : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: _isOtherSelected ? AppColors.pink : Colors.white.withOpacity(0.08),
                        width: 2,
                      ),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, color: Colors.white60, size: 28),
                        SizedBox(height: 8),
                        Text("Other", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_isOtherSelected) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _customSportController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: "Custom Sport Name",
                  border: OutlineInputBorder(),
                  hintText: "e.g. Volleyball, Swimming",
                ),
              ),
            ],
          ],
        );
      case 3:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Pricing & Slot Structure *", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Base Price per Hour (₹) *", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _isCustomSlotMode ? "Custom" : _slotModeController.text,
              items: const [
                DropdownMenuItem(value: "30m", child: Text("30 mins")),
                DropdownMenuItem(value: "45m", child: Text("45 mins")),
                DropdownMenuItem(value: "60m", child: Text("60 mins")),
                DropdownMenuItem(value: "90m", child: Text("90 mins")),
                DropdownMenuItem(value: "120m", child: Text("120 mins")),
                DropdownMenuItem(value: "Custom", child: Text("Custom")),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    if (val == "Custom") {
                      _isCustomSlotMode = true;
                    } else {
                      _isCustomSlotMode = false;
                      _slotModeController.text = val;
                    }
                  });
                }
              },
              decoration: const InputDecoration(labelText: "Default Slot Duration", border: OutlineInputBorder()),
            ),
            if (_isCustomSlotMode) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _customSlotController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Custom Slot Duration (minutes) *",
                  border: OutlineInputBorder(),
                  suffixText: "mins",
                ),
              ),
            ],
          ],
        );
      case 4:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Address / Location Details *", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _streetController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "Street Address *", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _cityController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: "City *", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stateController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: "State *", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _zipController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "ZIP / Postal Code *", border: OutlineInputBorder()),
                  ),
                ),
              ],
            )
          ],
        );
      case 5:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Contact Information *", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _contactPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: "Contact Phone Number *", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contactEmailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "Contact Email Address", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _websiteController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: "Website URL (Optional)", border: OutlineInputBorder()),
            ),
          ],
        );
      case 6:
        final hoursList = [
          "05:00 AM", "06:00 AM", "07:00 AM", "08:00 AM", "09:00 AM", "10:00 AM", "11:00 AM",
          "12:00 PM", "01:00 PM", "02:00 PM", "03:00 PM", "04:00 PM", "05:00 PM", "06:00 PM",
          "07:00 PM", "08:00 PM", "09:00 PM", "10:00 PM", "11:00 PM"
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Operating Hours", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _openingTime,
              items: hoursList.map((time) {
                return DropdownMenuItem(value: time, child: Text(time));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _openingTime = val);
              },
              decoration: const InputDecoration(labelText: "Opening Time", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _closingTime,
              items: hoursList.map((time) {
                return DropdownMenuItem(value: time, child: Text(time));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _closingTime = val);
              },
              decoration: const InputDecoration(labelText: "Closing Time", border: OutlineInputBorder()),
            ),
          ],
        );
      case 7:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select Amenities Offered", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text("Free Wi-Fi"),
              subtitle: const Text("High-speed internet access for players"),
              value: _hasWifi,
              activeColor: AppColors.pink,
              onChanged: (val) => setState(() => _hasWifi = val),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("On-Site Parking"),
              subtitle: const Text("Dedicated parking area for guests"),
              value: _hasParking,
              activeColor: AppColors.pink,
              onChanged: (val) => setState(() => _hasParking = val),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("Shower Rooms"),
              subtitle: const Text("Clean shower facilities for post-game use"),
              value: _hasShowers,
              activeColor: AppColors.pink,
              onChanged: (val) => setState(() => _hasShowers = val),
            ),
            const Divider(),
            SwitchListTile(
              title: const Text("Locker Rooms"),
              subtitle: const Text("Secure storage lockers for personal items"),
              value: _hasLockers,
              activeColor: AppColors.pink,
              onChanged: (val) => setState(() => _hasLockers = val),
            ),
          ],
        );
      case 8:
        final active = _getActiveImages();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Venue Images *", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text("Upload up to 5 pictures. Minimum 2 images required.", style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.1,
              ),
              itemCount: active.length < 5 ? active.length + 1 : 5,
              itemBuilder: (context, index) {
                if (index < active.length) {
                  final url = active[index];
                  final isMain = index == 0;
                  ImageProvider imageProvider;
                  if (url.startsWith('http')) {
                    imageProvider = NetworkImage(url);
                  } else if (url.startsWith('data:')) {
                    try {
                      final base64Part = url.split(',').last;
                      imageProvider = MemoryImage(base64Decode(base64Part));
                    } catch (_) {
                      imageProvider = const NetworkImage('https://images.unsplash.com/photo-1508098682722-e99c43a406b2?w=800');
                    }
                  } else {
                    imageProvider = FileImage(File(url));
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: isMain ? AppColors.pink : Colors.white.withOpacity(0.08), width: isMain ? 2 : 1),
                    ),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image(
                              image: imageProvider,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: Colors.grey.shade800,
                                child: const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
                              ),
                            ),
                          ),
                        ),
                        // Main Badge / Button
                        Positioned(
                          top: 8,
                          left: 8,
                          child: GestureDetector(
                            onTap: () {
                              if (!isMain) {
                                setState(() {
                                  final item = active.removeAt(index);
                                  active.insert(0, item);
                                  _syncControllersFromActive(active);
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isMain ? AppColors.pink : Colors.black87,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isMain ? Colors.transparent : Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(isMain ? Icons.star : Icons.star_border, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  Text(
                                    isMain ? "MAIN" : "Make Main",
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Delete Button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                active.removeAt(index);
                                _syncControllersFromActive(active);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          ),
                        ),
                        // Reordering Controls
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Left Arrow
                              index > 0
                                  ? GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          final temp = active[index];
                                          active[index] = active[index - 1];
                                          active[index - 1] = temp;
                                          _syncControllersFromActive(active);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                                        child: const Icon(Icons.arrow_back, color: Colors.white, size: 14),
                                      ),
                                    )
                                  : const SizedBox(width: 26),
                              // Right Arrow
                              index < active.length - 1
                                  ? GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          final temp = active[index];
                                          active[index] = active[index + 1];
                                          active[index + 1] = temp;
                                          _syncControllersFromActive(active);
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                                        child: const Icon(Icons.arrow_forward, color: Colors.white, size: 14),
                                      ),
                                    )
                                  : const SizedBox(width: 26),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                } else {
                  return GestureDetector(
                    onTap: () => _handleImageUpload(active.length),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_a_photo, color: Colors.grey, size: 28),
                            SizedBox(height: 8),
                            Text("Upload Image", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        );
      case 9:
        final finalSlotText = _isCustomSlotMode ? "${_customSlotController.text} mins" : "${_slotModeController.text.replaceAll('m', '')} mins";
        final finalSports = <String>[];
        if (_isOtherSelected && _customSportController.text.trim().isNotEmpty) {
          finalSports.add(_customSportController.text.trim());
        } else if (_selectedSport.isNotEmpty) {
          finalSports.add(_selectedSport);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Review Venue Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReviewRow("Venue Name", _nameController.text.isNotEmpty ? _nameController.text : "N/A"),
                    _buildReviewRow("Sports", finalSports.join(", ")),
                    _buildReviewRow("Base Price", "₹${_priceController.text.isNotEmpty ? _priceController.text : '0.00'} per hour"),
                    _buildReviewRow("Slot Duration", finalSlotText),
                    const Divider(),
                    _buildReviewRow("Address", "${_streetController.text}, ${_cityController.text}, ${_stateController.text} ${_zipController.text}"),
                    _buildReviewRow("Contact Phone", _contactPhoneController.text.isNotEmpty ? _contactPhoneController.text : "N/A"),
                    _buildReviewRow("Contact Email", _contactEmailController.text.isNotEmpty ? _contactEmailController.text : "N/A"),
                    if (_websiteController.text.isNotEmpty)
                      _buildReviewRow("Website", _websiteController.text),
                    const Divider(),
                    _buildReviewRow("Timings", "$_openingTime to $_closingTime"),
                    _buildReviewRow("Amenities", [
                      if (_hasWifi) "Wi-Fi",
                      if (_hasParking) "Parking",
                      if (_hasShowers) "Showers",
                      if (_hasLockers) "Lockers",
                    ].join(", ").isNotEmpty ? [
                      if (_hasWifi) "Wi-Fi",
                      if (_hasParking) "Parking",
                      if (_hasShowers) "Showers",
                      if (_hasLockers) "Lockers",
                    ].join(", ") : "None"),
                  ],
                ),
              ),
            ),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildReviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
// -------------------------------------------------------------
// Slot details / Scheduling Blocker Grid
// -------------------------------------------------------------
class SlotSchedulingScreen extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String slotMode;
  final String openingTime;
  final String closingTime;
  const SlotSchedulingScreen({
    super.key, 
    required this.venueId, 
    required this.venueName,
    required this.slotMode,
    required this.openingTime,
    required this.closingTime,
  });

  @override
  State<SlotSchedulingScreen> createState() => _SlotSchedulingScreenState();
}

class _SlotSchedulingScreenState extends State<SlotSchedulingScreen> {
  List<dynamic> _slots = [];
  bool _isLoading = true;
  late String _selectedDate;
  bool _isSelectionMode = false;
  final Set<String> _selectedSlotIds = {};

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now().toIso8601String().substring(0, 10);
    _loadSlots();
    WebSocketSyncManager.subscribe('slots', _loadSlots);
  }

  @override
  void dispose() {
    WebSocketSyncManager.unsubscribe('slots', _loadSlots);
    super.dispose();
  }

  void _loadSlots() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getPartnerVenueSlots(widget.venueId, _selectedDate);
    setState(() {
      _slots = res['data'] ?? [];
      _isLoading = false;
    });
  }

  void _toggleBlock(String slotId) async {
    setState(() => _isLoading = true);
    await ApiService.toggleSlotBlock(slotId);
    _loadSlots();
  }

  String _to24Hour(String time12h) {
    try {
      final clean = time12h.trim().toUpperCase();
      final parts = clean.split(' ');
      if (parts.length < 2) return clean;
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final int minute = int.parse(timeParts[1]);
      final ampm = parts[1];

      if (ampm == "PM" && hour < 12) {
        hour += 12;
      } else if (ampm == "AM" && hour == 12) {
        hour = 0;
      }

      return "${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}";
    } catch (_) {
      return "06:00";
    }
  }

  int _getDurationMinutes(String slotMode) {
    try {
      final clean = slotMode.replaceAll(RegExp(r'[^0-9]'), '');
      return int.parse(clean);
    } catch (_) {
      return 60;
    }
  }

  void _bulkGenerate() async {
    final defaultStart = _to24Hour(widget.openingTime);
    final defaultEnd = _to24Hour(widget.closingTime);
    final startController = TextEditingController(text: defaultStart);
    final endController = TextEditingController(text: defaultEnd);
    final priceController = TextEditingController(text: "1000");

    String rangeOption = "Selected Date";
    List<bool> selectedDays = [false, false, false, false, false, false, false];
    const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Bulk Generate Slots"),
        content: StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: startController, 
                      decoration: const InputDecoration(
                        labelText: "Start Time (HH:MM)", 
                        labelStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                      )
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: endController, 
                      decoration: const InputDecoration(
                        labelText: "End Time (HH:MM)", 
                        labelStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                      )
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController, 
                      keyboardType: TextInputType.number, 
                      decoration: const InputDecoration(
                        labelText: "Price (₹)", 
                        labelStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                      )
                    ),
                    const SizedBox(height: 20),
                    const Text("Generation Range", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: rangeOption,
                      items: [
                        DropdownMenuItem(
                          value: "Selected Date", 
                          child: Text("Selected Date ($_selectedDate)", overflow: TextOverflow.ellipsis),
                        ),
                        const DropdownMenuItem(
                          value: "Whole Week", 
                          child: Text("Whole Week (Next 7 Days)", overflow: TextOverflow.ellipsis),
                        ),
                        const DropdownMenuItem(
                          value: "Selected Days", 
                          child: Text("Selected Days of Week", overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            rangeOption = val;
                          });
                        }
                      },
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                    ),
                    if (rangeOption == "Selected Days") ...[
                      const SizedBox(height: 16),
                      const Text("Select Days:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(7, (idx) {
                          final isSel = selectedDays[idx];
                          return FilterChip(
                            label: Text(weekdays[idx], style: TextStyle(color: isSel ? Colors.white : Colors.grey, fontSize: 12)),
                            selected: isSel,
                            selectedColor: AppColors.pink,
                            checkmarkColor: Colors.white,
                            onSelected: (selected) {
                              setDialogState(() {
                                selectedDays[idx] = selected;
                              });
                            },
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (rangeOption == "Selected Days" && !selectedDays.contains(true)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please select at least one day"), backgroundColor: Colors.redAccent),
                );
                return;
              }
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
            child: const Text("Generate", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);

      List<String> targetDates = [];
      if (rangeOption == "Selected Date") {
        targetDates = [_selectedDate];
      } else if (rangeOption == "Whole Week") {
        for (int i = 0; i < 7; i++) {
          final d = DateTime.now().add(Duration(days: i));
          targetDates.add(d.toIso8601String().substring(0, 10));
        }
      } else {
        for (int i = 0; i < 7; i++) {
          final d = DateTime.now().add(Duration(days: i));
          final index = d.weekday - 1; 
          if (selectedDays[index]) {
            targetDates.add(d.toIso8601String().substring(0, 10));
          }
        }
      }

      if (targetDates.isNotEmpty) {
        try {
          await ApiService.bulkGenerateSlots(
            widget.venueId,
            targetDates,
            startController.text.trim(),
            endController.text.trim(),
            double.parse(priceController.text.trim()),
            _getDurationMinutes(widget.slotMode),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to generate slots: $e"), backgroundColor: Colors.redAccent),
          );
        }
      }
      _loadSlots();
    }
  }

  void _selectAllSlots() {
    setState(() {
      final unbookedSlots = _slots.where((s) => s['status'] != 'booked').map((s) => s['slot_id'] as String).toList();
      _selectedSlotIds.clear();
      _selectedSlotIds.addAll(unbookedSlots);
    });
  }

  void _deleteSelectedSlots() async {
    if (_selectedSlotIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.surface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Delete Slots"),
        content: Text("Are you sure you want to delete ${_selectedSlotIds.length} slot(s)?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await ApiService.bulkDeleteSlots(widget.venueId, _selectedSlotIds.toList());
        setState(() {
          _selectedSlotIds.clear();
          _isSelectionMode = false;
        });
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to delete slots: $e"), backgroundColor: Colors.redAccent),
        );
      }
      _loadSlots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.venueName),
        actions: [
          if (_isSelectionMode) ...[
            TextButton(
              onPressed: _selectAllSlots,
              child: const Text("Select All"),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: _selectedSlotIds.isEmpty ? null : _deleteSelectedSlots,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectionMode = false;
                  _selectedSlotIds.clear();
                });
              },
            ),
          ] else ...[
            if (_slots.any((s) => s['status'] != 'booked'))
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSelectionMode = true;
                  });
                },
                child: const Text("Select"),
              ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Configure Slots Blocker Grid", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  // Calendar date switcher
                  SizedBox(
                    height: 54,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: List.generate(7, (i) {
                        final date = DateTime.now().add(Duration(days: i - 3));
                        final dateStr = date.toIso8601String().substring(0, 10);
                        final isSelected = _selectedDate == dateStr;
                        final months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                        final monthStr = months[date.month - 1];

                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDate = dateStr;
                              _loadSlots();
                            });
                          },
                          child: Container(
                            width: 74,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.pink : theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  date.day.toString().padLeft(2, '0'),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : null,
                                  ),
                                ),
                                Text(
                                  monthStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isSelected ? Colors.white70 : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Grid of slots
                  Expanded(
                    child: _slots.isEmpty
                        ? const Center(child: Text("No slots generated for this date."))
                        : GridView.builder(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                              childAspectRatio: 2.2,
                            ),
                            itemCount: _slots.length,
                            itemBuilder: (context, index) {
                              final slot = _slots[index];
                              final isBooked = slot['status'] == 'booked';
                              final isBlocked = slot['status'] == 'blocked_by_partner';
                              final isSelected = _selectedSlotIds.contains(slot['slot_id']);

                              Color bg = theme.colorScheme.surface;
                              Color textColor = theme.colorScheme.onSurface;

                              if (isBooked) {
                                bg = Colors.red.withOpacity(0.2);
                                textColor = Colors.red;
                              } else if (isBlocked) {
                                bg = Colors.grey.shade800;
                                textColor = Colors.grey;
                              }

                              if (_isSelectionMode && isSelected) {
                                bg = AppColors.pink.withOpacity(0.15);
                              }

                              return GestureDetector(
                                onTap: isBooked 
                                    ? null 
                                    : (_isSelectionMode 
                                        ? () {
                                            setState(() {
                                              if (isSelected) {
                                                _selectedSlotIds.remove(slot['slot_id']);
                                              } else {
                                                _selectedSlotIds.add(slot['slot_id']);
                                              }
                                            });
                                          }
                                        : () => _toggleBlock(slot['slot_id'])),
                                onLongPress: isBooked || _isSelectionMode
                                    ? null
                                    : () {
                                        setState(() {
                                          _isSelectionMode = true;
                                          _selectedSlotIds.add(slot['slot_id']);
                                        });
                                      },
                                child: Stack(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected 
                                              ? AppColors.pink 
                                              : Colors.grey.withOpacity(0.2),
                                          width: isSelected ? 2.0 : 1.0,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            slot['start_time'] ?? '', 
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold, 
                                              color: textColor,
                                            ),
                                          ),
                                          Text(
                                            "₹${slot['price']}", 
                                            style: const TextStyle(
                                              fontSize: 11, 
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isSelectionMode && !isBooked)
                                      Positioned(
                                        top: 4,
                                        right: 4,
                                        child: Icon(
                                          isSelected 
                                              ? Icons.check_circle 
                                              : Icons.radio_button_unchecked,
                                          size: 14,
                                          color: isSelected 
                                              ? AppColors.pink 
                                              : Colors.grey,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 24),
                  // CTA Buttons
                  Row(
                    children: [
                      Expanded(
                        child: _isSelectionMode
                            ? ElevatedButton(
                                onPressed: _selectedSlotIds.isEmpty ? null : _deleteSelectedSlots,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  minimumSize: const Size(double.infinity, 50),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: Text(
                                  "Delete Selected (${_selectedSlotIds.length})",
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              )
                            : OutlinedButton(
                                onPressed: _bulkGenerate,
                                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                                child: const Text("Bulk Generate Slots"),
                              ),
                      ),
                    ],
                  )
                ],
              ),
            ),
    );
  }
}

// -------------------------------------------------------------
// Payments & Settlement Tab Screen
// -------------------------------------------------------------
class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  int _activeSubTab = 0; // 0: Overview, 1: Payouts
  List<dynamic> _settlements = [];
  List<dynamic> _bookings = [];
  Map<String, dynamic> _profile = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettlements();
  }

  void _loadSettlements() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getPartnerSettlements();
    final bookingsRes = await ApiService.getPartnerBookings();
    final profileRes = await ApiService.getProfile();
    setState(() {
      _settlements = res['data'] ?? [];
      _bookings = bookingsRes['data'] ?? [];
      _profile = profileRes['data'] ?? {};
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text("Payments & Settlements", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : Column(
              children: [
                // Tab Swapper
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _activeSubTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: _activeSubTab == 0 ? AppColors.brandGradient : null,
                          color: _activeSubTab == 0 ? null : const Color(0xFF1A1E29),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _activeSubTab == 0 ? Colors.transparent : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Text(
                          "Overview",
                          style: TextStyle(
                            color: _activeSubTab == 0 ? Colors.white : Colors.grey.shade400,
                            fontWeight: _activeSubTab == 0 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => setState(() => _activeSubTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: _activeSubTab == 1 ? AppColors.brandGradient : null,
                          color: _activeSubTab == 1 ? null : const Color(0xFF1A1E29),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _activeSubTab == 1 ? Colors.transparent : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Text(
                          "Settlement History",
                          style: TextStyle(
                            color: _activeSubTab == 1 ? Colors.white : Colors.grey.shade400,
                            fontWeight: _activeSubTab == 1 ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      _loadSettlements();
                      await Future.delayed(const Duration(milliseconds: 600));
                    },
                    color: AppColors.pink,
                    child: _activeSubTab == 0
                        ? _buildOverviewTab(theme)
                        : _buildSettlementList(),
                  ),
                )
              ],
            ),
    );
  }

  Widget _buildOverviewTab(ThemeData theme) {
    double totalRevenue = 0.0;
    double onlinePaid = 0.0;
    double payAtVenue = 0.0;

    for (var b in _bookings) {
      if (b['status'] == "CONFIRMED") {
        final amt = double.tryParse(b['online_amount']?.toString() ?? '0') ?? 0.0;
        if (b['payment_mode'] == 'pay_at_venue') {
          payAtVenue += amt;
        } else {
          onlinePaid += amt;
        }
        totalRevenue += amt;
      }
    }

    // Try to fallback to profile total earnings if bookings are empty
    if (totalRevenue == 0.0 && _profile['total_earnings'] != null) {
      totalRevenue = double.tryParse(_profile['total_earnings'].toString()) ?? 0.0;
      onlinePaid = totalRevenue;
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Total Revenue Earned", style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 8),
                  Text("₹${totalRevenue.toStringAsFixed(2)}", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Online Payments"),
                      Text("₹${onlinePaid.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Pay at Venue (Cash)"),
                      Text("₹${payAtVenue.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const DisputesScreen()));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.pink,
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text("Open Disputes Panel", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildSettlementList() {
    if (_settlements.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: const Center(child: Text("No settlements generated yet.")),
          )
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _settlements.length,
      itemBuilder: (context, index) {
        final s = _settlements[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text("Net Settlement: ₹${s['net_amount']}"),
            subtitle: Text("Period: ${s['period_start']?.toString().substring(0, 10)} to ${s['period_end']?.toString().substring(0, 10)}"),
            trailing: Chip(label: Text(s['status'] ?? 'pending')),
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// Disputes Screen
// -------------------------------------------------------------
class DisputesScreen extends StatefulWidget {
  const DisputesScreen({super.key});

  @override
  State<DisputesScreen> createState() => _DisputesScreenState();
}

class _DisputesScreenState extends State<DisputesScreen> {
  List<dynamic> _disputes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDisputes();
  }

  void _loadDisputes() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getPartnerDisputes();
    setState(() {
      _disputes = res['data'] ?? [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Disputes Board")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : _disputes.isEmpty
              ? const Center(child: Text("No disputes logged for your venues."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _disputes.length,
                  itemBuilder: (context, index) {
                    final d = _disputes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Dispute ID: ${d['dispute_id']?.toString().substring(0, 8)}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                Chip(label: Text(d['status'] ?? 'open')),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("Issue details: ${d['details']}"),
                            Text("Raised by: ${d['raised_by']}"),
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
// Profile Tab Screen
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
  Map<String, dynamic> _systemSettings = {};
  Map<String, String> _localDocPaths = {};

  // Notification preferences
  bool _bookingAlerts = true;
  bool _paymentsAlerts = true;
  bool _promotionsAlerts = false;
  bool _emailUpdates = true;

  // Security preferences
  bool _twoFactorEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadLocalDocPaths();
    _loadPreferences();
    _loadProfile();
  }

  void _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bookingAlerts = prefs.getBool('booking_alerts') ?? true;
      _paymentsAlerts = prefs.getBool('payments_alerts') ?? true;
      _promotionsAlerts = prefs.getBool('promotions_alerts') ?? false;
      _emailUpdates = prefs.getBool('email_updates') ?? true;
      _twoFactorEnabled = prefs.getBool('two_factor_enabled') ?? false;
    });
  }

  void _loadLocalDocPaths() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final Map<String, String> paths = {};
    for (final key in keys) {
      if (key.startsWith('kyc_path_')) {
        final docType = key.replaceFirst('kyc_path_', '');
        paths[docType] = prefs.getString(key) ?? '';
      }
    }
    setState(() {
      _localDocPaths = paths;
    });
  }

  void _saveLocalDocPath(String docType, String tempPath) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final File tempFile = File(tempPath);
      if (tempFile.existsSync()) {
        final String extension = tempPath.split('.').last;
        final String permanentPath = '${directory.path}/kyc_$docType.$extension';
        final File permanentFile = await tempFile.copy(permanentPath);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('kyc_path_$docType', permanentFile.path);
        setState(() {
          _localDocPaths[docType] = permanentFile.path;
        });
        debugPrint("KYC PREVIEW: Saved permanent document path: ${permanentFile.path}");
      }
    } catch (e) {
      debugPrint("KYC PREVIEW: Error saving document copy: $e");
    }
  }

  void _showDocumentUploadDialog(String label, String docType) {
    XFile? selectedFile;
    bool isUploading = false;
    final numberController = TextEditingController(
      text: docType == 'gst_certificate' 
          ? (_profile['gst_number'] ?? '') 
          : (docType == 'pan_card' 
              ? (_profile['pan_number'] ?? '') 
              : (docType == 'ownership_proof' ? (_profile['aadhaar_number'] ?? '') : ''))
    );

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text("Upload $label", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
              content: SizedBox(
                width: 320,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Please upload the official $label for verification:", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                    const SizedBox(height: 16),
                    if (selectedFile == null)
                      InkWell(
                        onTap: () async {
                          final ImagePicker picker = ImagePicker();
                          final XFile? file = await picker.pickImage(source: ImageSource.gallery);
                          if (file != null) {
                            setDialogState(() {
                              selectedFile = file;
                            });
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.cloud_upload_outlined, size: 36, color: AppColors.pink),
                              const SizedBox(height: 8),
                              Text("Select document from gallery", style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.w600, fontSize: 13)),
                              const SizedBox(height: 4),
                              Text("Supports PNG, JPG, PDF up to 5MB", style: TextStyle(color: isDark ? Colors.white30 : Colors.grey, fontSize: 11)),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.pink.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.pink.withOpacity(0.2)),
                        ),
                        child: Column(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(selectedFile!.path),
                                width: double.infinity,
                                height: 120,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.insert_drive_file_rounded, size: 24, color: AppColors.pink),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedFile!.name,
                                        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        "Document Selected",
                                        style: TextStyle(color: isDark ? Colors.white60 : Colors.grey, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                  onPressed: () {
                                    setDialogState(() {
                                      selectedFile = null;
                                    });
                                  },
                                )
                              ],
                            ),
                          ],
                        ),
                      ),
                    if (docType == 'gst_certificate' || docType == 'pan_card' || docType == 'ownership_proof') ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: numberController,
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                        keyboardType: docType == 'ownership_proof' ? TextInputType.number : TextInputType.text,
                        maxLength: docType == 'ownership_proof' ? 12 : (docType == 'pan_card' ? 10 : 15),
                        decoration: InputDecoration(
                          labelText: docType == 'gst_certificate' 
                              ? "GST Number (15-digit)" 
                              : (docType == 'pan_card' ? "PAN Number (10-digit)" : "Aadhaar Number (12-digit)"),
                          labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                          counterText: "",
                        ),
                        textCapitalization: docType == 'ownership_proof' ? TextCapitalization.none : TextCapitalization.characters,
                      ),
                    ],
                  ],
                ),
              ),
            ),
              actions: [
                TextButton(
                  onPressed: isUploading ? null : () => Navigator.pop(dialogCtx),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isUploading || selectedFile == null
                      ? null
                      : () async {
                          final String docNum = numberController.text.trim();
                          if ((docType == 'gst_certificate' || docType == 'pan_card' || docType == 'ownership_proof') && docNum.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Please enter your ${docType == 'gst_certificate' ? "GST" : (docType == 'pan_card' ? "PAN" : "Aadhaar")} number'), 
                                backgroundColor: Colors.redAccent
                              ),
                            );
                            return;
                          }
                          if (docType == 'ownership_proof' && docNum.length != 12) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid 12-digit Aadhaar number'), backgroundColor: Colors.redAccent),
                            );
                            return;
                          }
                          setDialogState(() => isUploading = true);
                          try {
                            final uploadRes = await ApiService.uploadFile(selectedFile!.path);
                            if (uploadRes['success'] == true) {
                              final fileUrl = uploadRes['data']['url'];
                              final res = await ApiService.submitPartnerKyc(
                                docType, 
                                fileUrl,
                                gstNumber: docType == 'gst_certificate' ? docNum.toUpperCase() : null,
                                panNumber: docType == 'pan_card' ? docNum.toUpperCase() : null,
                                aadhaarNumber: docType == 'ownership_proof' ? docNum : null,
                              );
                              if (res['success'] == true) {
                                if (mounted) {
                                  Navigator.pop(dialogCtx);
                                  _loadProfile();
                                  _saveLocalDocPath(docType, selectedFile!.path);
                                  _showCenteredSuccessPop(
                                    "$label Submitted", 
                                    "Your document has been submitted successfully and is currently under review by our admin team."
                                  );
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(res['message'] ?? 'Failed to submit document'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            } else {
                              if (mounted) {
                                final errMsg = uploadRes['error']?['message'] ?? uploadRes['message'] ?? 'Failed to upload document';
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(errMsg), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } finally {
                            setDialogState(() => isUploading = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
                  child: isUploading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Submit", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCenteredSuccessPop(String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: GlassContainer(
            radius: 24,
            padding: const EdgeInsets.all(24),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFF3DDC84),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.white),
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.pink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Done", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackTemplate(String docTypeLower) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (docTypeLower.contains('pan')) {
      return Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F5A84), Color(0xFF063A58)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("आयकर विभाग", style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                      Text("INCOME TAX DEPARTMENT", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text("GOVT. OF INDIA", style: TextStyle(color: Colors.amber, fontSize: 7, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Icon(Icons.person, color: Colors.white30, size: 36),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("NAME / नाम", style: TextStyle(color: Colors.white54, fontSize: 8)),
                      Text(_profile['email'] != null ? _profile['email'].split('@')[0].replaceAll(RegExp(r'[0-9]'), '').toUpperCase() : 'RAJESH SHARMA', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text("PERMANENT ACCOUNT NUMBER / खाता संख्या", style: TextStyle(color: Colors.white54, fontSize: 8)),
                      const Text("ABCDE1234F", style: TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("CARD TYPE: INDIVIDUAL", style: TextStyle(color: Colors.white30, fontSize: 8)),
                Container(
                  width: 80,
                  height: 16,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white54, style: BorderStyle.solid)),
                  ),
                  child: const Center(
                    child: Text("Signature", style: TextStyle(color: Colors.white30, fontSize: 8, fontStyle: FontStyle.italic)),
                  ),
                ),
              ],
            )
          ],
        ),
      );
    }

    if (docTypeLower.contains('gst') || docTypeLower.contains('cert')) {
      return Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFC5A880), width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            const Text("FORM GST REG-06", style: TextStyle(color: Color(0xFF333333), fontSize: 8, fontWeight: FontWeight.bold)),
            const Text("GOVERNMENT OF INDIA", style: TextStyle(color: Color(0xFFC5A880), fontSize: 10, fontWeight: FontWeight.bold)),
            const Text("CERTIFICATE OF REGISTRATION", style: TextStyle(color: Color(0xFF333333), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            const SizedBox(height: 8),
            Container(height: 1, color: const Color(0xFFC5A880)),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFC5A880), width: 1.5),
                    ),
                    child: const Center(child: Icon(Icons.gavel_rounded, color: Color(0xFFC5A880), size: 24)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Registration Number: 24ABCDE1234F1Z5", style: TextStyle(color: Colors.black87, fontSize: 8, fontWeight: FontWeight.bold)),
                        SizedBox(height: 4),
                        Text("Legal Name: SUNSET SPORTS COMPLEX", style: TextStyle(color: Colors.black54, fontSize: 7)),
                        SizedBox(height: 2),
                        Text("Jurisdiction: State Tax Department, Gujarat", style: TextStyle(color: Colors.black54, fontSize: 7)),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: const Color(0xFFC5A880)),
            const SizedBox(height: 4),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Date of Issue: 12/01/2026", style: TextStyle(color: Colors.black38, fontSize: 8)),
                Text("Approved by Authority", style: TextStyle(color: Color(0xFF3DDC84), fontSize: 8, fontWeight: FontWeight.bold)),
              ],
            )
          ],
        ),
      );
    }

    if (docTypeLower.contains('cheque')) {
      return Container(
        width: double.infinity,
        height: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFE3F2FD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF90CAF9), width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("STATE BANK OF INDIA", style: TextStyle(color: Color(0xFF0D47A1), fontSize: 12, fontWeight: FontWeight.bold)),
                    Text("Date: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}", style: TextStyle(color: Colors.black87, fontSize: 9)),
                  ],
                ),
                Text("IFS CODE: SBIN0001234", style: TextStyle(color: Colors.black54, fontSize: 8)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text("PAY TO: ", style: TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold)),
                    Container(
                      width: 180,
                      height: 1,
                      color: Colors.grey[400],
                    )
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text("RUPEES: ", style: TextStyle(color: Colors.black87, fontSize: 10, fontWeight: FontWeight.bold)),
                        Container(width: 140, height: 1, color: Colors.grey[400]),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                      ),
                      child: const Text("₹  N/A", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const Spacer(),
                const Center(
                  child: Text("⑈012345⑈ 382002002⑆ 000123⑈ 10", style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.black87, letterSpacing: 1.5)),
                )
              ],
            ),
            Center(
              child: Transform.rotate(
                angle: -0.25,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.redAccent.withOpacity(0.8), width: 3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "CANCELLED",
                    style: TextStyle(color: Colors.redAccent, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: 2),
                  ),
                ),
              ),
            )
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_turned_in, size: 48, color: AppColors.pink),
          const SizedBox(height: 12),
          Text(
            docTypeLower.replaceAll('_', ' ').toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            "OFFICIAL VERIFIED AGREEMENT & LICENSE DOCUMENT",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 10),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified, size: 14, color: const Color(0xFF3DDC84)),
              const SizedBox(width: 6),
              const Text("SECURE BLOCKCHAIN HASHED", style: TextStyle(color: Color(0xFF3DDC84), fontSize: 9, fontWeight: FontWeight.bold)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildDocumentPreview(String docType, String fileUrl) {
    final docTypeLower = docType.toLowerCase();
    
    // 1. Check if we have the actual uploaded local image file!
    final localPath = _localDocPaths[docType];
    debugPrint("KYC PREVIEW: docType=$docType, localPath=$localPath");
    if (localPath != null && localPath.isNotEmpty) {
      final file = File(localPath);
      debugPrint("KYC PREVIEW: File exists = ${file.existsSync()}");
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(
              maxHeight: 400,
            ),
            color: Colors.black12,
            child: Image.file(
              file,
              fit: BoxFit.contain,
            ),
          ),
        );
      }
    }
    
    // 2. Map mock URLs to realistic public images so they always see an actual photographic image
    String effectiveUrl = fileUrl;
    if (fileUrl.startsWith('/uploads')) {
      final serverBase = ApiService.activeUrl.replaceAll('/api', '');
      effectiveUrl = '$serverBase$fileUrl';
    } else if (fileUrl.contains('mock-s3-bucket') || fileUrl.isEmpty) {
      if (docTypeLower.contains('pan')) {
        effectiveUrl = 'https://images.unsplash.com/photo-1593085512500-5d55148d6f0d?w=600&auto=format&fit=crop';
      } else if (docTypeLower.contains('gst') || docTypeLower.contains('cert')) {
        effectiveUrl = 'https://images.unsplash.com/photo-1554415707-6e8cfc93fe23?w=600&auto=format&fit=crop';
      } else if (docTypeLower.contains('cheque')) {
        effectiveUrl = 'https://images.unsplash.com/photo-1628157582853-a796fa650a6a?w=600&auto=format&fit=crop';
      } else {
        effectiveUrl = 'https://images.unsplash.com/photo-1450133064473-71024230f91b?w=600&auto=format&fit=crop';
      }
    }
    
    // 3. Render the network image
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(
          maxHeight: 400,
        ),
        color: Colors.black12,
        child: Image.network(
          effectiveUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallbackTemplate(docTypeLower),
        ),
      ),
    );
  }

  void _showViewAllDocumentsDialog() {
    final documents = _profile['partner_documents'] as List<dynamic>? ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Uploaded Documents", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          content: Container(
            width: double.maxFinite,
            constraints: const BoxConstraints(maxHeight: 320),
            child: documents.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.0),
                    child: Text("No documents have been uploaded yet.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: documents.length,
                    separatorBuilder: (context, index) => const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final doc = documents[index];
                      final docType = doc['document_type'] as String;
                      final fileUrl = doc['file_url'] as String;
                      final status = (doc['status'] as String).toUpperCase();

                      IconData getIcon() {
                        if (docType.contains('cert') || docType.contains('license')) {
                          return Icons.assignment_outlined;
                        }
                        if (docType.contains('pan')) {
                          return Icons.badge_outlined;
                        }
                        return Icons.insert_drive_file_outlined;
                      }

                      Color getStatusColor() {
                        if (status == "APPROVED" || status == "VERIFIED" || status == "SIGNED") return const Color(0xFF3DDC84);
                        if (status == "PENDING") return const Color(0xFFFFB03A);
                        return Colors.redAccent;
                      }

                      String formatDocName(String type) {
                        return type.replaceAll('_', ' ').toUpperCase();
                      }

                      Widget buildLeading() {
                        final localPath = _localDocPaths[docType];
                        if (localPath != null && localPath.isNotEmpty && File(localPath).existsSync()) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(localPath),
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                            ),
                          );
                        }
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.pink.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(getIcon(), color: AppColors.pink, size: 20),
                        );
                      }

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: buildLeading(),
                        title: Text(formatDocName(docType), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: getStatusColor().withOpacity(0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(status, style: TextStyle(color: getStatusColor(), fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        trailing: ElevatedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) {
                                return AlertDialog(
                                  backgroundColor: isDark ? AppColors.surface : Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: Text(formatDocName(docType)),
                                  content: SizedBox(
                                    width: 320,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _buildDocumentPreview(docType, fileUrl),
                                      ],
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Close"),
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.pink.withOpacity(0.2),
                            foregroundColor: AppColors.pink,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text("View", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Done", style: TextStyle(color: Colors.grey)),
            ),
          ],
        );
      },
    );
  }

  void _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.getProfile();
      final data = res['data'] ?? {};
      
      final settingsRes = await ApiService.getSettings();
      final settings = settingsRes['data'] ?? {};

      setState(() {
        _profile = data;
        _systemSettings = settings;
        _isLoading = false;
      });
      if (data['fcm_token'] == null) {
        await ApiService.updateProfile(fcmToken: "mock_partner_fcm_token_dev");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showActionDialog("Error Loading Profile", "Failed to retrieve profile data: $e");
    }
  }

  void _showEditProfileDialog() {
    final phoneController = TextEditingController(text: _profile['phone_number'] ?? '');
    final emailController = TextEditingController(text: _profile['email'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text("Edit Partner Details", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: phoneController,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                    decoration: const InputDecoration(
                      labelText: "Phone Number",
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                    decoration: const InputDecoration(
                      labelText: "Email Address",
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          setDialogState(() => isSaving = true);
                          try {
                            final res = await ApiService.updateProfile(
                              phoneNumber: phoneController.text.trim(),
                              email: emailController.text.trim(),
                            );
                            if (res['success'] == true) {
                              if (mounted) {
                                Navigator.pop(context);
                                _loadProfile();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Profile updated successfully'), backgroundColor: AppColors.success),
                                );
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res['message'] ?? 'Failed to update profile'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Save Changes", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChangePhotoUpload() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null) return;

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (spinnerCtx) => const Center(child: CircularProgressIndicator(color: AppColors.pink)),
      );

      final uploadRes = await ApiService.uploadFile(file.path);
      if (uploadRes['success'] == true) {
        final url = uploadRes['data']['url'];
        final res = await ApiService.updateProfile(avatarUrl: url);
        if (res['success'] == true) {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // Close spinner
            _loadProfile();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Profile photo updated successfully'), backgroundColor: AppColors.success),
            );
          }
        } else {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop(); // Close spinner
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res['message'] ?? 'Failed to update profile image'), backgroundColor: Colors.redAccent),
            );
          }
        }
      } else {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // Close spinner
          final errMsg = uploadRes['error']?['message'] ?? uploadRes['message'] ?? 'Failed to upload image';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errMsg), backgroundColor: Colors.redAccent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // Close spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showChangeMobileDialog() {
    final mobileController = TextEditingController(text: _profile['phone_number'] ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text("Change Mobile Number", style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: mobileController,
                    keyboardType: TextInputType.phone,
                    style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                    decoration: const InputDecoration(
                      labelText: "New Mobile Number",
                      labelStyle: TextStyle(color: Colors.grey),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final newMobile = mobileController.text.trim();
                          if (newMobile.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter a valid mobile number'), backgroundColor: Colors.redAccent),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);
                          try {
                            final res = await ApiService.updateProfile(
                              phoneNumber: newMobile,
                            );
                            if (res['success'] == true) {
                              if (mounted) {
                                Navigator.pop(context);
                                _loadProfile();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Mobile number updated successfully'), backgroundColor: AppColors.success),
                                );
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res['message'] ?? 'Failed to update mobile number'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } finally {
                            setDialogState(() => isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
                  child: isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Update Mobile", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showManageDevicesDialog() {
    List<Map<String, String>> mockDevices = [
      {'name': 'Android Emulator', 'type': 'Current Device', 'status': 'Active Now', 'lastActive': 'Active Now'},
      {'name': 'iPhone 15 Pro', 'type': 'iOS Mobile', 'status': 'Last active: 2 hours ago', 'lastActive': '2h'},
      {'name': 'Chrome Web (macOS)', 'type': 'Desktop Browser', 'status': 'Last active: Yesterday', 'lastActive': '1d'},
    ];

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Manage Devices", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "These devices are currently logged into your partner account. You can revoke access for any session.",
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    ...mockDevices.map((device) {
                      final isCurrent = device['type'] == 'Current Device';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              device['type']!.contains('Browser') ? Icons.computer_rounded : Icons.phone_android_rounded,
                              color: AppColors.pink,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    device['name']!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    device['status']!,
                                    style: TextStyle(
                                      color: isCurrent ? const Color(0xFF3DDC84) : Colors.grey,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isCurrent)
                              IconButton(
                                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
                                onPressed: () {
                                  setDialogState(() {
                                    mockDevices.remove(device);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Revoked access for ${device['name']}"),
                                      backgroundColor: Colors.redAccent,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showWebViewDialog(String title, String url) {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      launchUrl(Uri.parse(url));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(Uri.parse(url));

        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: 360,
            height: 500,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: WebViewWidget(controller: controller),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Done"),
            ),
          ],
        );
      },
    );
  }

  void _showHelpCenterDialog() {
    final List<Map<String, String>> faqs = [
      {
        'q': 'How do I list a new venue?',
        'a': 'Go to the Venues tab, click "Add Venue" at the top, fill in the details (name, sports types, pricing, amenities, images), and submit it. Our admin team will review and list it.'
      },
      {
        'q': 'When do settlements process?',
        'a': 'Payouts are automatically processed every Tuesday for all completed slot bookings from the previous week. You can track settlements in the Settlements tab.'
      },
      {
        'q': 'How do I complete KYC?',
        'a': 'Go to the Profile tab, scroll to KYC documents, and upload your GST certificate, PAN card, and business license. Verification takes 24-48 business hours.'
      },
      {
        'q': 'Can I customize court booking slots?',
        'a': 'Yes. You can manage slots and court configurations directly within each venue\'s setting by selecting custom times and base pricing.'
      },
    ];

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Help Center / FAQs", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SizedBox(
            width: 320,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: faqs.length,
              itemBuilder: (context, index) {
                return Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    title: Text(
                      faqs[index]['q']!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 8.0),
                        child: Text(
                          faqs[index]['a']!,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontSize: 12,
                          ),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _showContactSupportDialog() {
    final supportPhone = _systemSettings['supportPhone'] ?? "1800-284-5383";
    final supportEmail = _systemSettings['supportEmail'] ?? "support@athletepov.com";

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Contact Support", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Reach out to us via call or email. Our team is available Mon-Sat, 9:00 AM - 9:00 PM.",
                  style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.phone_in_talk_rounded, color: AppColors.pink),
                  title: const Text("Call Toll-Free", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(supportPhone, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.grey),
                    onPressed: () {
                      _copyToClipboard(supportPhone);
                    },
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline_rounded, color: AppColors.pink),
                  title: const Text("Email Us", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(supportEmail, style: const TextStyle(fontSize: 12)),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.grey),
                    onPressed: () {
                      _copyToClipboard(supportEmail);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  void _showRaiseTicketDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text("Raise Support Ticket", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                      decoration: const InputDecoration(
                        labelText: "Issue Title",
                        labelStyle: TextStyle(color: Colors.grey),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descController,
                      maxLines: 4,
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                      decoration: const InputDecoration(
                        labelText: "Describe your issue",
                        labelStyle: TextStyle(color: Colors.grey),
                        alignLabelWithHint: true,
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.pink)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final title = titleController.text.trim();
                          final desc = descController.text.trim();
                          if (title.isEmpty || desc.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please fill in all fields'), backgroundColor: Colors.redAccent),
                            );
                            return;
                          }
                          setDialogState(() => isSubmitting = true);
                          try {
                            final res = await ApiService.submitSupportTicket(title, desc);
                            if (res['success'] == true) {
                              if (mounted) {
                                Navigator.pop(context);
                                _showActionDialog("Ticket Submitted", "Your ticket has been logged successfully. Ticket ID: ${res['data']?['report_id']?.toString().substring(0, 8) ?? 'ST-9912'}\nOur team will contact you shortly.");
                              }
                            } else {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res['message'] ?? 'Failed to raise support ticket'), backgroundColor: Colors.redAccent),
                                );
                              }
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
                              );
                            }
                          } finally {
                            setDialogState(() => isSubmitting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
                  child: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Submit Ticket", style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _launchWhatsAppSupport() {
    final number = _systemSettings['supportWhatsapp'] ?? "9427961426";
    launchUrl(Uri.parse("https://wa.me/$number"));
  }

  void _launchCallSupport() {
    final number = _systemSettings['supportPhone'] ?? "9427961426";
    launchUrl(Uri.parse("tel:$number"));
  }

  void _showLiveChatDialog() {
    final List<Map<String, String>> chatMessages = [
      {'sender': 'bot', 'text': 'Hello! Thanks for contacting Athlete POV Partner Support. How can we help you today?'}
    ];
    final chatController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? AppColors.surface : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: AppColors.pink.withOpacity(0.12),
                    child: const Icon(Icons.support_agent_rounded, size: 16, color: AppColors.pink),
                  ),
                  const SizedBox(width: 8),
                  const Text("Live Support Chat", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 320,
                height: 400,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: chatMessages.length,
                        itemBuilder: (context, index) {
                          final msg = chatMessages[index];
                          final isBot = msg['sender'] == 'bot';
                          return Align(
                            alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isBot
                                    ? (isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))
                                    : AppColors.pink.withOpacity(0.15),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: isBot ? Radius.zero : const Radius.circular(12),
                                  bottomRight: isBot ? const Radius.circular(12) : Radius.zero,
                                ),
                              ),
                              child: Text(
                                msg['text']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(color: Colors.white10, height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: chatController,
                            style: TextStyle(fontSize: 12, color: isDark ? Colors.white : const Color(0xFF1A1A1A)),
                            decoration: const InputDecoration(
                              hintText: "Type your message...",
                              hintStyle: TextStyle(color: Colors.grey),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (value) {
                              if (value.trim().isEmpty) return;
                              final text = value.trim();
                              chatController.clear();
                              setDialogState(() {
                                chatMessages.add({'sender': 'user', 'text': text});
                              });
                              
                              // Trigger bot response logic
                              Future.delayed(const Duration(seconds: 1), () {
                                String reply = "I'm connecting you with a support representative. Please hold on...";
                                final txt = text.toLowerCase();
                                if (txt.contains('payment') || txt.contains('settle') || txt.contains('earnings')) {
                                  reply = "For payment and settlement inquiries, note that weekly payouts process automatically on Tuesdays. You can view settlements status under Settlements.";
                                } else if (txt.contains('kyc') || txt.contains('doc') || txt.contains('verification')) {
                                  reply = "KYC approvals are processed within 24-48 business hours. Ensure your GST and PAN documents are clearly visible in the preview.";
                                } else if (txt.contains('venue') || txt.contains('court') || txt.contains('add')) {
                                  reply = "To add or update sports venues, tap Venues -> Add Venue. Changes are typically approved in less than 24 hours.";
                                } else if (txt.contains('hello') || txt.contains('hi')) {
                                  reply = "Hello! How can we assist you with Athlete POV Partner platform today?";
                                }
                                setDialogState(() {
                                  chatMessages.add({'sender': 'bot', 'text': reply});
                                });
                              });
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send_rounded, color: AppColors.pink, size: 20),
                          onPressed: () {
                            final text = chatController.text.trim();
                            if (text.isEmpty) return;
                            chatController.clear();
                            setDialogState(() {
                              chatMessages.add({'sender': 'user', 'text': text});
                            });
                            
                            Future.delayed(const Duration(seconds: 1), () {
                              String reply = "I'm connecting you with a support representative. Please hold on...";
                              final txt = text.toLowerCase();
                              if (txt.contains('payment') || txt.contains('settle') || txt.contains('earnings')) {
                                reply = "For payment and settlement inquiries, note that weekly payouts process automatically on Tuesdays. You can view settlements status under Settlements.";
                              } else if (txt.contains('kyc') || txt.contains('doc') || txt.contains('verification')) {
                                reply = "KYC approvals are processed within 24-48 business hours. Ensure your GST and PAN documents are clearly visible in the preview.";
                              } else if (txt.contains('venue') || txt.contains('court') || txt.contains('add')) {
                                reply = "To add or update sports venues, tap Venues -> Add Venue. Changes are typically approved in less than 24 hours.";
                              } else if (txt.contains('hello') || txt.contains('hi')) {
                                reply = "Hello! How can we assist you with Athlete POV Partner platform today?";
                              }
                              setDialogState(() {
                                chatMessages.add({'sender': 'bot', 'text': reply});
                              });
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("End Chat", style: TextStyle(color: Colors.grey)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => SplashScreen(toggleTheme: widget.toggleTheme)),
      (route) => false,
    );
  }

  void _showActionDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          title: Text(title, style: TextStyle(color: isDark ? Colors.white : const Color(0xFF1A1A1A))),
          content: Text(message, style: TextStyle(color: isDark ? Colors.white70 : const Color(0xFF6B7280))),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK", style: TextStyle(color: AppColors.pink)),
            )
          ],
        );
      },
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Copied to clipboard: $text"),
        backgroundColor: AppColors.pink,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final secondaryTextColor = isDark ? const Color(0xFF9AA4B2) : const Color(0xFF6B7280);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _loadProfile();
          await Future.delayed(const Duration(milliseconds: 600));
        },
        color: AppColors.pink,
        child: (_isLoading && _profile.isEmpty)
            ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLoading && _profile.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12.0),
                      child: LinearProgressIndicator(color: AppColors.pink, backgroundColor: Colors.transparent),
                    ),

                  // Profile Header & Level Indicator
                  _buildProfileHeader(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 1. Partner Information Card (Top Card)
                  _buildPartnerCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 2. Business Information Card
                  _buildBusinessCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 3. KYC Status Card
                  _buildKycCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 4. Bank Details Card
                  _buildBankDetailsCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 5. Earnings Summary Card
                  _buildEarningsSummaryCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 6. Venue Information Card
                  _buildVenueInfoCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 7. Documents Card
                  _buildDocumentsCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 8. Notification Preferences Card
                  _buildNotificationPreferencesCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 9. Security Card
                  _buildSecurityCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 10. Support Card
                  _buildSupportCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 20),

                  // 11. App Preferences Card
                  _buildAppPreferencesCard(isDark, textColor, secondaryTextColor),
                  const SizedBox(height: 24),

                  // 12. Logout Card
                  _buildLogoutCard(isDark),
                  const SizedBox(height: 24),

                  // 13. Delete Account Action
                  _buildDeleteAccountButton(textColor),
                  const SizedBox(height: 110),
                ],
              ),
            ),
      ),
    );
  }

  // --- WIDGET BUILDERS ---

  Widget _buildProfileHeader(bool isDark, Color textColor, Color secondaryTextColor) {
    final String businessName = _profile['venues'] != null && (_profile['venues'] as List).isNotEmpty
        ? _profile['venues'][0]['name']
        : (_profile['email'] != null ? _profile['email'].split('@')[0].toUpperCase() : 'Sunset Sports Arena');

    final kycStatus = _profile['kyc_status'] ?? 'unverified';
    final bool isVerified = kycStatus == 'verified';
    final bool isPending = kycStatus == 'pending';
    final int completedCount = 1 + (isVerified || isPending ? 1 : 0) + (isVerified ? 1 : 0) + (isVerified ? 1 : 0);
    final double progressVal = completedCount / 4.0;
    final String progressPct = "${(progressVal * 100).toInt()}%";

    final String planTier = (_profile['plan_tier'] as String? ?? 'free').toLowerCase();
    String tier = "Bronze Partner";
    String badge = "🥉";
    if (planTier == 'enterprise') {
      tier = "Platinum Partner";
      badge = "💎";
    } else if (planTier == 'premium') {
      tier = "Gold Partner";
      badge = "🥇";
    } else {
      tier = "Bronze Partner";
      badge = "🥉";
    }

    final createdYear = _profile['created_at'] != null 
        ? DateTime.parse(_profile['created_at']).year.toString() 
        : "2025";

    String? avatarUrl = _profile['avatar_url'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      if (avatarUrl.startsWith('/uploads')) {
        final serverBase = ApiService.activeUrl.replaceAll('/api', '');
        avatarUrl = '$serverBase$avatarUrl';
      }
    }

    return GlassContainer(
      radius: 24,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _showChangePhotoUpload,
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 36,
                      backgroundColor: AppColors.pink.withOpacity(0.2),
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? null
                          : const Icon(Icons.person, size: 36, color: AppColors.pink),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.pink,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            businessName,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (kycStatus == 'verified' ? const Color(0xFF3DDC84) : const Color(0xFFFFB03A)).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            kycStatus.toUpperCase(),
                            style: TextStyle(
                              color: kycStatus == 'verified' ? const Color(0xFF3DDC84) : const Color(0xFFFFB03A), 
                              fontSize: 8, 
                              fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Partner Level: $badge $tier",
                      style: TextStyle(fontSize: 12, color: AppColors.purple, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Partner ID: ${_profile['partner_id']?.toString().substring(0, 8).toUpperCase() ?? 'APV-PARTNER-8823'}",
                      style: TextStyle(fontSize: 11, color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 16, color: AppColors.pink),
                onPressed: () => _copyToClipboard(_profile['partner_id'] ?? "APV-PARTNER-8823"),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Profile Completion: $progressPct", style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600)),
              Text("Member Since: $createdYear", style: TextStyle(fontSize: 11, color: secondaryTextColor)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progressVal,
              backgroundColor: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.pink),
              minHeight: 6,
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPartnerCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final String businessName = _profile['venues'] != null && (_profile['venues'] as List).isNotEmpty
        ? (_profile['venues'][0]['name'] ?? 'n/a')
        : 'n/a';

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("PARTNER INFORMATION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.pink.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  "🏢 Venue Partner",
                  style: TextStyle(color: AppColors.pink, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.business_center, businessName, textColor),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.phone, _profile['phone_number'] ?? "+91 93134 57713", textColor),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.email, _profile['email'] ?? "partner@email.com", textColor),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.location_on, _profile['venues'] != null && (_profile['venues'] as List).isNotEmpty ? (_profile['venues'][0]['address'] ?? 'n/a') : 'n/a', textColor),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _showEditProfileDialog,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.pink,
                    side: const BorderSide(color: AppColors.pink),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Edit Profile"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _showChangePhotoUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pink,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Upload Photo"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBusinessCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final String businessName = _profile['venues'] != null && (_profile['venues'] as List).isNotEmpty
        ? (_profile['venues'][0]['name'] ?? 'n/a')
        : 'n/a';

    final createdDate = _profile['created_at'] != null 
        ? DateTime.tryParse(_profile['created_at']) 
        : null;
    final List<String> months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final String memberSinceDate = createdDate != null 
        ? "${months[createdDate.month - 1]} ${createdDate.year}" 
        : "Jan 2026";


    final documents = _profile['partner_documents'] as List<dynamic>? ?? [];
    final gstDoc = documents.firstWhere((d) => d['document_type'] == 'gst_certificate', orElse: () => null);
    final panDoc = documents.firstWhere((d) => d['document_type'] == 'pan_card', orElse: () => null);
    final aadhaarDoc = documents.firstWhere((d) => d['document_type'] == 'ownership_proof', orElse: () => null);

    final String gstVal = _profile['gst_number'] ?? (gstDoc != null 
        ? (gstDoc['status'] == 'verified' ? "24ABCDE1234F1Z5" : "Verification ${gstDoc['status']}") 
        : "not avl");

    final String panVal = _profile['pan_number'] ?? (panDoc != null 
        ? (panDoc['status'] == 'verified' ? "ABCDE1234F" : "Verification ${panDoc['status']}") 
        : "not avl");

    final String aadhaarVal = _profile['aadhaar_number'] ?? (aadhaarDoc != null 
        ? (aadhaarDoc['status'] == 'verified' ? "123456789012" : "Verification ${aadhaarDoc['status']}") 
        : "not avl");

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("BUSINESS INFORMATION", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 16),
          _buildDetailTile("Venue Name", businessName, secondaryTextColor, textColor),
          _buildDetailTile("Business Type", _profile['venues'] != null && (_profile['venues'] as List).isNotEmpty && (_profile['venues'][0]['sport_types'] as List).isNotEmpty ? ((_profile['venues'][0]['sport_types'] as List).join(' & ') + ' Complex') : 'n/a', secondaryTextColor, textColor),
          _buildDetailTile("GST Number", gstVal, secondaryTextColor, textColor),
          _buildDetailTile("PAN Number", panVal, secondaryTextColor, textColor),
          _buildDetailTile("Aadhaar Number", aadhaarVal, secondaryTextColor, textColor),
          _buildDetailTile("Owner Name", _profile['email'] != null ? _profile['email'].split('@')[0].replaceAll(RegExp(r'[0-9]'), '').toUpperCase() : 'RAJESH SHARMA', secondaryTextColor, textColor),
          _buildDetailTile("Plan Tier", (_profile['plan_tier'] ?? 'free').toUpperCase(), secondaryTextColor, textColor),
          _buildDetailTile("Member Since", memberSinceDate, secondaryTextColor, textColor),
        ],
      ),
    );
  }

  Widget _buildKycCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final kycStatus = _profile['kyc_status'] ?? 'unverified';
    final isVerified = kycStatus == 'verified';
    final isPending = kycStatus == 'pending';

    final documents = _profile['partner_documents'] as List<dynamic>? ?? [];
    bool isDocVerified(String docType) {
      final doc = documents.firstWhere((d) => d['document_type'] == docType, orElse: () => null);
      if (doc == null) return false;
      final status = (doc['status'] as String).toLowerCase();
      return status == 'verified' || status == 'approved';
    }

    final bool isAadhaarCheck = isDocVerified('ownership_proof');
    final bool isPanCheck = isDocVerified('pan_card');
    final bool isGstCheck = isDocVerified('gst_certificate');
    final bool isBankCheck = isDocVerified('cancelled_cheque');

    int completedCount = 0;
    if (isAadhaarCheck) completedCount++;
    if (isPanCheck) completedCount++;
    if (isGstCheck) completedCount++;
    if (isBankCheck) completedCount++;

    final String progressPct = "${(completedCount / 4.0 * 100).toInt()}%";

    final String kycMsg = isVerified
        ? "All documents are approved. Profile verification is $progressPct complete."
        : (isPending
            ? "Verification is in progress ($progressPct Complete). GST and Bank verification pending."
            : "Verification is incomplete ($progressPct Complete). Please submit your KYC documents.");

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("KYC STATUS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
              Text(
                "Overall: ${kycStatus.toUpperCase()}", 
                style: TextStyle(
                  color: isVerified 
                      ? const Color(0xFF3DDC84) 
                      : (isPending ? const Color(0xFFFFB03A) : Colors.redAccent), 
                  fontSize: 12, 
                  fontWeight: FontWeight.bold
                )
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKycCheckItem("Aadhaar", isAadhaarCheck),
              _buildKycCheckItem("PAN", isPanCheck),
              _buildKycCheckItem("GST", isGstCheck),
              _buildKycCheckItem("Bank", isBankCheck),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isVerified ? const Color(0xFF3DDC84) : const Color(0xFFFFB03A)).withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (isVerified ? const Color(0xFF3DDC84) : const Color(0xFFFFB03A)).withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(
                  isVerified ? Icons.check_circle_outline_rounded : Icons.pending_actions_rounded, 
                  color: isVerified ? const Color(0xFF3DDC84) : const Color(0xFFFFB03A), 
                  size: 20
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    kycMsg,
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : const Color(0xFF1A1A1A)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankDetailsCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final bankStatus = _profile['bank_status'] ?? 'unverified';
    final bankName = _profile['bank_name'] ?? '';
    final bankAccountNo = _profile['bank_account_no'] ?? '';
    final bankIfsc = _profile['bank_ifsc'] ?? '';
    
    final bool hasBank = bankAccountNo.isNotEmpty;
    
    String displayAcc = "Account: not avl";
    if (hasBank) {
      displayAcc = bankAccountNo.length > 4 
          ? "Account: XXXXXXXX${bankAccountNo.substring(bankAccountNo.length - 4)}"
          : "Account: $bankAccountNo";
    }

    Color badgeColor = Colors.redAccent;
    String badgeText = "Incomplete";
    if (bankStatus == 'approved') {
      badgeColor = const Color(0xFF3DDC84);
      badgeText = "Primary";
    } else if (bankStatus == 'pending') {
      badgeColor = Colors.amber;
      badgeText = "Pending Review";
    }

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("BANK ACCOUNT DETAILS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
              IconButton(
                icon: const Icon(Icons.edit, size: 16, color: AppColors.pink),
                onPressed: _showBankEditDialog,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.pink.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_rounded, color: AppColors.pink, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hasBank ? bankName : "not avl", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor)),
                    const SizedBox(height: 2),
                    Text(
                      displayAcc, 
                      style: TextStyle(color: secondaryTextColor, fontSize: 13)
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText, 
                  style: TextStyle(
                    color: badgeColor, 
                    fontSize: 10, 
                    fontWeight: FontWeight.bold
                  )
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildDetailTile("IFSC Code", hasBank ? bankIfsc : "not avl", secondaryTextColor, textColor),
          if (bankStatus == 'pending') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 14),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      "Your edit is pending admin review. The original details remain active.",
                      style: TextStyle(color: Colors.amber, fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showBankEditDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final currentBankName = _profile['bank_name'] ?? '';
    final currentBankAccountNo = _profile['bank_account_no'] ?? '';
    final currentBankIfsc = _profile['bank_ifsc'] ?? '';
    
    final bankNameController = TextEditingController(text: currentBankName);
    final bankAccountController = TextEditingController(text: currentBankAccountNo);
    final bankIfscController = TextEditingController(text: currentBankIfsc);
    
    final isFirstTime = currentBankAccountNo.isEmpty;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.surface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            isFirstTime ? "Add Bank Details" : "Edit Bank Details",
            style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isFirstTime) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Updates require admin approval before going live.",
                            style: TextStyle(color: Colors.amber, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                TextField(
                  controller: bankNameController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: "Bank Name",
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    hintText: "E.g., HDFC Bank",
                    hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bankAccountController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: "Account Number",
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    hintText: "E.g., 5010012345678",
                    hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bankIfscController,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: InputDecoration(
                    labelText: "IFSC Code",
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
                    hintText: "E.g., HDFC0000123",
                    hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = bankNameController.text.trim();
                final acc = bankAccountController.text.trim();
                final ifsc = bankIfscController.text.trim();
                
                if (name.isEmpty || acc.isEmpty || ifsc.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("All fields are required.")),
                  );
                  return;
                }
                
                Navigator.pop(dialogCtx); // Close input fields
                
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (spinnerCtx) => const Center(child: CircularProgressIndicator(color: AppColors.pink)),
                );
                
                final response = await ApiService.updateProfile(
                  bankName: name,
                  bankAccountNo: acc,
                  bankIfsc: ifsc,
                );
                
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop(); // Close spinner
                }
                
                if (response['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isFirstTime 
                            ? "Bank account saved successfully!" 
                            : "Changes submitted for admin approval."
                      ),
                    ),
                  );
                  _loadProfile();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(response['message'] ?? 'Failed to update bank details.')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.pink),
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEarningsSummaryCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final earnings = double.tryParse(_profile['total_earnings']?.toString() ?? '0') ?? 0.0;

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("EARNINGS SUMMARY", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildEarningCol("Lifetime", "₹${earnings.toStringAsFixed(0)}", textColor, secondaryTextColor),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 40, color: Colors.white10),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEarningCol("This Month", "₹${(earnings * 0.15).toStringAsFixed(0)}", AppColors.pink, secondaryTextColor),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 40, color: Colors.white10),
              const SizedBox(width: 8),
              Expanded(
                child: _buildEarningCol("Pending", "₹${(earnings * 0.05).toStringAsFixed(0)}", AppColors.purple, secondaryTextColor),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVenueInfoCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final venues = _profile['venues'] as List<dynamic>? ?? [];

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("YOUR VENUES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
              InkWell(
                onTap: () {
                  _showActionDialog("Add Venue", "Redirecting to Venues creator...");
                },
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 16, color: AppColors.pink),
                    Text("Add Venue", style: TextStyle(color: AppColors.pink, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (venues.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Text("No venues registered yet. Click 'Add Venue' above to list one.", style: TextStyle(color: secondaryTextColor, fontSize: 13)),
            )
          else
            ...venues.map((v) {
              final List<dynamic> sports = v['sport_types'] ?? [];
              final String sportsStr = sports.isNotEmpty ? sports.join(", ") : "Sports Arena";
              return _buildVenueTile(Icons.sports_soccer_rounded, v['name'] ?? 'Facility', sportsStr, textColor, secondaryTextColor);
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildDocumentsCard(bool isDark, Color textColor, Color secondaryTextColor) {
    final documents = _profile['partner_documents'] as List<dynamic>? ?? [];

    String getDocStatus(String docType) {
      final doc = documents.firstWhere((d) => d['document_type'] == docType, orElse: () => null);
      if (doc == null) return "NOT UPLOADED";
      return (doc['status'] as String).toUpperCase();
    }

    Color getStatusColor(String status) {
      if (status == "APPROVED" || status == "VERIFIED" || status == "SIGNED") {
        return const Color(0xFF3DDC84);
      } else if (status == "PENDING" || status == "PENDING SIGNATURE") {
        return const Color(0xFFFFB03A);
      } else if (status == "REJECTED") {
        return Colors.redAccent;
      }
      return Colors.grey;
    }

    final gstStatus = getDocStatus('gst_certificate');
    final panStatus = getDocStatus('pan_card');
    final licenseStatus = getDocStatus('ownership_proof');
    final chequeStatus = getDocStatus('cancelled_cheque');
    final agreementStatus = getDocStatus('agreement');

    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("DOCUMENTS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
              GestureDetector(
                onTap: _showViewAllDocumentsDialog,
                child: const Text("View All", style: TextStyle(color: AppColors.pink, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildDocRow("GST Certificate", "gst_certificate", gstStatus, textColor, getStatusColor(gstStatus)),
          _buildDocRow("PAN Card", "pan_card", panStatus, textColor, getStatusColor(panStatus)),
          _buildDocRow("Aadhaar Card", "ownership_proof", licenseStatus, textColor, getStatusColor(licenseStatus)),
          _buildDocRow("Cancelled Cheque", "cancelled_cheque", chequeStatus, textColor, getStatusColor(chequeStatus)),
          _buildDocRow("Agreement", "agreement", agreementStatus, textColor, getStatusColor(agreementStatus)),
        ],
      ),
    );
  }

  Widget _buildNotificationPreferencesCard(bool isDark, Color textColor, Color secondaryTextColor) {
    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("NOTIFICATION PREFERENCES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 12),
          _buildSwitchRow("Booking Alerts", "Receive instant notifications for bookings", _bookingAlerts, (val) async {
            setState(() => _bookingAlerts = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('booking_alerts', val);
          }, textColor, secondaryTextColor),
          const SizedBox(height: 8),
          _buildSwitchRow("Payments", "Alerts for settlements and payouts", _paymentsAlerts, (val) async {
            setState(() => _paymentsAlerts = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('payments_alerts', val);
          }, textColor, secondaryTextColor),
          const SizedBox(height: 8),
          _buildSwitchRow("Promotions", "Newsletters and partner campaigns", _promotionsAlerts, (val) async {
            setState(() => _promotionsAlerts = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('promotions_alerts', val);
          }, textColor, secondaryTextColor),
          const SizedBox(height: 8),
          _buildSwitchRow("Email Updates", "Receive weekly reporting emails", _emailUpdates, (val) async {
            setState(() => _emailUpdates = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('email_updates', val);
          }, textColor, secondaryTextColor),
        ],
      ),
    );
  }

  Widget _buildSecurityCard(bool isDark, Color textColor, Color secondaryTextColor) {
    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("SECURITY SETTINGS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 12),
          _buildSettingsActionTile(Icons.lock_reset_rounded, "Change Password", () {
            _showActionDialog("Passwordless Account", "Your partner account uses secure, passwordless OTP (One-Time Password) verification via your registered phone number. A password is not required to log in. You can configure Two-Factor Authentication below.");
          }, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.phone_iphone_rounded, "Change Mobile", _showChangeMobileDialog, textColor, secondaryTextColor),
          _buildSwitchRow("Two-Factor Authentication", "Secure account access via OTP tokens", _twoFactorEnabled, (val) async {
            setState(() => _twoFactorEnabled = val);
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('two_factor_enabled', val);
            if (mounted) {
              _showActionDialog("Two-Factor Auth", val ? "Two-Factor Auth has been enabled." : "Two-Factor Auth has been disabled.");
            }
          }, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.devices_rounded, "Manage Devices", _showManageDevicesDialog, textColor, secondaryTextColor),
        ],
      ),
    );
  }

  Widget _buildSupportCard(bool isDark, Color textColor, Color secondaryTextColor) {
    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("HELP & SUPPORT", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 12),
          _buildSettingsActionTile(Icons.help_outline_rounded, "Help Center / FAQs", _showHelpCenterDialog, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.support_agent_rounded, "Contact Support", _showContactSupportDialog, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.assignment_turned_in_rounded, "Raise Ticket", _showRaiseTicketDialog, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.chat_bubble_outline_rounded, "Live Chat", _showLiveChatDialog, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.phone_iphone_rounded, "WhatsApp Support", _launchWhatsAppSupport, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.phone_rounded, "Call Support", _launchCallSupport, textColor, secondaryTextColor),
        ],
      ),
    );
  }

  Widget _buildAppPreferencesCard(bool isDark, Color textColor, Color secondaryTextColor) {
    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("APP PREFERENCES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: secondaryTextColor, letterSpacing: 1)),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, color: AppColors.pink),
            title: Text(isDark ? "Dark Mode Active" : "Light Mode Active", style: TextStyle(color: textColor, fontSize: 14)),
            trailing: Switch(
              value: isDark,
              activeColor: AppColors.pink,
              onChanged: (val) => widget.toggleTheme(),
            ),
          ),
          _buildSettingsActionTile(Icons.language_rounded, "Language (English)", () {
            _showActionDialog("Select Language", "Available Languages:\n- English (Active)\n- Gujarati\n- Hindi");
          }, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.description_outlined, "Privacy Policy", () {
            _showWebViewDialog("Privacy Policy", _systemSettings['privacyPolicyUrl'] ?? "https://athletepov.com/privacy-policy");
          }, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.gavel_rounded, "Terms of Service", () {
            _showWebViewDialog("Terms of Service", _systemSettings['termsOfServiceUrl'] ?? "https://athletepov.com/terms-of-service");
          }, textColor, secondaryTextColor),
          _buildSettingsActionTile(Icons.star_outline_rounded, "Rate App", () {
            final String playStoreUrl = _systemSettings['playStoreUrl'] ?? "https://play.google.com/store/apps/details?id=com.athletepov.partner";
            final String appStoreUrl = _systemSettings['appStoreUrl'] ?? "https://apps.apple.com/app/athletepov-partner/id123456789";
            final String targetUrl = (!kIsWeb && Platform.isIOS) ? appStoreUrl : playStoreUrl;
            launchUrl(Uri.parse(targetUrl));
          }, textColor, secondaryTextColor),
          const SizedBox(height: 8),
          const Divider(color: Colors.white10),
          const SizedBox(height: 8),
          Center(
            child: Text("App Version: v${_systemSettings['partnerAppVersion'] ?? '1.0.24'} (Partner)", style: TextStyle(color: secondaryTextColor, fontSize: 11)),
          )
        ],
      ),
    );
  }

  Widget _buildLogoutCard(bool isDark) {
    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(8),
      border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
      gradient: LinearGradient(
        colors: [
          Colors.redAccent.withOpacity(0.12),
          Colors.redAccent.withOpacity(0.04),
        ],
      ),
      child: ListTile(
        leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
        title: const Text("Logout Session", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
        onTap: _logout,
      ),
    );
  }


  Widget _buildDeleteAccountButton(Color textColor) {
    return GlassContainer(
      radius: 20,
      padding: const EdgeInsets.all(8),
      border: Border.all(color: Colors.redAccent.withOpacity(0.15)),
      gradient: LinearGradient(
        colors: [
          Colors.redAccent.withOpacity(0.04),
          Colors.redAccent.withOpacity(0.01),
        ],
      ),
      child: ListTile(
        leading: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
        title: const Text("Delete Partner Account", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: const Text("Permanently remove all venues and slots data", style: TextStyle(color: Colors.redAccent, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.redAccent),
        onTap: () {
          showDialog(
            context: context,
            builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return AlertDialog(
                backgroundColor: isDark ? AppColors.surface : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text("Delete Account", style: TextStyle(color: Colors.redAccent)),
                content: const Text(
                  "Warning: This action is permanent and all associated venues, slots, and balance data will be immediately removed.",
                  style: TextStyle(color: Colors.redAccent),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(child: CircularProgressIndicator(color: AppColors.pink)),
                      );
                      
                      final response = await ApiService.deleteProfile();
                      
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                      
                      if (response['success'] == true) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('token');
                        
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Your account has been deleted successfully.')),
                          );
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => LoginScreen(toggleTheme: widget.toggleTheme),
                            ),
                            (route) => false,
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(response['message'] ?? 'Failed to delete account')),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                    child: const Text("Confirm Delete", style: TextStyle(color: Colors.white)),
                  )
                ],
              );
            },
          );
        },
      ),
    );
  }

  // --- HELPERS ---

  Widget _buildInfoRow(IconData icon, String text, Color textColor) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.pink),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: textColor, fontSize: 14))),
      ],
    );
  }

  Widget _buildDetailTile(String label, String value, Color labelColor, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: labelColor, fontSize: 13)),
          Text(value, style: TextStyle(color: valueColor, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildKycCheckItem(String title, bool isChecked) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isChecked 
                ? const Color(0xFF3DDC84).withOpacity(0.12)
                : Colors.redAccent.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isChecked ? Icons.check_rounded : Icons.close_rounded,
            color: isChecked ? const Color(0xFF3DDC84) : Colors.redAccent,
            size: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEarningCol(String title, String val, Color valColor, Color titleColor) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: titleColor, fontSize: 11)),
        const SizedBox(height: 6),
        Text(val, style: TextStyle(color: valColor, fontWeight: FontWeight.bold, fontSize: 16)),
      ],
    );
  }

  Widget _buildVenueTile(IconData icon, String name, String subtitle, Color textColor, Color secondaryTextColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.pink.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.pink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: secondaryTextColor, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 20),
        ],
      ),
    );
  }

  Widget _buildDocRow(String name, String docType, String status, Color textColor, Color statusColor) {
    final bool canUpload = status != "APPROVED";
    final bool isUploaded = status != "NOT UPLOADED";

    final documents = _profile['partner_documents'] as List<dynamic>? ?? [];
    final doc = documents.firstWhere((d) => d['document_type'] == docType, orElse: () => null);
    final String fileUrl = doc != null ? (doc['file_url'] as String? ?? '') : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                if (isUploaded && fileUrl.isNotEmpty) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  showDialog(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        backgroundColor: isDark ? AppColors.surface : Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        title: Text(name.toUpperCase()),
                        content: SizedBox(
                          width: 320,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildDocumentPreview(docType, fileUrl),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Close"),
                          ),
                        ],
                      );
                    },
                  );
                } else {
                  _showDocumentUploadDialog(name, docType);
                }
              },
              child: Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined, 
                    size: 18, 
                    color: isUploaded ? AppColors.pink : Colors.grey,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name, 
                      style: TextStyle(
                        color: textColor, 
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(status, style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
          if (canUpload) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showDocumentUploadDialog(name, docType),
              child: Container(
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.upload_file_rounded, size: 16, color: AppColors.pink),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSwitchRow(String title, String subtitle, bool val, ValueChanged<bool> onChange, Color textColor, Color secondaryTextColor) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: secondaryTextColor, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(
          value: val,
          activeColor: AppColors.pink,
          onChanged: onChange,
        ),
      ],
    );
  }

  Widget _buildSettingsActionTile(IconData icon, String title, VoidCallback onTap, Color textColor, Color secondaryTextColor) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.pink, size: 20),
      title: Text(title, style: TextStyle(color: textColor, fontSize: 14)),
      trailing: Icon(Icons.chevron_right_rounded, color: secondaryTextColor, size: 18),
      onTap: onTap,
    );
  }
}

// -------------------------------------------------------------
// Phone Collection Screen (Post-Login)
// -------------------------------------------------------------
class PhoneCollectionScreen extends StatefulWidget {
  final VoidCallback toggleTheme;
  const PhoneCollectionScreen({super.key, required this.toggleTheme});

  @override
  State<PhoneCollectionScreen> createState() => _PhoneCollectionScreenState();
}

class _PhoneCollectionScreenState extends State<PhoneCollectionScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;

  void _submitPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number')),
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      final profileRes = await ApiService.getProfile();
      if (profileRes['success'] == true) {
        final profile = profileRes['data'] ?? {};
        final email = profile['email'] ?? '';

        // For partner, email needs to be set too if it's currently null
        final updateRes = await ApiService.updateProfile(
          phoneNumber: phone,
          email: email.isEmpty ? profile['phone_number'] : email,
        );
        
        if (updateRes['success'] == true) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
            ),
          );
          return;
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(updateRes['error']?['message'] ?? 'Failed to update phone number')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load profile')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.phone_iphone, size: 60, color: AppColors.pink),
              const SizedBox(height: 20),
              const Text(
                "One Last Step!",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Please enter your phone number to complete onboarding",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.phone, color: AppColors.pink),
                  hintText: "Phone Number",
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitPhone,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.pink,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Submit", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
