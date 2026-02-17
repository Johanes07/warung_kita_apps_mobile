import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  // Method untuk reset database instance (digunakan saat restore)
  void resetDatabaseInstance() {
    _database = null;
  }

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
      debugPrint("Database belum ada, membuat database baru...");
      await Directory(dirname(path)).create(recursive: true);
    } else {
      debugPrint("Database sudah ada di: $path");

      // ✅ CEK STRUKTUR DATABASE, HAPUS JIKA CORRUPT ATAU STRUKTUR LAMA
      try {
        final testDb = await openDatabase(path, version: 1);
        final columns = await testDb.rawQuery('PRAGMA table_info(products)');

        // Cek apakah masih pakai struktur lama (stock_retail/stock_wholesale)
        final hasStockRetail = columns.any(
          (col) => col['name'] == 'stock_retail',
        );
        final hasStockWholesale = columns.any(
          (col) => col['name'] == 'stock_wholesale',
        );

        // Cek apakah sudah pakai struktur baru (base_unit)
        final hasBaseUnit = columns.any((col) => col['name'] == 'base_unit');
        final hasUnit = columns.any((col) => col['name'] == 'unit');

        await testDb.close();

        // Hapus database jika masih pakai struktur lama (retail/wholesale)
        if ((hasStockRetail || hasStockWholesale) && !hasUnit && !hasBaseUnit) {
          debugPrint(
            "⚠️ Database structure outdated (old retail/wholesale system), deleting...",
          );
          await File(path).delete();
          debugPrint("✅ Old database deleted, will create new one");
        }
      } catch (e) {
        debugPrint("⚠️ Error checking database, deleting corrupt database...");
        try {
          await File(path).delete();
          debugPrint("✅ Corrupt database deleted");
        } catch (deleteError) {
          debugPrint("❌ Failed to delete database: $deleteError");
        }
      }
    }

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// ✅ Migrasi database dengan error handling yang lebih baik
  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint("🔄 Upgrading database from version $oldVersion to $newVersion");

    // Migration untuk mengubah email ke username (version 5)
    if (oldVersion < 5) {
      debugPrint("⚠️ Migrating users table: email → username...");

      final usersInfo = await db.rawQuery('PRAGMA table_info(users)');
      final hasEmail = usersInfo.any((col) => col['name'] == 'email');
      final hasUsername = usersInfo.any((col) => col['name'] == 'username');

      if (hasEmail && !hasUsername) {
        // Buat tabel users baru dengan username
        await db.execute('''
          CREATE TABLE users_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            username TEXT UNIQUE NOT NULL,
            password TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
          )
        ''');

        // Copy data, gunakan email sebagai username
        await db.execute('''
          INSERT INTO users_new (id, name, username, password, created_at)
          SELECT id, name, email, password, created_at FROM users
        ''');

        await db.execute('DROP TABLE users');
        await db.execute('ALTER TABLE users_new RENAME TO users');

        debugPrint("✅ Users table migrated successfully");
      }
    }

    // Cek struktur saat ini
    final productsInfo = await db.rawQuery('PRAGMA table_info(products)');
    final hasBaseUnit = productsInfo.any((col) => col['name'] == 'base_unit');
    final hasBasePrice = productsInfo.any((col) => col['name'] == 'base_price');
    final hasUnit = productsInfo.any((col) => col['name'] == 'unit');

    // Jika sudah ada base_unit dan base_price, berarti struktur sudah benar (versi 4)
    if (hasBaseUnit && hasBasePrice) {
      debugPrint("✅ Database structure is already up to date");
      return;
    }

    // Jika ada 'unit' tapi belum ada 'base_unit', upgrade dari v3 ke v4
    if (hasUnit && !hasBaseUnit && oldVersion == 3) {
      debugPrint(
        "⚠️ Upgrading from version 3 to 4 (adding multi-unit support)...",
      );

      // Buat tabel product_units
      await db.execute('''
        CREATE TABLE IF NOT EXISTS product_units (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          unit_name TEXT NOT NULL,
          conversion_rate REAL NOT NULL,
          price INTEGER NOT NULL,
          FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
        )
      ''');

      // Rename kolom di products table (SQLite tidak support RENAME COLUMN langsung di versi lama)
      // Jadi kita buat tabel baru dan copy data
      await db.execute('''
        CREATE TABLE products_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          barcode TEXT UNIQUE NOT NULL,
          base_unit TEXT NOT NULL,
          base_price INTEGER NOT NULL,
          stock REAL NOT NULL DEFAULT 0,
          min_stock REAL NOT NULL DEFAULT 0
        )
      ''');

      await db.execute('''
        INSERT INTO products_new (id, name, barcode, base_unit, base_price, stock, min_stock)
        SELECT id, name, barcode, unit, price, stock, min_stock FROM products
      ''');

      await db.execute('DROP TABLE products');
      await db.execute('ALTER TABLE products_new RENAME TO products');

      // Tambah kolom unit_name di transaction_items jika belum ada
      final transItemsInfo = await db.rawQuery(
        'PRAGMA table_info(transaction_items)',
      );
      final hasUnitName = transItemsInfo.any(
        (col) => col['name'] == 'unit_name',
      );

      if (!hasUnitName) {
        await db.execute('''
          CREATE TABLE transaction_items_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transaction_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            quantity REAL NOT NULL,
            unit_name TEXT NOT NULL,
            price INTEGER NOT NULL,
            FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
            FOREIGN KEY(product_id) REFERENCES products(id)
          )
        ''');

        await db.execute('''
          INSERT INTO transaction_items_new (id, transaction_id, product_id, quantity, unit_name, price)
          SELECT ti.id, ti.transaction_id, ti.product_id, ti.quantity, p.base_unit, ti.price
          FROM transaction_items ti
          LEFT JOIN products p ON ti.product_id = p.id
        ''');

        await db.execute('DROP TABLE transaction_items');
        await db.execute(
          'ALTER TABLE transaction_items_new RENAME TO transaction_items',
        );
      }

      debugPrint("✅ Database upgraded to version 4 successfully");
      return;
    }

    // Jika struktur sangat berbeda, recreate database
    debugPrint("⚠️ Major schema change detected, recreating database...");
    await db.execute('DROP TABLE IF EXISTS product_units');
    await db.execute('DROP TABLE IF EXISTS transaction_items');
    await db.execute('DROP TABLE IF EXISTS transactions');
    await db.execute('DROP TABLE IF EXISTS products');
    await db.execute('DROP TABLE IF EXISTS users');

    await _createDB(db, newVersion);
    debugPrint("✅ Database recreated with new structure");
  }

  /// Membuat tabel ketika database baru dibuat
  Future _createDB(Database db, int version) async {
    debugPrint("Creating new database...");

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        username TEXT UNIQUE NOT NULL,
        password TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        barcode TEXT UNIQUE NOT NULL,
        base_unit TEXT NOT NULL,
        base_price INTEGER NOT NULL,
        stock REAL NOT NULL DEFAULT 0,
        min_stock REAL NOT NULL DEFAULT 0,
        image_path TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        unit_name TEXT NOT NULL,
        conversion_rate REAL NOT NULL,
        price INTEGER NOT NULL,
        image_path TEXT,
        FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        total_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL DEFAULT 'cash',
        cash_received INTEGER NOT NULL DEFAULT 0,
        change_amount INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY(user_id) REFERENCES users(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS transaction_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaction_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity REAL NOT NULL,
        unit_name TEXT NOT NULL,
        price INTEGER NOT NULL,
        FOREIGN KEY(transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    debugPrint("Tabel database berhasil dibuat!");
  }

  // ==========================
  // USERS FUNCTIONS
  // ==========================

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final db = await database;
    final users = await db.query('users', orderBy: 'created_at DESC');
    debugPrint("List user: $users");
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
  // PRODUCT UNITS FUNCTIONS
  // ==========================
  Future<List<Map<String, dynamic>>> getProductUnits(int productId) async {
    final db = await database;
    return await db.query(
      'product_units',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'conversion_rate ASC',
    );
  }

  Future<int> addProductUnit(
    int productId,
    String unitName,
    double conversionRate,
    int price, {
    String? imagePath,
  }) async {
    final db = await database;
    return await db.insert('product_units', {
      'product_id': productId,
      'unit_name': unitName,
      'conversion_rate': conversionRate,
      'price': price,
      'image_path': imagePath,
    });
  }

  Future<void> deleteProductUnit(int unitId) async {
    final db = await database;
    await db.delete('product_units', where: 'id = ?', whereArgs: [unitId]);
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
    await db.delete('product_units');
    await db.delete('transaction_items');
    await db.delete('transactions');
    await db.delete('products');
    await db.delete('users');
    debugPrint("Semua data berhasil dihapus!");
  }

  /// ✅ FORCE DELETE DATABASE (untuk testing atau fix corruption)
  Future<void> deleteDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'warung_kita.sqlite');

    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      debugPrint("🗑️ Database deleted: $path");
    }

    _database = null;
  }

  /// ✅ FORCE RECREATE DATABASE (hapus dan buat ulang)
  Future<void> recreateDatabase() async {
    await deleteDatabase();
    _database = await _initDB();
    debugPrint("🔄 Database recreated successfully");
  }
}
