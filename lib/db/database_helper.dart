import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'warung_kita.sqlite');

    final exists = await File(path).exists();

    if (!exists) {
      print("Database belum ada, membuat database baru...");
      await Directory(dirname(path)).create(recursive: true);
    } else {
      print("Database sudah ada di: $path");

      // ✅ CEK STRUKTUR DATABASE, HAPUS JIKA CORRUPT
      try {
        final testDb = await openDatabase(path, version: 1);
        final columns = await testDb.rawQuery('PRAGMA table_info(products)');

        final hasStockRetail = columns.any(
          (col) => col['name'] == 'stock_retail',
        );
        final hasStockWholesale = columns.any(
          (col) => col['name'] == 'stock_wholesale',
        );

        await testDb.close();

        // Jika kolom tidak ada, hapus database lama
        if (!hasStockRetail || !hasStockWholesale) {
          print("⚠️ Database structure outdated, deleting old database...");
          await File(path).delete();
          print("✅ Old database deleted, will create new one");
        }
      } catch (e) {
        print("⚠️ Error checking database, deleting corrupt database...");
        try {
          await File(path).delete();
          print("✅ Corrupt database deleted");
        } catch (deleteError) {
          print("❌ Failed to delete database: $deleteError");
        }
      }
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// ✅ Migrasi database dengan error handling yang lebih baik
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("🔄 Upgrading database from version $oldVersion to $newVersion");

    if (oldVersion < 2) {
      try {
        // ✅ STEP 1: Cek dan tambah kolom di products
        print("📋 Checking products table structure...");
        final productsInfo = await db.rawQuery('PRAGMA table_info(products)');
        print(
          "Current products columns: ${productsInfo.map((e) => e['name']).toList()}",
        );

        final hasStockRetail = productsInfo.any(
          (col) => col['name'] == 'stock_retail',
        );
        final hasStockWholesale = productsInfo.any(
          (col) => col['name'] == 'stock_wholesale',
        );

        if (!hasStockRetail) {
          print("➕ Adding stock_retail column...");
          await db.execute(
            'ALTER TABLE products ADD COLUMN stock_retail INTEGER NOT NULL DEFAULT 0',
          );
          print("✅ stock_retail column added");
        } else {
          print("✓ stock_retail column already exists");
        }

        if (!hasStockWholesale) {
          print("➕ Adding stock_wholesale column...");
          await db.execute(
            'ALTER TABLE products ADD COLUMN stock_wholesale INTEGER NOT NULL DEFAULT 0',
          );
          print("✅ stock_wholesale column added");
        } else {
          print("✓ stock_wholesale column already exists");
        }

        // ✅ STEP 2: Cek dan tambah kolom di transaction_items
        print("📋 Checking transaction_items table structure...");
        final transItemsInfo = await db.rawQuery(
          'PRAGMA table_info(transaction_items)',
        );
        print(
          "Current transaction_items columns: ${transItemsInfo.map((e) => e['name']).toList()}",
        );

        final hasPriceType = transItemsInfo.any(
          (col) => col['name'] == 'price_type',
        );

        if (!hasPriceType) {
          print("➕ Adding price_type column...");
          await db.execute(
            'ALTER TABLE transaction_items ADD COLUMN price_type TEXT DEFAULT "retail"',
          );
          print("✅ price_type column added");
        } else {
          print("✓ price_type column already exists");
        }

        print("✅ Database structure upgrade completed");

        // ✅ STEP 3: Migrate existing data
        try {
          List<Map<String, dynamic>> products = await db.query('products');
          print("📦 Found ${products.length} products to check for migration");

          int migratedCount = 0;
          for (var product in products) {
            int productId = product['id'] as int;
            int currentStock = (product['stock'] as int?) ?? 0;
            int currentRetail = (product['stock_retail'] as int?) ?? 0;
            int currentWholesale = (product['stock_wholesale'] as int?) ?? 0;

            // ✅ Migrate jika stock_retail dan stock_wholesale masih 0
            if (currentRetail == 0 &&
                currentWholesale == 0 &&
                currentStock > 0) {
              int halfStock = (currentStock / 2).floor();

              await db.update(
                'products',
                {
                  'stock_retail': halfStock,
                  'stock_wholesale': currentStock - halfStock,
                },
                where: 'id = ?',
                whereArgs: [productId],
              );

              migratedCount++;
              print(
                "📝 Migrated product ID $productId: Stock $currentStock → Retail: $halfStock, Wholesale: ${currentStock - halfStock}",
              );
            } else if (currentStock == 0 &&
                currentRetail == 0 &&
                currentWholesale == 0) {
              print("⚠️ Product ID $productId has no stock (all zeros)");
            } else {
              print(
                "✓ Product ID $productId already has retail/wholesale stock",
              );
            }
          }

          print("✅ Data migration completed: $migratedCount products migrated");
        } catch (e) {
          print("❌ Error during data migration: $e");
          print("⚠️ Continuing despite migration error...");
        }

        print("🎉 Database successfully upgraded to version 2!");
      } catch (e) {
        print("❌ CRITICAL ERROR during upgrade: $e");
        print("Stack trace: ${StackTrace.current}");
        rethrow;
      }
    }
  }

  /// Membuat tabel ketika database baru dibuat
  Future _createDB(Database db, int version) async {
    print("Creating new database...");

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
        stock INTEGER NOT NULL DEFAULT 0,
        stock_retail INTEGER NOT NULL DEFAULT 0,
        stock_wholesale INTEGER NOT NULL DEFAULT 0
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
        price_type TEXT DEFAULT 'retail',
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    print("Tabel database berhasil dibuat!");
  }

  // ==========================
  // USERS FUNCTIONS
  // ==========================

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

  Future resetDatabase() async {
    final db = await database;
    await db.delete('transaction_items');
    await db.delete('transactions');
    await db.delete('products');
    await db.delete('users');
    print("Semua data berhasil dihapus!");
  }

  /// ✅ FORCE DELETE DATABASE (untuk testing atau fix corruption)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'warung_kita.sqlite');

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      print("🗑️ Database deleted: $path");
    }

    _database = null;
  }

  /// ✅ FORCE RECREATE DATABASE (hapus dan buat ulang)
  Future<void> recreateDatabase() async {
    await deleteDatabase();
    _database = await _initDB();
    print("🔄 Database recreated successfully");
  }

  /// ✅ FIX MIGRATION - Panggil ini jika migration gagal
  Future<void> fixMigration() async {
    final db = await database;

    try {
      print("🔧 Attempting to fix database migration...");

      // Cek dan fix products table
      final productsInfo = await db.rawQuery('PRAGMA table_info(products)');
      final hasStockRetail = productsInfo.any(
        (col) => col['name'] == 'stock_retail',
      );
      final hasStockWholesale = productsInfo.any(
        (col) => col['name'] == 'stock_wholesale',
      );

      if (!hasStockRetail) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN stock_retail INTEGER NOT NULL DEFAULT 0',
        );
        print("✅ Added stock_retail column");
      }

      if (!hasStockWholesale) {
        await db.execute(
          'ALTER TABLE products ADD COLUMN stock_wholesale INTEGER NOT NULL DEFAULT 0',
        );
        print("✅ Added stock_wholesale column");
      }

      // Cek dan fix transaction_items table
      final transInfo = await db.rawQuery(
        'PRAGMA table_info(transaction_items)',
      );
      final hasPriceType = transInfo.any((col) => col['name'] == 'price_type');

      if (!hasPriceType) {
        await db.execute(
          'ALTER TABLE transaction_items ADD COLUMN price_type TEXT DEFAULT "retail"',
        );
        print("✅ Added price_type column");
      }

      // Fix existing products with zero stock_retail/wholesale
      await db.execute('''
        UPDATE products 
        SET stock_retail = CAST(stock / 2 AS INTEGER),
            stock_wholesale = stock - CAST(stock / 2 AS INTEGER)
        WHERE stock_retail = 0 AND stock_wholesale = 0 AND stock > 0
      ''');

      print("✅ Migration fix completed successfully!");
    } catch (e) {
      print("❌ Error fixing migration: $e");
      rethrow;
    }
  }
}
