import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'websocket_sync.dart';
import 'api_service.dart';

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

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> tabs = [
      HomeTab(toggleTheme: widget.toggleTheme),
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
  const HomeTab({super.key, required this.toggleTheme});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  List<dynamic> _venues = [];
  List<dynamic> _banners = [];
  String _selectedSport = "All";
  String _selectedCity = "Madhupura, Gujarat";
  bool _isLoading = true;
  List<dynamic> _notifications = [];

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
    _loadData();
  }

  void _loadData() async {
    _loadNotifications();
    setState(() => _isLoading = true);
    final bannerResponse = await ApiService.getBanners();
    final venueResponse = await ApiService.getVenues(sport: _selectedSport == "All" ? null : _selectedSport);
    setState(() {
      _banners = bannerResponse['data'] ?? [];
      _venues = venueResponse['data'] ?? [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF4B5563);

    return Scaffold(
      backgroundColor: context.bgCol,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textCol),
          onPressed: () {},
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_on, color: AppColors.pink, size: 18),
            const SizedBox(width: 4),
            DropdownButton<String>(
              value: _selectedCity,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: textCol, size: 18),
              style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: textCol),
              dropdownColor: context.cardCol,
              items: ["Madhupura, Gujarat", "Bengaluru", "Mumbai", "Delhi"].map((city) {
                return DropdownMenuItem(value: city, child: Text(city));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCity = val);
              },
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          Stack(
            children: [
              IconButton(
                icon: Icon(Icons.notifications, color: textCol),
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Good Morning 👋", style: GoogleFonts.sora(fontSize: 18, color: textCol)),
                  const SizedBox(height: 6),
                  Stack(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          "Let's Play",
                          style: GoogleFonts.sora(fontSize: 32, fontWeight: FontWeight.bold, color: textCol),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          height: 3,
                          width: 140,
                          decoration: BoxDecoration(
                            gradient: AppColors.brandGradient,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text("Find your perfect turf today", style: GoogleFonts.sora(color: subtextCol, fontSize: 13)),
                  const SizedBox(height: 16),
                  
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Text("☁️", style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 4),
                            Text("25°C Cool Breeze 🍃", style: GoogleFonts.sora(fontSize: 11, color: textCol)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.navigation, color: Colors.deepOrangeAccent, size: 12),
                            const SizedBox(width: 4),
                            Text("Near You", style: GoogleFonts.sora(fontSize: 11, color: textCol)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  TextField(
                    style: GoogleFonts.sora(color: textCol, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: "Search venues, sports or areas...",
                      hintStyle: GoogleFonts.sora(color: Colors.grey),
                      prefixIcon: const Icon(Icons.search, color: AppColors.pink, size: 20),
                      filled: true,
                      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.03),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  SizedBox(
                    height: 40,
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
                  const SizedBox(height: 24),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("Nearby Venues", style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.bold, color: textCol)),
                      Text("Trending 🔥", style: GoogleFonts.sora(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orangeAccent)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  _venues.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(top: 20.0),
                          child: Center(child: Text("No venues listed matching this sport.", style: GoogleFonts.sora(color: Colors.grey))),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _venues.length,
                          itemBuilder: (context, index) {
                            final venue = _venues[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: GlassContainer(
                                padding: const EdgeInsets.all(0),
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => VenueDetailScreen(venueId: venue['venue_id']),
                                      ),
                                    );
                                  },
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
                                            child: const Center(child: Icon(Icons.image, size: 50, color: Colors.grey)),
                                          ),
                                          Positioned(
                                            top: 12,
                                            left: 12,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.black54,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.star, color: Colors.amber, size: 14),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    venue['avg_rating']?.toString() ?? '0',
                                                    style: GoogleFonts.sora(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 12,
                                            right: 12,
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: const BoxDecoration(
                                                color: Colors.black54,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.favorite_border, color: Colors.white, size: 16),
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 12,
                                            right: 12,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.6),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                "₹${venue['base_price']}/hr",
                                                style: GoogleFonts.sora(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          )
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
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    "${_selectedSport == 'All' ? 'Sports' : _selectedSport} • ${_selectedCity.split(',')[0]} • 0 km",
                                                    style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                gradient: AppColors.brandGradient,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (context) => VenueDetailScreen(venueId: venue['venue_id']),
                                                    ),
                                                  );
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.transparent,
                                                  shadowColor: Colors.transparent,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        )
                ],
              ),
            ),
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
        margin: const EdgeInsets.only(right: 8),
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

class VenueDetailScreen extends StatefulWidget {
  final String venueId;
  const VenueDetailScreen({super.key, required this.venueId});

  @override
  State<VenueDetailScreen> createState() => _VenueDetailScreenState();
}

class _VenueDetailScreenState extends State<VenueDetailScreen> {
  Map<String, dynamic> _venue = {};
  List<dynamic> _slots = [];
  bool _isLoading = true;
  String _selectedDate = "2026-06-20";
  dynamic _selectedSlot;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadVenueDetails();
  }

  void _loadVenueDetails() async {
    setState(() => _isLoading = true);
    final detailResponse = await ApiService.getVenueDetails(widget.venueId);
    final slotsResponse = await ApiService.getSlots(widget.venueId, _selectedDate);
    if (mounted) {
      setState(() {
        _venue = detailResponse['data'] ?? {};
        _slots = slotsResponse['data'] ?? [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.card : Colors.white;
    final textCol = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subtextCol = isDark ? Colors.white70 : const Color(0xFF6B7280);
    final borderCol = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.08);

    return Scaffold(
      backgroundColor: context.bgCol,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.pink))
          : Stack(
              children: [
                // Scrollable Content
                SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 110),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Hero Image Section
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(32),
                              bottomRight: Radius.circular(32),
                            ),
                            child: Container(
                              height: 280,
                              width: double.infinity,
                              color: Colors.grey.shade900,
                              child: const Center(
                                child: Icon(Icons.sports_soccer_rounded, size: 80, color: Colors.white24),
                              ),
                            ),
                          ),
                          // Gradient Overlay
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(32),
                                  bottomRight: Radius.circular(32),
                                ),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.4),
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Back Button
                          Positioned(
                            top: 48,
                            left: 16,
                            child: CircleAvatar(
                              backgroundColor: Colors.black.withOpacity(0.4),
                              child: IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ),
                          ),
                          // Share & Favorite Buttons
                          Positioned(
                            top: 48,
                            right: 16,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Colors.black.withOpacity(0.4),
                                  child: IconButton(
                                    icon: const Icon(Icons.share_rounded, color: Colors.white, size: 20),
                                    onPressed: () => AppToast.show(context, "Link shared!"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                CircleAvatar(
                                  backgroundColor: Colors.black.withOpacity(0.4),
                                  child: IconButton(
                                    icon: Icon(
                                      _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      color: _isFavorite ? AppColors.pink : Colors.white,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isFavorite = !_isFavorite;
                                      });
                                      AppToast.show(context, _isFavorite ? "Added to favorites!" : "Removed from favorites!");
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // 2. Venue Information
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _venue['name'] ?? 'Sports Venue',
                                    style: GoogleFonts.sora(fontSize: 22, fontWeight: FontWeight.bold, color: textCol),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.pink.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.verified_user_rounded, color: AppColors.pink, size: 14),
                                      const SizedBox(width: 4),
                                      Text("VERIFIED", style: GoogleFonts.sora(color: AppColors.pink, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                const SizedBox(width: 4),
                                Text(
                                  _venue['avg_rating']?.toString() ?? '4.8',
                                  style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textCol, fontSize: 14),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "(${_venue['reviews']?.length ?? 12} reviews)",
                                  style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                ),
                                const SizedBox(width: 12),
                                Text("•", style: TextStyle(color: subtextCol)),
                                const SizedBox(width: 12),
                                Text(
                                  "2.4 km away",
                                  style: GoogleFonts.sora(color: subtextCol, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            // 3. Amenities Section
                            Text(
                              "Amenities",
                              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 74,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: [
                                  _buildAmenity(Icons.lightbulb_outline_rounded, "Floodlights", cardBg, textCol, borderCol),
                                  _buildAmenity(Icons.local_parking_rounded, "Parking", cardBg, textCol, borderCol),
                                  _buildAmenity(Icons.shower_outlined, "Changing Room", cardBg, textCol, borderCol),
                                  _buildAmenity(Icons.local_cafe_outlined, "Cafe", cardBg, textCol, borderCol),
                                  _buildAmenity(Icons.wifi_rounded, "WiFi", cardBg, textCol, borderCol),
                                  _buildAmenity(Icons.ac_unit_rounded, "AC", cardBg, textCol, borderCol),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            // 4. Date & Slots Picker
                            Text(
                              "Select Date & Slots",
                              style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: textCol),
                            ),
                            const SizedBox(height: 12),
                            // Improved Date Selection slider
                            SizedBox(
                              height: 76,
                              child: ListView(
                                scrollDirection: Axis.horizontal,
                                children: ["2026-06-20", "2026-06-21", "2026-06-22", "2026-06-23", "2026-06-24", "2026-06-25"].map((date) {
                                  final isSelected = _selectedDate == date;
                                  final isToday = date == "2026-06-20";

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
                                          color: isSelected ? Colors.transparent : borderCol,
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            isToday ? "Today" : "Jun",
                                            style: GoogleFonts.sora(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: isSelected ? Colors.white70 : subtextCol,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            date.substring(8),
                                            style: GoogleFonts.sora(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: isSelected ? Colors.white : textCol,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // 5. Slots Layout
                            _slots.isEmpty
                                ? Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(28.0),
                                      child: Column(
                                        children: [
                                          Icon(Icons.event_busy_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
                                          const SizedBox(height: 12),
                                          Text(
                                            "No slots available for this date",
                                            style: GoogleFonts.sora(color: subtextCol, fontSize: 13),
                                          ),
                                          const SizedBox(height: 12),
                                          OutlinedButton(
                                            onPressed: () {
                                              setState(() {
                                                _selectedDate = "2026-06-20";
                                                _loadVenueDetails();
                                              });
                                            },
                                            style: OutlinedButton.styleFrom(
                                              side: const BorderSide(color: AppColors.pink),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                            child: Text("Choose another date", style: GoogleFonts.sora(color: AppColors.pink, fontSize: 12, fontWeight: FontWeight.bold)),
                                          )
                                        ],
                                      ),
                                    ),
                                  )
                                : GridView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 2.1,
                                    ),
                                    itemCount: _slots.length,
                                    itemBuilder: (context, index) {
                                      final slot = _slots[index];
                                      final isBooked = slot['status'] == 'booked';
                                      final isBlocked = slot['status'] == 'blocked_by_partner';
                                      final isSelected = _selectedSlot != null && _selectedSlot['slot_id'] == slot['slot_id'];

                                      Color cardBgColor = cardBg;
                                      Color textTextColor = textCol;
                                      Color subtitleColor = subtextCol;
                                      Border? cardBorder = Border.all(color: borderCol);

                                      if (isBooked) {
                                        cardBgColor = Colors.red.withOpacity(0.08);
                                        textTextColor = Colors.redAccent.withOpacity(0.7);
                                        subtitleColor = Colors.redAccent.withOpacity(0.5);
                                        cardBorder = Border.all(color: Colors.red.withOpacity(0.2));
                                      } else if (isBlocked) {
                                        cardBgColor = Colors.grey.withOpacity(0.08);
                                        textTextColor = Colors.grey.withOpacity(0.6);
                                        subtitleColor = Colors.grey.withOpacity(0.4);
                                        cardBorder = Border.all(color: Colors.grey.withOpacity(0.1));
                                      } else if (isSelected) {
                                        cardBgColor = Colors.transparent;
                                        textTextColor = Colors.white;
                                        subtitleColor = Colors.white70;
                                        cardBorder = null;
                                      }

                                      return GestureDetector(
                                        onTap: (isBooked || isBlocked)
                                            ? null
                                            : () {
                                                setState(() {
                                                  _selectedSlot = slot;
                                                });
                                              },
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          decoration: BoxDecoration(
                                            gradient: isSelected ? AppColors.brandGradient : null,
                                            color: isSelected ? null : cardBgColor,
                                            borderRadius: BorderRadius.circular(14),
                                            border: cardBorder,
                                            boxShadow: isSelected
                                                ? [BoxShadow(color: AppColors.pink.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                                                : null,
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                slot['start_time'] ?? '',
                                                style: GoogleFonts.sora(fontWeight: FontWeight.bold, color: textTextColor, fontSize: 13),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isBooked ? "Booked" : "₹${slot['price']}",
                                                style: GoogleFonts.sora(fontSize: 10, color: subtitleColor),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 6. Sticky Floating Bottom Booking Bar
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: GlassContainer(
                    radius: 20,
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
                                style: GoogleFonts.sora(fontSize: 11, color: subtextCol),
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
                            gradient: _selectedSlot != null ? AppColors.brandGradient : null,
                            color: _selectedSlot == null ? Colors.white10 : null,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ElevatedButton(
                            onPressed: _selectedSlot == null
                                ? null
                                : () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (context) => CheckoutScreen(
                                          venue: _venue,
                                          slot: _selectedSlot,
                                        ),
                                      ),
                                    );
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              "Book Now",
                              style: GoogleFonts.sora(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
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

  Widget _buildAmenity(IconData icon, String text, Color cardBg, Color textCol, Color borderCol) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.pink, size: 20),
          const SizedBox(width: 8),
          Text(text, style: GoogleFonts.sora(fontSize: 12, color: textCol, fontWeight: FontWeight.w500)),
        ],
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

    if (mode == "pay_at_venue") {
      setState(() => _isLoading = false);
      booking['slot'] = widget.slot;
      booking['venue'] = widget.venue;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ConfirmationScreen(booking: booking),
        ),
      );
    } else {
      final payInit = await ApiService.initiatePayment(bookingId);
      final orderId = payInit['orderId'];

      await Future.delayed(const Duration(seconds: 1));

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E2638), // Razorpay brand color theme
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.network(
                      'https://razorpay.com/assets/razorpay-glyph.svg',
                      height: 28,
                      errorBuilder: (c, e, s) => const Icon(Icons.payment_rounded, color: Colors.blue, size: 28),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "TEST MODE",
                        style: GoogleFonts.sora(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  widget.venue['name'] ?? 'Sports Arena',
                  style: GoogleFonts.sora(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  "Order ID: $orderId",
                  style: GoogleFonts.sora(fontSize: 12, color: Colors.white70),
                ),
                const Divider(color: Colors.white24, height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Total Amount", style: GoogleFonts.sora(color: Colors.white70, fontSize: 13)),
                    Text(
                      "₹${booking['online_amount']}",
                      style: GoogleFonts.sora(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Payment Method Simulation options
                Text("Select Simulated Payment Method:", style: GoogleFonts.sora(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 12),
                _buildRazorpayMethod(Icons.qr_code_rounded, "UPI / GooglePay"),
                _buildRazorpayMethod(Icons.credit_card_rounded, "Card (Visa/Mastercard)"),
                _buildRazorpayMethod(Icons.account_balance_rounded, "Netbanking"),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(() => _isLoading = false);
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text("Cancel", style: GoogleFonts.sora(color: Colors.white70)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          final mockPayId = "pay_${MathUtils.randomString(14)}";
                          final verifyRes = await ApiService.verifyPayment(bookingId, orderId, mockPayId);
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
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text("Pay Success", style: GoogleFonts.sora(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    )
                  ],
                )
              ],
            ),
          ),
        ),
      );
    }
  }

  Widget _buildRazorpayMethod(IconData icon, String label) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.sora(color: Colors.white, fontSize: 13)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: Colors.white30, size: 18),
        ],
      ),
    );
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
        child: BackdropFilter(
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


