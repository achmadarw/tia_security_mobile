import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'config/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/face_recognition_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize auth service
  final authService = AuthService();
  await authService.init();

  // Pre-initialize face recognition model to avoid "failed precondition" error
  print('[Main] Pre-initializing face recognition model...');
  final faceRecognitionService = FaceRecognitionService();
  try {
    await faceRecognitionService.initialize();
    print('[Main] ✅ Face recognition model ready');
  } catch (e) {
    print('[Main] ⚠️ Failed to pre-initialize face recognition: $e');
    print('[Main] Model will be initialized on first use');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MyApp(authService: authService),
    ),
  );
}

class MyApp extends StatelessWidget {
  final AuthService authService;

  const MyApp({super.key, required this.authService});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'TIA - Security Management',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeProvider.themeMode,
          home: SplashScreen(authService: authService),
        );
      },
    );
  }
}
