import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:warung_kita/db/database_helper.dart';

class BackupService {
  static final BackupService instance = BackupService._init();
  BackupService._init();

  final dbHelper = DatabaseHelper.instance;

  /// Request storage permission
  Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status.isDenied) {
        final manageStatus = await Permission.manageExternalStorage.request();
        return manageStatus.isGranted;
      }
      return status.isGranted;
    }
    return true;
  }

  /// Backup database to Downloads folder
  Future<String?> backupDatabase(BuildContext context) async {
    try {
      // Request permission
      final hasPermission = await _requestPermission();
      if (!hasPermission) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin penyimpanan diperlukan untuk backup'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return null;
      }

      // Get database path
      final dbPath = await dbHelper.database;
      final dbFile = File(dbPath.path);

      if (!await dbFile.exists()) {
        throw Exception('Database file not found');
      }

      // Create backup filename with timestamp
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final backupFileName = 'warung_kita_backup_$timestamp.db';

      // Get Downloads directory
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) {
        throw Exception('Could not access storage directory');
      }

      // Create backup file path
      final backupPath = join(downloadsDir.path, backupFileName);

      // Copy database file
      await dbFile.copy(backupPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup berhasil!\nLokasi: ${downloadsDir.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }

      return backupPath;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal backup: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  /// Restore database from file
  Future<bool> restoreDatabase(BuildContext context) async {
    try {
      // Request permission
      final hasPermission = await _requestPermission();
      if (!hasPermission) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin penyimpanan diperlukan untuk restore'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      // Pick backup file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
      );

      if (result == null || result.files.single.path == null) {
        return false;
      }

      final pickedFile = File(result.files.single.path!);

      // Validasi file harus .db
      if (!pickedFile.path.endsWith('.db')) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('File harus berformat .db'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return false;
      }

      if (!await pickedFile.exists()) {
        throw Exception('File tidak ditemukan');
      }

      // Validasi struktur database
      final isValid = await _validateDatabaseStructure(pickedFile);
      if (!isValid) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'File database tidak valid atau versi tidak kompatibel.\n'
                'Database akan otomatis diupgrade setelah restore.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        // Tetap lanjutkan, biarkan migration handle
      }

      // Show confirmation dialog
      if (context.mounted) {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Konfirmasi Restore'),
            content: const Text(
              'Restore database akan mengganti semua data yang ada. '
              'Pastikan Anda sudah backup data saat ini.\n\n'
              'Lanjutkan?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text(
                  'Ya, Restore',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );

        if (confirm != true) {
          return false;
        }
      }

      // Get current database path
      final db = await dbHelper.database;
      final dbPath = db.path;

      // Close database connection
      await db.close();

      // Wait a bit to ensure database is fully closed
      await Future.delayed(const Duration(milliseconds: 500));

      // Replace database file
      final dbFile = File(dbPath);

      // Backup current database first (safety measure)
      final tempBackupPath = '$dbPath.temp_backup';
      if (await dbFile.exists()) {
        await dbFile.copy(tempBackupPath);
      }

      try {
        // Copy new database
        await pickedFile.copy(dbPath);

        // Delete temp backup if successful
        final tempBackup = File(tempBackupPath);
        if (await tempBackup.exists()) {
          await tempBackup.delete();
        }
      } catch (e) {
        // Restore from temp backup if copy failed
        final tempBackup = File(tempBackupPath);
        if (await tempBackup.exists()) {
          await tempBackup.copy(dbPath);
          await tempBackup.delete();
        }
        throw Exception('Gagal menyalin file database: $e');
      }

      // Reinitialize database (akan trigger migration jika perlu)
      dbHelper.resetDatabaseInstance();
      await dbHelper.database;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Restore berhasil! Database telah diupgrade ke versi terbaru.\n'
              'Silakan restart aplikasi.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal restore: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return false;
    }
  }

  /// Validate database structure
  Future<bool> _validateDatabaseStructure(File dbFile) async {
    try {
      // Import sqflite untuk validasi
      final db = await openDatabase(dbFile.path, readOnly: true);

      // Cek tabel yang wajib ada
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Tabel wajib
      final requiredTables = [
        'users',
        'products',
        'transactions',
        'transaction_items',
      ];

      for (final table in requiredTables) {
        if (!tableNames.contains(table)) {
          await db.close();
          return false;
        }
      }

      await db.close();
      return true;
    } catch (e) {
      debugPrint('Error validating database: $e');
      return false;
    }
  }

  /// Get list of backup files
  Future<List<FileSystemEntity>> getBackupFiles() async {
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      if (downloadsDir == null) return [];

      final files = downloadsDir
          .listSync()
          .where(
            (file) =>
                file.path.contains('warung_kita_backup') &&
                file.path.endsWith('.db'),
          )
          .toList();

      // Sort by date (newest first)
      files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );

      return files;
    } catch (e) {
      return [];
    }
  }
}

