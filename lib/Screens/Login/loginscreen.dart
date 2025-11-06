import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rive/rive.dart';
import 'package:warung_kita/Screens/Home/homescreen.dart';
import 'package:warung_kita/Screens/Register/registerscreen.dart';
import 'package:warung_kita/db/database_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  /// === Variabel Animasi Rive ===
  Artboard? _riveArtboard;
  SMIInput<bool>? isFocus; // Fokus di email field
  SMIInput<bool>? isPrivateField; // Fokus di password field
  SMIInput<bool>? isPrivateFieldShow; // Toggle password show/hide
  SMIInput<double>? numLook; // Teddy melihat panjang teks email
  SMITrigger? successTrigger; // Trigger animasi sukses login
  SMITrigger? failTrigger; // Trigger animasi gagal login

  @override
  void initState() {
    super.initState();
    _loadRive();
  }

  /// === Load File Rive ===
  Future<void> _loadRive() async {
    try {
      // ✅ WAJIB inisialisasi sebelum memanggil RiveFile.import()
      await RiveFile.initialize();

      final data = await rootBundle.load('assets/rive/auth_teddy.riv');
      final file = RiveFile.import(data);
      final artboard = file.mainArtboard;

      // Pastikan nama State Machine di Rive benar
      final controller = StateMachineController.fromArtboard(
        artboard,
        'Login Machine', // Nama state machine di file Rive
      );

      if (controller != null) {
        artboard.addController(controller);

        /// Hubungkan input dengan state machine di Rive
        isFocus = controller.findInput<bool>('isFocus');
        isPrivateField = controller.findInput<bool>('isPrivateField');
        isPrivateFieldShow = controller.findInput<bool>('isPrivateFieldShow');
        numLook = controller.findInput<double>('numLook');

        /// ✅ Trigger state
        successTrigger = controller.findInput<bool>('success') as SMITrigger?;
        failTrigger = controller.findInput<bool>('fail') as SMITrigger?;

        // Debugging
        print("SuccessTrigger ditemukan: $successTrigger");
        print("FailTrigger ditemukan: $failTrigger");
      } else {
        print("❌ State Machine 'Login Machine' tidak ditemukan di file Rive!");
      }

      setState(() {
        _riveArtboard = artboard;
      });
    } catch (e) {
      print("Error saat load Rive: $e");
    }
  }

  /// === Fungsi Login ===
  Future<void> loginUser() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    // Validasi input
    if (email.isEmpty || password.isEmpty) {
      _showSnackBar('Email dan password harus diisi!', Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final db = await DatabaseHelper.instance.database;

      // Pastikan nama tabel dan kolom sesuai
      final result = await db.query(
        'users',
        where: 'email = ? AND password = ?',
        whereArgs: [email, password],
      );

      print("Hasil login: $result"); // Debugging

      setState(() {
        _isLoading = false;
      });

      if (result.isNotEmpty) {
        // ✅ Trigger animasi sukses
        successTrigger?.fire();
        print("Trigger sukses dipanggil");

        final int userId = result.first['id'] as int;

        _showSnackBar('Login berhasil!', Colors.green);

        Future.delayed(const Duration(seconds: 1), () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => HomeScreen(userId: userId)),
          );
        });
      } else {
        // ❌ Trigger animasi gagal
        failTrigger?.fire();
        print("Trigger gagal dipanggil");
        _showSnackBar('Email atau password salah', Colors.red);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Terjadi kesalahan: $e', Colors.red);
    }
  }

  /// === Helper untuk SnackBar ===
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// === Background ===
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/images/bgwarung.jpeg"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.5)),

          /// === Konten Utama ===
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Card(
                elevation: 10,
                color: Colors.white.withOpacity(0.9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      /// Teddy Animasi
                      SizedBox(
                        height: 200,
                        child: _riveArtboard == null
                            ? const Center(child: CircularProgressIndicator())
                            : Rive(artboard: _riveArtboard!),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        "MY APPS",
                        style: GoogleFonts.poppins(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.brown[700],
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Masuk untuk melanjutkan",
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 25),

                      /// === Input Email ===
                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.black87),
                        onTap: () {
                          isFocus?.value = true;
                          isPrivateField?.value = false;
                        },
                        onChanged: (value) {
                          // Teddy melihat panjang teks yang diketik
                          numLook?.value = value.length.toDouble();
                        },
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.email, color: Colors.brown),
                          labelText: 'Email',
                          labelStyle: const TextStyle(color: Colors.brown),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                                color: Colors.brown, width: 2),
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      /// === Input Password ===
                      TextField(
                        controller: passwordController,
                        obscureText: _obscurePassword,
                        onTap: () {
                          isFocus?.value = false;
                          isPrivateField?.value = true;
                        },
                        onChanged: (value) {
                          isPrivateField?.value = value.isNotEmpty;
                        },
                        decoration: InputDecoration(
                          prefixIcon:
                              const Icon(Icons.lock, color: Colors.brown),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              color: Colors.brown,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                                isPrivateFieldShow?.value = !_obscurePassword;
                              });
                            },
                          ),
                          labelText: 'Password',
                          labelStyle: const TextStyle(color: Colors.brown),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(
                                color: Colors.brown, width: 2),
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 25),

                      /// === Tombol Login ===
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : loginUser,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.brown[700],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            elevation: 5,
                          ),
                          child: _isLoading
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : const Text(
                                  'Login',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 15),

                      /// === Tombol Register ===
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const RegisterScreen(),
                            ),
                          );
                        },
                        child: Text(
                          'Belum punya akun? Register',
                          style: GoogleFonts.poppins(
                            color: Colors.brown[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
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
