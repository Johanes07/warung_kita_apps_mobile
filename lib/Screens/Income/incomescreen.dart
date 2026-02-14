import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:warung_kita/Screens/Cashier/cashierscreen.dart';
import 'package:warung_kita/services/printer_service.dart';

class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  final dbHelper = DatabaseHelper.instance;
  final printerService = PrinterService();
  final formatCurrency = NumberFormat.currency(
    locale: 'id',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  DateTimeRange? selectedDateRange;
  int totalIncome = 0;
  int retailIncome = 0;
  int wholesaleIncome = 0;
  List<Map<String, dynamic>> transactions = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadIncomeData();
  }

  Future<void> _loadIncomeData() async {
    final db = await dbHelper.database;

    String whereClause = "";
    List<dynamic> whereArgs = [];

    if (selectedDateRange != null) {
      String startDate = DateFormat(
        'yyyy-MM-dd',
      ).format(selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(selectedDateRange!.end);
      whereClause = "WHERE DATE(t.created_at) BETWEEN ? AND ?";
      whereArgs = [startDate, endDate];
    } else {
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      whereClause = "WHERE DATE(t.created_at) = ?";
      whereArgs = [today];
    }

    final totalResult = await db.rawQuery('''
      SELECT SUM(total_amount) as total FROM transactions t $whereClause
    ''', whereArgs);

    final retailResult = await db.rawQuery('''
      SELECT SUM(ti.quantity * ti.price) as total
      FROM transaction_items ti
      JOIN transactions t ON ti.transaction_id = t.id
      $whereClause AND ti.price_type = 'retail'
    ''', whereArgs);

    final wholesaleResult = await db.rawQuery('''
      SELECT SUM(ti.quantity * ti.price) as total
      FROM transaction_items ti
      JOIN transactions t ON ti.transaction_id = t.id
      $whereClause AND ti.price_type = 'wholesale'
    ''', whereArgs);

    final listResult = await db.rawQuery('''
      SELECT * FROM transactions t $whereClause ORDER BY t.created_at DESC
    ''', whereArgs);

    setState(() {
      totalIncome = (totalResult.first['total'] ?? 0) as int;
      retailIncome = (retailResult.first['total'] ?? 0) as int;
      wholesaleIncome = (wholesaleResult.first['total'] ?? 0) as int;
      transactions = listResult;
      isLoading = false;
    });
  }

  Future<List<Map<String, dynamic>>> _getTransactionItems(
    int transactionId,
  ) async {
    final db = await dbHelper.database;

    final result = await db.rawQuery(
      '''
      SELECT ti.*, p.name, p.price_retail, p.price_wholesale, p.stock_retail, p.stock_wholesale
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''',
      [transactionId],
    );

    return result;
  }

  /// ✅ MENGHITUNG NOMOR TRANSAKSI PER HARI
  Future<int> _getDailyTransactionNumber(Map<String, dynamic> trx) async {
    final db = await dbHelper.database;

    String transactionDate = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.parse(trx['created_at']));

    // Hitung berapa transaksi di hari yang sama sebelum transaksi ini (termasuk transaksi ini)
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

  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange:
          selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
    );

    if (picked != null) {
      setState(() {
        selectedDateRange = picked;
      });
      _loadIncomeData();
    }
  }

  /// ✅ CETAK ULANG STRUK - Menggunakan PrinterService
  Future<void> _reprintReceipt(Map<String, dynamic> trx) async {
    if (!printerService.connected || printerService.selectedDevice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Printer belum terhubung. Silakan hubungkan printer di halaman utama.",
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final items = await _getTransactionItems(trx['id']);
      final dailyNumber = await _getDailyTransactionNumber(trx);

      printerService.printer.printNewLine();
      printerService.printer.printCustom("TOKO RIZKI", 3, 1);
      printerService.printer.printCustom("Transaksi #$dailyNumber", 1, 1);
      printerService.printer.printCustom(
        DateFormat(
          'dd MMM yyyy, HH:mm',
        ).format(DateTime.parse(trx['created_at'])),
        1,
        1,
      );
      printerService.printer.printNewLine();

      for (var item in items) {
        final name = item['name'];
        final qty = item['quantity'];
        final price = item['price'];
        final subtotal = qty * price;
        final priceType = item['price_type'] ?? 'retail';

        printerService.printer.printLeftRight(
          name,
          formatCurrency.format(subtotal),
          1,
        );
        printerService.printer.printCustom(
          "$qty x ${formatCurrency.format(price)} (${priceType == 'retail' ? 'Eceran' : 'Grosir'})",
          0,
          0,
        );
      }

      printerService.printer.printNewLine();
      printerService.printer.printLeftRight(
        "TOTAL",
        formatCurrency.format(trx['total_amount']),
        2,
      );
      printerService.printer.printNewLine();
      printerService.printer.printCustom(
        "Terima kasih telah berbelanja!",
        1,
        1,
      );
      printerService.printer.printCustom("--- CETAK ULANG ---", 0, 1);
      printerService.printer.printNewLine();
      printerService.printer.printNewLine();

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Struk Transaksi #$dailyNumber berhasil dicetak"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Gagal cetak struk: $e")));
    }
  }

  /// ✅ EDIT TRANSAKSI - NAVIGASI KE CASHIER SCREEN
  Future<void> _editTransaction(Map<String, dynamic> trx) async {
    final items = await _getTransactionItems(trx['id']);

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CashierScreen(
          editMode: true,
          transactionId: trx['id'],
          existingCart: items,
        ),
      ),
    );

    if (result == true) {
      _loadIncomeData();
    }
  }

  /// ✅ DIALOG AKSI TRANSAKSI (Lihat Detail, Edit, atau Cetak)
  void _showTransactionActions(Map<String, dynamic> trx) async {
    final dailyNumber = await _getDailyTransactionNumber(trx);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                "Transaksi #$dailyNumber",
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                DateFormat(
                  'dd MMM yyyy, HH:mm',
                ).format(DateTime.parse(trx['created_at'])),
                style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              /// ✅ Tombol Lihat Detail
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Icon(Icons.info_outline, color: Colors.white),
                ),
                title: Text(
                  "Lihat Detail",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text("Lihat daftar produk yang dibeli"),
                onTap: () {
                  Navigator.pop(context);
                  _showTransactionDetail(trx);
                },
              ),

              /// ✅ Tombol Edit Transaksi
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.orange,
                  child: Icon(Icons.edit, color: Colors.white),
                ),
                title: Text(
                  "Edit Transaksi",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text("Ubah produk di halaman kasir"),
                onTap: () {
                  Navigator.pop(context);
                  _editTransaction(trx);
                },
              ),

              /// ✅ Tombol Cetak Ulang
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: printerService.connected
                      ? Colors.green
                      : Colors.grey,
                  child: const Icon(Icons.print, color: Colors.white),
                ),
                title: Text(
                  "Cetak Ulang Struk",
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  printerService.connected
                      ? "Printer siap"
                      : "Printer belum terhubung",
                  style: TextStyle(
                    fontSize: 12,
                    color: printerService.connected ? Colors.green : Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _reprintReceipt(trx);
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// Dialog Detail Transaksi
  void _showTransactionDetail(Map<String, dynamic> trx) async {
    final items = await _getTransactionItems(trx['id']);
    final dailyNumber = await _getDailyTransactionNumber(trx);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.blue.shade600, Colors.blue.shade400],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.receipt_long,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Detail Transaksi",
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              "#$dailyNumber",
                              style: GoogleFonts.poppins(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Content
                items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.inventory_2_outlined,
                              size: 64,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              "Tidak ada detail belanja",
                              style: GoogleFonts.poppins(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.5,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: Colors.grey.shade200, height: 1),
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            final priceType = item['price_type'] ?? 'retail';
                            final isRetail = priceType == 'retail';

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Number badge
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      "${idx + 1}",
                                      style: GoogleFonts.poppins(
                                        color: Colors.blue.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),

                                  // Product info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['name'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isRetail
                                                    ? Colors.green.shade50
                                                    : Colors.orange.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isRetail
                                                      ? Colors.green.shade200
                                                      : Colors.orange.shade200,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    isRetail
                                                        ? Icons
                                                              .shopping_bag_outlined
                                                        : Icons
                                                              .inventory_outlined,
                                                    size: 10,
                                                    color: isRetail
                                                        ? Colors.green.shade700
                                                        : Colors
                                                              .orange
                                                              .shade700,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    isRetail
                                                        ? 'Eceran'
                                                        : 'Grosir',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isRetail
                                                          ? Colors
                                                                .green
                                                                .shade700
                                                          : Colors
                                                                .orange
                                                                .shade700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "Qty: ${item['quantity']}",
                                              style: GoogleFonts.poppins(
                                                fontSize: 12,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Price
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        formatCurrency.format(
                                          item['price'] * item['quantity'],
                                        ),
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                      Text(
                                        "${formatCurrency.format(item['price'])} × ${item['quantity']}",
                                        style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                const SizedBox(height: 20),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey.shade100,
                      foregroundColor: Colors.grey.shade700,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      "Tutup",
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: Text(
          "Pemasukan",
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: const Color.fromARGB(255, 0, 0, 0),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // ✅ Status printer (simplified)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Center(
              child: Icon(
                Icons.print,
                color: printerService.connected ? Colors.green : Colors.grey,
                size: 24,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.date_range,
              color: Color.fromARGB(255, 0, 0, 0),
            ),
            tooltip: "Pilih Range Tanggal",
            onPressed: _pickDateRange,
          ),
        ],
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
          : RefreshIndicator(
              onRefresh: _loadIncomeData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // ✅ Banner status printer
                    if (!printerService.connected)
                      Container(
                        color: Colors.orange.shade50,
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Printer belum terhubung. Hubungkan di halaman utama untuk cetak struk.",
                                style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.orange.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    Container(
                      margin: const EdgeInsets.all(16),
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Total Pemasukan",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            formatCurrency.format(totalIncome),
                            style: GoogleFonts.poppins(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (selectedDateRange != null)
                            Text(
                              "${DateFormat('dd MMM yyyy').format(selectedDateRange!.start)} - ${DateFormat('dd MMM yyyy').format(selectedDateRange!.end)}",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            )
                          else
                            Text(
                              "Hari ini",
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.shopping_bag,
                                    color: Colors.green,
                                    size: 30,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Pendapatan Eceran",
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatCurrency.format(retailIncome),
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.store,
                                    color: Colors.orange,
                                    size: 30,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    "Pendapatan Grosir",
                                    style: GoogleFonts.poppins(fontSize: 12),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatCurrency.format(wholesaleIncome),
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Riwayat Transaksi",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          transactions.isEmpty
                              ? const Center(child: Text("Tidak ada transaksi"))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: transactions.length,
                                  itemBuilder: (context, index) {
                                    final trx = transactions[index];
                                    return FutureBuilder<int>(
                                      future: _getDailyTransactionNumber(trx),
                                      builder: (context, snapshot) {
                                        final dailyNumber =
                                            snapshot.data ?? trx['id'];

                                        return Card(
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: ListTile(
                                            leading: const Icon(
                                              Icons.receipt_long,
                                              color: Colors.green,
                                            ),
                                            title: Text(
                                              "Transaksi #$dailyNumber",
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Text(
                                              DateFormat(
                                                'dd MMM yyyy, HH:mm',
                                              ).format(
                                                DateTime.parse(
                                                  trx['created_at'],
                                                ),
                                              ),
                                            ),
                                            trailing: Text(
                                              formatCurrency.format(
                                                trx['total_amount'],
                                              ),
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green,
                                              ),
                                            ),
                                            onTap: () =>
                                                _showTransactionActions(trx),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
