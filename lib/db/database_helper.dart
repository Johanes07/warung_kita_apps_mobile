  import 'dart:async';
  import 'dart:io';
  import 'package:flutter/services.dart' show rootBundle;
  import 'package:path/path.dart';
  import 'package:sqflite/sqflite.dart';

  class DatabaseHelper {
    static final DatabaseHelper instance = DatabaseHelper._init();
    static Database? _database;

    DatabaseHelper._init();

    /// Getter untuk database
    Future<Database> get database async {
      if (_database != null) return _database!;
      _database = await _initDB();
      return _database!;
    }

    /// Inisialisasi database
    Future<Database> _initDB() async {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'warung_kita.sqlite');

      // Cek apakah database sudah ada
      final exists = await File(path).exists();

      if (!exists) {
        print("Database belum ada, menyalin dari assets...");

        // Buat folder jika belum ada
        await Directory(dirname(path)).create(recursive: true);

        try {
          // Coba load database dari assets
          final data = await rootBundle.load('assets/database/warung_kita.sqlite');
          final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

          await File(path).writeAsBytes(bytes, flush: true);
          print("Database berhasil disalin ke: $path");
        } catch (e) {
          print("Gagal menyalin database dari assets. Membuat database baru...");
        }
      } else {
        print("Database sudah ada di: $path");
      }

      // Buka database dan buat tabel jika belum ada
      return await openDatabase(
        path,
        version: 1,
        onCreate: _createDB,
        onConfigure: (db) async {
          // Aktifkan foreign key
          await db.execute('PRAGMA foreign_keys = ON');
        },
      );
    }

    /// Membuat tabel ketika database baru dibuat
    Future _createDB(Database db, int version) async {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT UNIQUE NOT NULL,
          password TEXT NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          barcode TEXT UNIQUE NOT NULL,
          price_retail INTEGER NOT NULL,
          price_wholesale INTEGER NOT NULL,
          stock INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id INTEGER NOT NULL,
          total_amount INTEGER NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY(user_id) REFERENCES users(id)
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS transaction_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          transaction_id INTEGER NOT NULL,
          product_id INTEGER NOT NULL,
          quantity INTEGER NOT NULL,
          price INTEGER NOT NULL,
          FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
          FOREIGN KEY(product_id) REFERENCES products(id)
        )
      ''');

      print("Tabel database berhasil dibuat!");
    }

    // ==========================
    // USERS FUNCTIONS
    // ==========================

    /// Register user baru
    Future<int> registerUser(String name, String email, String password) async {
      final db = await database;

      final existing = await db.query(
        'users',
        where: 'email = ?',
        whereArgs: [email.trim()],
      );

      if (existing.isNotEmpty) {
        throw Exception('Email sudah terdaftar!');
      }

      final data = {
        'name': name.trim(),
        'email': email.trim(),
        'password': password.trim(),
      };

      final id = await db.insert('users', data);
      print("User berhasil diregistrasi dengan ID: $id");
      return id;
    }

    /// Login user
    Future<Map<String, dynamic>?> loginUser(String email, String password) async {
      final db = await database;

      final result = await db.query(
        'users',
        where: 'email = ? AND password = ?',
        whereArgs: [email.trim(), password.trim()],
      );

      print("Login attempt dengan email: $email, password: $password");
      print("Result login: $result");

      if (result.isNotEmpty) {
        return result.first;
      }
      return null;
    }

    /// Ambil semua user
    Future<List<Map<String, dynamic>>> getAllUsers() async {
      final db = await database;
      final users = await db.query('users', orderBy: 'created_at DESC');
      print("List user: $users");
      return users;
    }

    // ==========================
    // PRODUCTS FUNCTIONS
    // ==========================
    Future<List<Map<String, dynamic>>> getAllProducts() async {
      final db = await database;
      return await db.query('products', orderBy: 'name ASC');
    }

    // ==========================
    // CLOSE DATABASE
    // ==========================
    Future close() async {
      final db = await database;
      db.close();
    }

    // OPTIONAL: Reset database (hapus semua data)
    Future resetDatabase() async {
      final db = await database;
      await db.delete('transaction_items');
      await db.delete('transactions');
      await db.delete('products');
      await db.delete('users');
      print("Semua data berhasil dihapus!");
    }
  }
