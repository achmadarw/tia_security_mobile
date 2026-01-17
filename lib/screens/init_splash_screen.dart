import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/face_recognition_service.dart';
import '../services/security_app_service.dart';
import 'app_selector_screen.dart';
import 'security_home_screen.dart';

/// Initial Splash Screen with Face Recognition Initialization
/// Shows loading progress while initializing heavy resources
class InitSplashScreen extends StatefulWidget {
  final AuthService authService;

  const InitSplashScreen({Key? key, required this.authService})
      : super(key: key);

  @override
  State<InitSplashScreen> createState() => _InitSplashScreenState();
}

class _InitSplashScreenState extends State<InitSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  String _statusText = 'Memulai aplikasi...';
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeOutBack,
      ),
    );

    _animationController.forward();
    _initializeApp();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeApp() async {
    try {
      // Step 1: Check for existing security session
      setState(() {
        _statusText = 'Memeriksa sesi...';
        _progress = 0.1;
      });

      final prefs = await SharedPreferences.getInstance();
      final securityToken = prefs.getString('security_access_token');

      if (securityToken != null && securityToken.isNotEmpty) {
        // Try to restore security session
        setState(() {
          _statusText = 'Memulihkan sesi Security...';
          _progress = 0.3;
        });

        try {
          final securityService = SecurityAppService();
          final sessionData = await securityService.getCurrentSession();

          // Session is valid, navigate to dashboard
          setState(() {
            _statusText = 'Sesi aktif ditemukan';
            _progress = 1.0;
          });
          await Future.delayed(const Duration(milliseconds: 500));

          if (!mounted) return;

          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => SecurityHomeScreen(
                sessionData: sessionData,
                authService: widget.authService,
              ),
            ),
          );
          return;
        } catch (e) {
          print('[InitSplash] Session restore failed: $e');
          // Token expired or session invalid, clear and continue to login
          await prefs.remove('security_access_token');
          await prefs.remove('security_user_data');
          await prefs.remove('security_pos_data');
        }
      }

      // Step 2: Initialize auth service (quick)
      setState(() {
        _statusText = 'Memuat konfigurasi...';
        _progress = 0.4;
      });
      await Future.delayed(const Duration(milliseconds: 300));

      // Step 3: Initialize face recognition model (heavy)
      setState(() {
        _statusText = 'Memuat model Face Recognition...';
        _progress = 0.6;
      });

      final faceRecognitionService = FaceRecognitionService();
      await faceRecognitionService.initialize();

      setState(() {
        _statusText = 'Face Recognition siap';
        _progress = 0.9;
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 4: Complete
      setState(() {
        _statusText = 'Selesai';
        _progress = 1.0;
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // Navigate to app selector
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              AppSelectorScreen(authService: widget.authService),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    } catch (e) {
      print('[InitSplash] Error: $e');
      setState(() {
        _statusText = 'Face Recognition akan dimuat saat dibutuhkan';
        _progress = 1.0;
      });

      // Continue to app even if face recognition fails
      await Future.delayed(const Duration(milliseconds: 1500));

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              AppSelectorScreen(authService: widget.authService),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue[700]!,
              Colors.blue[900]!,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 15),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.security,
                        size: 70,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // App Title
                    const Text(
                      'TIA System',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            color: Colors.black26,
                            offset: Offset(0, 4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subtitle
                    const Text(
                      'Security Management',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 80),

                    // Loading Progress Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 60),
                      child: Column(
                        children: [
                          // Progress bar
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: _progress),
                              duration: const Duration(milliseconds: 500),
                              curve: Curves.easeInOut,
                              builder: (context, value, child) {
                                return LinearProgressIndicator(
                                  value: value,
                                  minHeight: 8,
                                  backgroundColor: Colors.white24,
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Status text
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              _statusText,
                              key: ValueKey(_statusText),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Percentage
                          Text(
                            '${(_progress * 100).toInt()}%',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 60),

                    // Loading dots animation
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) {
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 500 + (index * 200)),
                          curve: Curves.easeInOut,
                          builder: (context, value, child) {
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withOpacity(0.3 + (value * 0.7)),
                                shape: BoxShape.circle,
                              ),
                            );
                          },
                          onEnd: () {
                            // Repeat animation
                            if (mounted && _progress < 1.0) {
                              setState(() {});
                            }
                          },
                        );
                      }),
                    ),

                    const SizedBox(height: 40),

                    // Version info
                    const Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
