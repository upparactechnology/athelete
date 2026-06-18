import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'api_service.dart';

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
    setState(() => _isLoading = false);

    if (response['success'] == true) {
      setState(() => _otpRequested = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['data']['message'] ?? 'OTP Sent!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to request OTP')),
      );
    }
  }

  void _verifyOtp() async {
    if (_otpController.text.trim().isEmpty) return;
    setState(() => _isLoading = true);
    final response = await ApiService.verifyOtp(_phoneController.text.trim(), _otpController.text.trim());
    setState(() => _isLoading = false);

    if (response['success'] == true) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(toggleTheme: widget.toggleTheme),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(response['error']?['message'] ?? 'Verification failed')),
      );
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
              const Icon(Icons.sports_soccer, size: 60, color: Color(0xFF10B981)),
              const SizedBox(height: 20),
              Text(
                _otpRequested ? "Verify OTP" : "Let's Get Started",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _otpRequested ? "Enter the 6-digit code sent to you" : "Enter your phone number to login or register",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              if (!_otpRequested) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone, color: Color(0xFF10B981)),
                    hintText: "Phone Number",
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _requestOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Request OTP", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock, color: Color(0xFF10B981)),
                    hintText: "Enter OTP (e.g. 123456)",
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isLoading ? null : _verifyOtp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("Verify & Login", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                TextButton(
                  onPressed: () => setState(() => _otpRequested = false),
                  child: const Text("Change Phone Number", style: TextStyle(color: Color(0xFF10B981))),
                )
              ]
            ],
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
      const TournamentsTab(),
      const CouponsTab(),
      ProfileTab(toggleTheme: widget.toggleTheme),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: tabs,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF10B981),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.emoji_events), label: 'Events'),
          BottomNavigationBarItem(icon: Icon(Icons.percent), label: 'Coupons'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
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
  String _selectedCity = "Bengaluru";
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.location_on, color: Color(0xFF10B981)),
            const SizedBox(width: 4),
            DropdownButton<String>(
              value: _selectedCity,
              underline: const SizedBox(),
              items: ["Bengaluru", "Mumbai", "Delhi", "Hyderabad"].map((city) {
                return DropdownMenuItem(value: city, child: Text(city, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCity = val);
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dark_mode),
            onPressed: widget.toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.notifications),
            onPressed: () {},
          )
        ],
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Hello, Amit! 👋", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text("Let's Play!", style: TextStyle(color: Colors.grey, fontSize: 16)),
                  const SizedBox(height: 20),
                  // Search Bar
                  TextField(
                    decoration: InputDecoration(
                      hintText: "Search venues, sports or areas...",
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: theme.colorScheme.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Carousel Banners
                  if (_banners.isNotEmpty) ...[
                    SizedBox(
                      height: 140,
                      child: PageView.builder(
                        itemCount: _banners.length,
                        itemBuilder: (context, index) {
                          final banner = _banners[index];
                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            clipBehavior: Clip.antiAlias,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Container(color: Colors.indigoAccent),
                                Positioned(
                                  left: 20,
                                  top: 30,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(banner['title'] ?? 'Special Booking Promo', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(20)),
                                        child: const Text("Book Now", style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold)),
                                      )
                                    ],
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  // Sports filter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: ["All", "Football", "Cricket", "Badminton"].map((sport) {
                      final isSelected = _selectedSport == sport;
                      return ChoiceChip(
                        label: Text(sport),
                        selected: isSelected,
                        selectedColor: const Color(0xFF10B981),
                        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.grey),
                        onSelected: (selected) {
                          setState(() {
                            _selectedSport = sport;
                            _loadData();
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text("Nearby Venues", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  // Venues Grid/List
                  _venues.isEmpty
                      ? const Text("No venues listed matching this sport category.")
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _venues.length,
                          itemBuilder: (context, index) {
                            final venue = _venues[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              clipBehavior: Clip.antiAlias,
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
                                    Container(
                                      height: 150,
                                      color: Colors.grey.shade800,
                                      child: const Center(child: Icon(Icons.image, size: 50, color: Colors.grey)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(venue['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                              Row(
                                                children: [
                                                  const Icon(Icons.star, color: Colors.amber, size: 18),
                                                  const SizedBox(width: 4),
                                                  Text(venue['avg_rating']?.toString() ?? '4.8'),
                                                ],
                                              )
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text("Indoor Football • Koramangala", style: TextStyle(color: Colors.grey.shade400, fontSize: 13)),
                                          const SizedBox(height: 8),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text("₹${venue['base_price']} onwards", style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16)),
                                              const Text("Details & Book", style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                                            ],
                                          )
                                        ],
                                      ),
                                    )
                                  ],
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
}

// -------------------------------------------------------------
// Venue Details & Slot Picker Screen
// -------------------------------------------------------------
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

  @override
  void initState() {
    super.initState();
    _loadVenueDetails();
  }

  void _loadVenueDetails() async {
    setState(() => _isLoading = true);
    final detailResponse = await ApiService.getVenueDetails(widget.venueId);
    final slotsResponse = await ApiService.getSlots(widget.venueId, _selectedDate);
    setState(() {
      _venue = detailResponse['data'] ?? {};
      _slots = slotsResponse['data'] ?? [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_venue['name'] ?? 'Venue Details'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 200,
                    color: Colors.grey.shade800,
                    child: const Center(child: Icon(Icons.image, size: 80, color: Colors.grey)),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_venue['name'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 4),
                            Text(_venue['avg_rating']?.toString() ?? '4.8', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text("(${_venue['reviews']?.length ?? 0} reviews)", style: const TextStyle(color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text("Amenities", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildAmenity(Icons.lightbulb, "Flood Lights"),
                            _buildAmenity(Icons.local_parking, "Parking"),
                            _buildAmenity(Icons.shower, "Change Room"),
                            _buildAmenity(Icons.local_cafe, "Drinks"),
                          ],
                        ),
                        const SizedBox(height: 24),
                        const Text("Select Date & Slots", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        // Calendar Picker Slider
                        SizedBox(
                          height: 60,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: ["2026-06-20", "2026-06-21", "2026-06-22", "2026-06-23", "2026-06-24"].map((date) {
                              final isSelected = _selectedDate == date;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedDate = date;
                                    _selectedSlot = null;
                                    _loadVenueDetails();
                                  });
                                },
                                child: Container(
                                  width: 80,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF10B981) : theme.colorScheme.surface,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(date.substring(8), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : null)),
                                      Text(date.substring(5, 7), style: TextStyle(fontSize: 12, color: isSelected ? Colors.white70 : Colors.grey)),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Slots Grid
                        _slots.isEmpty
                            ? const Text("No slots generated for this date.")
                            : GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
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
                                  final isSelected = _selectedSlot != null && _selectedSlot['slot_id'] == slot['slot_id'];

                                  Color bg = theme.colorScheme.surface;
                                  Color textColor = Colors.white;

                                  if (isBooked) {
                                    bg = Colors.red.shade900.withOpacity(0.4);
                                    textColor = Colors.red.shade300;
                                  } else if (isBlocked) {
                                    bg = Colors.grey.shade800;
                                    textColor = Colors.grey;
                                  } else if (isSelected) {
                                    bg = const Color(0xFF10B981);
                                    textColor = Colors.white;
                                  }

                                  return GestureDetector(
                                    onTap: (isBooked || isBlocked)
                                        ? null
                                        : () {
                                            setState(() {
                                              _selectedSlot = slot;
                                            });
                                          },
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: bg,
                                        borderRadius: BorderRadius.circular(10),
                                        border: isSelected ? Border.all(color: Colors.white, width: 1.5) : null,
                                      ),
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(slot['start_time'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                                          Text("₹${slot['price']}", style: TextStyle(fontSize: 12, color: isSelected ? Colors.white70 : Colors.grey)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                        const SizedBox(height: 30),
                        ElevatedButton(
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
                            backgroundColor: const Color(0xFF10B981),
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text("Select Date & Slots", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                        )
                      ],
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildAmenity(IconData icon, String text) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: Colors.grey.shade800,
          child: Icon(icon, color: const Color(0xFF10B981)),
        ),
        const SizedBox(height: 4),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
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
    // Simulate lookup coupon
    setState(() {
      _discount = double.parse(widget.slot['price']) * 0.1; // 10% mock discount
      _appliedCouponCode = code;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Coupon "$code" applied! 10% Discount')),
    );
  }

  void _processPayment() async {
    setState(() => _isLoading = true);

    // 1. Create booking in pending status
    final mode = _payOnline ? "online" : "pay_at_venue";
    final bookingRes = await ApiService.createBooking(
      widget.venue['venue_id'],
      widget.slot['slot_id'],
      mode,
      couponCode: _appliedCouponCode,
    );

    if (bookingRes['success'] != true) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to lock slot and create booking.")),
      );
      return;
    }

    final booking = bookingRes['data'];
    final bookingId = booking['booking_id'];

    if (mode == "pay_at_venue") {
      // Direct success for deposit/cash
      setState(() => _isLoading = false);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ConfirmationScreen(booking: booking),
        ),
      );
    } else {
      // 2. Initiate payment record
      final payInit = await ApiService.initiatePayment(bookingId);
      final orderId = payInit['orderId'];

      // 3. Mock payment sheet popup
      await Future.delayed(const Duration(seconds: 1));

      // Show mock Razorpay dialog overlay
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.payment, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text("Razorpay Sandbox"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Order ID: $orderId"),
              const SizedBox(height: 8),
              Text("Pay securely: ₹${booking['online_amount']}"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() => _isLoading = false);
              },
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // 4. Verify payment
                final mockPayId = "pay_${MathUtils.randomString(14)}";
                final verifyRes = await ApiService.verifyPayment(bookingId, orderId, mockPayId);
                if (verifyRes['success'] == true) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(
                      builder: (context) => ConfirmationScreen(booking: verifyRes['data']),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Payment verification failed")),
                  );
                }
                setState(() => _isLoading = false);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              child: const Text("Simulate Success", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = double.parse(widget.slot['price']);
    final finalPrice = price - _discount;
    final convenience = finalPrice * 0.04;
    final gst = finalPrice * 0.03 * 0.18;
    final total = finalPrice + convenience + gst;

    final deposit = total * 0.3;
    final outstanding = total * 0.7;

    return Scaffold(
      appBar: AppBar(title: const Text("Checkout")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Venue details card
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            color: Colors.grey.shade800,
                            child: const Icon(Icons.image),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.venue['name'] ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              Text("Time: ${widget.slot['start_time']} - ${widget.slot['end_time']}", style: const TextStyle(color: Colors.grey)),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Coupon Code
                  const Text("Have a coupon code?", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponController,
                          decoration: const InputDecoration(
                            hintText: "Enter code (e.g. PLAY10)",
                            filled: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _applyCoupon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          minimumSize: const Size(80, 50),
                        ),
                        child: const Text("Apply", style: TextStyle(color: Colors.white)),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Payment options split
                  const Text("Payment Options", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  RadioListTile<bool>(
                    title: const Text("Pay Online (Full Amount)"),
                    subtitle: const Text("Pay now and enjoy your game"),
                    value: true,
                    groupValue: _payOnline,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _payOnline = val!),
                  ),
                  RadioListTile<bool>(
                    title: const Text("Pay at Venue (Split Deposit)"),
                    subtitle: const Text("Pay 30% online now & 70% cash at court"),
                    value: false,
                    groupValue: _payOnline,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _payOnline = val!),
                  ),
                  const SizedBox(height: 24),
                  // Detailed price breakdown
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildPriceRow("Slot Price", "₹${price.toStringAsFixed(2)}"),
                          if (_discount > 0) _buildPriceRow("Discount Applied", "-₹${_discount.toStringAsFixed(2)}", color: Colors.green),
                          _buildPriceRow("Convenience Fee (4%)", "₹${convenience.toStringAsFixed(2)}"),
                          _buildPriceRow("GST (18% on platform commission)", "₹${gst.toStringAsFixed(2)}"),
                          const Divider(),
                          _buildPriceRow("Total Amount", "₹${total.toStringAsFixed(2)}", isBold: true),
                          if (!_payOnline) ...[
                            const Divider(),
                            _buildPriceRow("Payable Now (30%)", "₹${deposit.toStringAsFixed(2)}", color: const Color(0xFF10B981), isBold: true),
                            _buildPriceRow("Pay at Venue (70%)", "₹${outstanding.toStringAsFixed(2)}", color: Colors.amber),
                          ]
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _processPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      _payOnline ? "Proceed to Pay: ₹${total.toStringAsFixed(2)}" : "Proceed with Deposit: ₹${deposit.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildPriceRow(String label, String value, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color)),
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle_outline, size: 90, color: Color(0xFF10B981)),
              const SizedBox(height: 16),
              const Text("Booking Confirmed!", textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text("Your slot is locked and confirmed.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 32),
              // E-Ticket Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Text(booking['eticket_code'] ?? 'APV-2026-XXXXXX', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 16),
                      // QR Code
                      QrImageView(
                        data: booking['eticket_code'] ?? '',
                        version: QrVersions.auto,
                        size: 160.0,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      const Text("Show this QR at the venue for check-in", style: TextStyle(color: Colors.grey, fontSize: 13)),
                      const Divider(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Online Paid"),
                          Text("₹${booking['online_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                        ],
                      ),
                      if (double.parse(booking['venue_amount'].toString()) > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("Pay at Venue"),
                            Text("₹${booking['venue_amount']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber)),
                          ],
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => SplashScreen(toggleTheme: () {})),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text("Back to Home", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
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
    setState(() {
      _bookings = res['data'] ?? [];
      _isLoading = false;
    });
  }

  void _cancel(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Cancel Booking"),
        content: const Text("Are you sure you want to cancel this booking? This will release your slot."),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("No")),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("Yes, Cancel")),
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
    return Scaffold(
      appBar: AppBar(title: const Text("My Bookings")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _bookings.isEmpty
              ? const Center(child: Text("You have no booking records yet."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _bookings.length,
                  itemBuilder: (context, index) {
                    final booking = _bookings[index];
                    final isCancelled = booking['status'] == "CANCELLED";

                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(booking['venue']?['name'] ?? 'Sports Turf', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCancelled ? Colors.red.shade900 : const Color(0xFF10B981).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(booking['status'] ?? 'PENDING', style: TextStyle(color: isCancelled ? Colors.red.shade300 : const Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                                )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text("Slot: ${booking['slot']?['start_time']} - ${booking['slot']?['end_time']}"),
                            Text("Code: ${booking['eticket_code']}"),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text("Paid: ₹${booking['online_amount']}", style: const TextStyle(fontWeight: FontWeight.bold)),
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
                                        child: const Text("View Ticket", style: TextStyle(color: Color(0xFF10B981))),
                                      ),
                                      const SizedBox(width: 8),
                                      TextButton(
                                        onPressed: () => _cancel(booking['booking_id']),
                                        child: const Text("Cancel", style: TextStyle(color: Colors.red)),
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
    setState(() {
      _coupons = res['data'] ?? [];
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Coupons")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : _coupons.isEmpty
              ? const Center(child: Text("Your wallet has no coupon codes right now."))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _coupons.length,
                  itemBuilder: (context, index) {
                    final item = _coupons[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      child: ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Color(0xFF10B981),
                          child: Icon(Icons.percent, color: Colors.white),
                        ),
                        title: Text(item['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("Get ${item['discount_value']}% OFF on slot bookings"),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF10B981)), borderRadius: BorderRadius.circular(4)),
                          child: const Text("ACTIVE", style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
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

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  void _loadProfile() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getProfile();
    setState(() {
      _profile = res['data'] ?? {};
      _isLoading = false;
    });
  }

  void _logout() async {
    await ApiService.clearToken();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => SplashScreen(toggleTheme: widget.toggleTheme)),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Profile")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    radius: 50,
                    backgroundColor: Color(0xFF10B981),
                    child: Icon(Icons.person, size: 50, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(_profile['name'] ?? 'Athlete User', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  Text(_profile['phone_number'] ?? '', style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 30),
                  // Preferences
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.dark_mode, color: Color(0xFF10B981)),
                          title: const Text("Toggle Dark/Light Mode"),
                          trailing: Switch(
                            value: Theme.of(context).brightness == Brightness.dark,
                            activeColor: const Color(0xFF10B981),
                            onChanged: (val) => widget.toggleTheme(),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.email, color: Color(0xFF10B981)),
                          title: const Text("Email Address"),
                          subtitle: Text(_profile['email'] ?? 'Not set'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Milestones
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Milestones & Rewards", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          _buildMilestoneRow("First Booking Completed", true),
                          _buildMilestoneRow("5 Bookings Completed", false),
                          _buildMilestoneRow("Tournament Champions", false),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _logout,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("Logout", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  )
                ],
              ),
            ),
    );
  }

  Widget _buildMilestoneRow(String label, bool completed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Icon(completed ? Icons.check_circle : Icons.radio_button_unchecked, color: completed ? const Color(0xFF10B981) : Colors.grey),
        ],
      ),
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
