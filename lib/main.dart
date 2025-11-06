import 'package:flutter/material.dart';
import 'package:warung_kita/Screens/Login/loginscreen.dart';
import 'package:warung_kita/Screens/Register/registerscreen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Warung Kita',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),

      // Halaman awal aplikasi
      initialRoute: '/login',

      // Daftar route yang tersedia
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
      },
    );
  }
}
