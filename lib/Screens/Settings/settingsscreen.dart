import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/services/backup_service.dart';
import 'dart:io';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final backupService = BackupService.instance;
  List<FileSystemEntity> backupFiles = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBackupFiles();
  }

  Future<void> _loadBackupFiles() async {
    setState(() => isLoading = true);
    final files = await backupService.getBackupFiles();
    setState(() {
      backupFiles = files;
      isLoading = false;
    });
  }

  Future<void> _backup() async {
    setState(() => isLoading = true);
    await backupService.backupDatabase(context);
    await _loadBackupFiles();
    setState(() => isLoading = false);
  }

  Future<void> _restore() async {
    setState(() => isLoading = true);
    final success = await backupService.restoreDatabase(context);
    if (success && mounted) {
      // Show dialog to restart app
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Restart Aplikasi'),
          content: const Text(
            'Database berhasil di-restore. Silakan tutup dan buka kembali aplikasi.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                // Exit app
                exit(0);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
    setState(() => isLoading = false);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Pengaturan',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/bgwarung2.jpg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Backup Section
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.backup,
                                  color: Colors.blue.shade700,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Backup Database',
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Simpan data ke penyimpanan',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Backup database akan menyimpan semua data produk, transaksi, dan user ke folder Download.',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _backup,
                              icon: const Icon(Icons.save_alt),
                              label: Text(
                                'Backup Sekarang',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Restore Section
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.restore,
                                  color: Colors.orange.shade700,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Restore Database',
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'Pulihkan data dari backup',
                                      style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber,
                                  color: Colors.red.shade700,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Restore akan mengganti semua data yang ada!',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.red.shade900,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _restore,
                              icon: const Icon(Icons.upload_file),
                              label: Text(
                                'Pilih File Backup',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Backup Files List
                  Text(
                    'File Backup Tersedia',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  backupFiles.isEmpty
                      ? Card(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.folder_open,
                                    size: 64,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Belum ada file backup',
                                    style: GoogleFonts.poppins(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: backupFiles.length,
                          itemBuilder: (context, index) {
                            final file = backupFiles[index];
                            final stat = file.statSync();
                            final fileName = file.path.split('/').last;
                            final fileSize = _formatFileSize(stat.size);
                            final modified = DateFormat(
                              'dd MMM yyyy, HH:mm',
                            ).format(stat.modified);

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Icon(
                                    Icons.insert_drive_file,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                title: Text(
                                  fileName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '$modified • $fileSize',
                                  style: GoogleFonts.poppins(fontSize: 11),
                                ),
                                trailing: const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                ),
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }
}
