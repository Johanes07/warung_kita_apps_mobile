import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:warung_kita/db/database_helper.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  _RegisterScreenState createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool _isLoading = false;

  /// Fungsi register user
  Future<void> registerUser() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (name.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua field wajib diisi!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password dan konfirmasi tidak cocok!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final db = await DatabaseHelper.instance.database;

    /// Cek apakah email sudah terdaftar
    final existingUser = await db.query(
      'users',
      where: 'email = ?',
      whereArgs: [email],
    );

    if (existingUser.isNotEmpty) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email sudah terdaftar!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    /// Simpan user baru
    await db.insert('users', {
      'name': name,
      'email': email,
      'password': password,
    });

    setState(() {
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Registrasi Berhasil! Silakan login.'),
        backgroundColor: Colors.green,
      ),
    );

    /// Pindah ke halaman login
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          /// === Background Image ===
          Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/images/bgwarung.jpeg"),
                fit: BoxFit.cover,
              ),
            ),
          ),

          /// === Overlay Transparan Gelap ===
          Container(
            color: Colors.black.withOpacity(0.5),
          ),

          /// === Content Register ===
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Card(
                  elevation: 10,
                  color: Colors.white.withOpacity(0.85),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(25),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        /// Judul
                        Text(
                          "Register Akun",
                          style: GoogleFonts.poppins(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.brown[700],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          "Buat akun untuk mulai menggunakan Warung Kita",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 25),

                        /// Nama Field
                        TextField(
                          controller: nameController,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.person, color: Colors.brown),
                            labelText: 'Nama Lengkap',
                            labelStyle: const TextStyle(color: Colors.brown),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.brown, width: 2),
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),

                        /// Email Field
                        TextField(
                          controller: emailController,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.email, color: Colors.brown),
                            labelText: 'Email',
                            labelStyle: const TextStyle(color: Colors.brown),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.brown, width: 2),
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),

                        /// Password Field
                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock, color: Colors.brown),
                            labelText: 'Password',
                            labelStyle: const TextStyle(color: Colors.brown),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.brown, width: 2),
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                        const SizedBox(height: 15),

                        /// Konfirmasi Password Field
                        TextField(
                          controller: confirmPasswordController,
                          obscureText: true,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.lock_outline, color: Colors.brown),
                            labelText: 'Konfirmasi Password',
                            labelStyle: const TextStyle(color: Colors.brown),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: Colors.brown, width: 2),
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                        ),
                        const SizedBox(height: 25),

                        /// Tombol Register
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : registerUser,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.brown[700],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              elevation: 5,
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    'Register',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        /// Kembali ke Login
                        TextButton(
                          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
                          child: Text(
                            'Sudah punya akun? Login',
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
          ),
        ],
      ),
    );
  }
}
