import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> transactions = [];
  bool isLoading = true;

  DateTimeRange? selectedRange;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
      ),
    );
  }

  pw.Widget _tableCell(String text, {pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        textAlign: align,
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  }

  /// ✅ MENGHITUNG NOMOR TRANSAKSI PER HARI
  Future<int> _getDailyTransactionNumber(Map<String, dynamic> trx) async {
    final db = await dbHelper.database;

    String transactionDate = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.parse(trx['created_at'].toString()));

    // Hitung berapa transaksi di hari yang sama sebelum transaksi ini
    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM transactions
      WHERE DATE(created_at) = ? AND id <= ?
      ORDER BY created_at ASC
    ''',
      [transactionDate, trx['id']],
    );

    return (result.first['count'] ?? 0) as int;
  }

  /// ================= LOAD TRANSAKSI =================
  Future<void> _loadTransactions() async {
    final db = await dbHelper.database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (selectedRange != null) {
      String startDate = DateFormat('yyyy-MM-dd').format(selectedRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(selectedRange!.end);

      whereClause = 'WHERE DATE(created_at) BETWEEN ? AND ?';
      whereArgs = [startDate, endDate];
    }

    final listResult = await db.rawQuery('''
      SELECT * FROM transactions 
      $whereClause 
      ORDER BY created_at ASC
    ''', whereArgs);

    setState(() {
      transactions = listResult;
      isLoading = false;
    });
  }

  /// ✅ AMBIL DETAIL PRODUK DARI TRANSAKSI
  Future<List<Map<String, dynamic>>> _getTransactionItems(
    int transactionId,
  ) async {
    final db = await dbHelper.database;
    final result = await db.rawQuery(
      '''
      SELECT ti.*, p.name 
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''',
      [transactionId],
    );
    return result;
  }

  /// ================= RESET TRANSAKSI =================
  Future<void> _resetTransactions() async {
    final db = await dbHelper.database;
    await db.delete('transactions');
    await db.delete('transaction_items');

    setState(() {
      transactions.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Data transaksi berhasil direset")),
    );
  }

  void _confirmReset() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Konfirmasi Reset"),
        content: const Text(
          "Apakah Anda yakin ingin menghapus semua data transaksi?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _resetTransactions();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Hapus"),
          ),
        ],
      ),
    );
  }

  /// ================= EXPORT PDF DETAIL =================
  Future<void> _exportPDF() async {
    if (transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Tidak ada data transaksi untuk dicetak")),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final pdf = pw.Document();
    final formatCurrency = NumberFormat.currency(
      locale: 'id',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    // ✅ Load semua detail transaksi dengan produknya DAN nomor urut per hari
    List<Map<String, dynamic>> detailedTransactions = [];
    for (var trx in transactions) {
      final items = await _getTransactionItems(trx['id']);
      final dailyNumber = await _getDailyTransactionNumber(trx);
      detailedTransactions.add({
        'transaction': trx,
        'items': items,
        'dailyNumber': dailyNumber,
      });
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          /// ===== HEADER =====
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  "TOKO RIZKI",
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  "Laporan Riwayat Transaksi Detail",
                  style: pw.TextStyle(fontSize: 14, color: PdfColors.grey700),
                ),
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 1),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          /// ===== INFO =====
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "Tanggal Cetak:",
                style: const pw.TextStyle(fontSize: 10),
              ),
              pw.Text(
                DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ],
          ),

          if (selectedRange != null)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("Periode:", style: const pw.TextStyle(fontSize: 10)),
                pw.Text(
                  "${DateFormat('dd MMM yyyy').format(selectedRange!.start)} - ${DateFormat('dd MMM yyyy').format(selectedRange!.end)}",
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),

          pw.SizedBox(height: 20),

          /// ✅ DETAIL SETIAP TRANSAKSI dengan nomor urut per hari
          ...detailedTransactions.map((data) {
            final trx = data['transaction'];
            final items = data['items'] as List<Map<String, dynamic>>;
            final dailyNumber = data['dailyNumber'];

            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 20),
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  /// Header Transaksi dengan nomor urut per hari
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        "Transaksi #$dailyNumber",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      pw.Text(
                        DateFormat(
                          'dd MMM yyyy, HH:mm',
                        ).format(DateTime.parse(trx['created_at'])),
                        style: const pw.TextStyle(fontSize: 10),
                      ),
                    ],
                  ),

                  pw.SizedBox(height: 8),
                  pw.Divider(thickness: 0.5),
                  pw.SizedBox(height: 8),

                  /// Tabel Detail Produk
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3), // Nama Produk
                      1: const pw.FlexColumnWidth(1), // Qty
                      2: const pw.FlexColumnWidth(1.5), // Harga
                      3: const pw.FlexColumnWidth(1.5), // Subtotal
                      4: const pw.FlexColumnWidth(1), // Tipe
                    },
                    children: [
                      /// Header Tabel Produk
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          _tableHeader("Produk"),
                          _tableHeader("Qty"),
                          _tableHeader("Harga"),
                          _tableHeader("Subtotal"),
                          _tableHeader("Tipe"),
                        ],
                      ),

                      /// Data Produk
                      ...items.map((item) {
                        final qty = item['quantity'];
                        final price = item['price'];
                        final subtotal = qty * price;
                        final priceType = item['price_type'] ?? 'retail';

                        return pw.TableRow(
                          children: [
                            _tableCell(item['name']),
                            _tableCell(
                              qty.toString(),
                              align: pw.TextAlign.center,
                            ),
                            _tableCell(
                              formatCurrency.format(price),
                              align: pw.TextAlign.right,
                            ),
                            _tableCell(
                              formatCurrency.format(subtotal),
                              align: pw.TextAlign.right,
                            ),
                            _tableCell(
                              priceType == 'retail' ? 'Eceran' : 'Grosir',
                              align: pw.TextAlign.center,
                            ),
                          ],
                        );
                      }).toList(),
                    ],
                  ),

                  pw.SizedBox(height: 8),

                  /// Total Transaksi
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Text(
                        "TOTAL: ",
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                      pw.Text(
                        formatCurrency.format(trx['total_amount']),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 12,
                          color: PdfColors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),

          pw.SizedBox(height: 20),

          /// ===== SUMMARY =====
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "Ringkasan Keseluruhan",
                  style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Total Transaksi"),
                    pw.Text(totalTransactions.toString()),
                  ],
                ),
                pw.SizedBox(height: 4),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Total Pendapatan"),
                    pw.Text(
                      formatCurrency.format(totalRevenue),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 24),

          /// ===== FOOTER =====
          pw.Center(
            child: pw.Text(
              "Terima kasih telah menggunakan sistem TOKO RIZKI",
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ),
        ],
      ),
    );

    // Close loading
    Navigator.pop(context);

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  /// ================= RINGKASAN DATA =================
  int get totalTransactions => transactions.length;

  int get totalRevenue {
    return transactions.fold<int>(
      0,
      (sum, trx) => sum + (trx['total_amount'] as int),
    );
  }

  /// ================= PILIH RANGE TANGGAL =================
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange:
          selectedRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );

    if (picked != null) {
      setState(() {
        selectedRange = picked;
        isLoading = true;
      });
      await _loadTransactions();
    }
  }

  /// ✅ Reset filter (tampilkan semua)
  void _resetFilter() {
    setState(() {
      selectedRange = null;
      isLoading = true;
    });
    _loadTransactions();
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency = NumberFormat.currency(
      locale: 'id',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          "Riwayat Transaksi",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: const Color.fromARGB(255, 0, 0, 0),
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/bgwarung2.jpg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            tooltip: "Reset Data",
            onPressed: _confirmReset,
          ),
        ],
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadTransactions,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      /// ===== INFO PERIODE =====
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today,
                                  color: Colors.blueAccent,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Periode Laporan",
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              selectedRange != null
                                  ? "${DateFormat('dd MMM yyyy').format(selectedRange!.start)} - ${DateFormat('dd MMM yyyy').format(selectedRange!.end)}"
                                  : "Semua Transaksi",
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    icon: const Icon(Icons.date_range),
                                    label: Text(
                                      selectedRange != null
                                          ? "Ubah Periode"
                                          : "Pilih Periode",
                                      style: GoogleFonts.poppins(),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      side: const BorderSide(
                                        color: Colors.blueAccent,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: _pickDateRange,
                                  ),
                                ),
                                if (selectedRange != null) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    color: Colors.red,
                                    tooltip: "Reset Filter",
                                    onPressed: _resetFilter,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      /// ===== RINGKASAN =====
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              title: "Total Transaksi",
                              value: "$totalTransactions",
                              color: Colors.orange,
                              icon: Icons.receipt_long,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              title: "Total Pendapatan",
                              value: formatCurrency.format(totalRevenue),
                              color: Colors.green,
                              icon: Icons.attach_money,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      /// ===== TOMBOL EXPORT PDF =====
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.picture_as_pdf,
                              size: 64,
                              color: Colors.red.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Export Laporan PDF Detail",
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              transactions.isEmpty
                                  ? "Tidak ada data untuk dicetak"
                                  : "Cetak laporan transaksi lengkap dengan detail produk",
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.download),
                                label: Text(
                                  "Cetak Laporan PDF",
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade400,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                onPressed: transactions.isEmpty
                                    ? null
                                    : _exportPDF,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      /// ===== INFO =====
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue.shade700,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                "Laporan PDF akan menampilkan nomor transaksi sesuai urutan per hari dan detail lengkap produk yang dibeli",
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.blue.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  /// Widget untuk ringkasan
  Widget _buildSummaryCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.poppins(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
