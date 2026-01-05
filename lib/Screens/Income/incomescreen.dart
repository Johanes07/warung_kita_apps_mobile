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
  final printerService = PrinterService(); // ✅ Gunakan singleton
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

      printerService.printer.printNewLine();
      printerService.printer.printCustom("TOKO RIZKI", 3, 1);
      printerService.printer.printCustom("Transaksi #${trx['id']}", 1, 1);
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
          content: Text("Struk Transaksi #${trx['id']} berhasil dicetak"),
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
  void _showTransactionActions(Map<String, dynamic> trx) {
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
                "Transaksi #${trx['id']}",
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

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            "Detail Transaksi #${trx['id']}",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: items.isEmpty
              ? const Text("Tidak ada detail belanja")
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: items.length,
                    itemBuilder: (context, idx) {
                      final item = items[idx];
                      final priceType = item['price_type'] ?? 'retail';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item['name'],
                                style: GoogleFonts.poppins(),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: priceType == 'retail'
                                    ? Colors.green.withOpacity(0.2)
                                    : Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                priceType == 'retail' ? 'Eceran' : 'Grosir',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: priceType == 'retail'
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text("Qty: ${item['quantity']}"),
                        trailing: Text(
                          formatCurrency.format(
                            item['price'] * item['quantity'],
                          ),
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Tutup"),
            ),
          ],
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
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        leading: const Icon(
                                          Icons.receipt_long,
                                          color: Colors.green,
                                        ),
                                        title: Text(
                                          "Transaksi #${trx['id']}",
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        subtitle: Text(
                                          DateFormat(
                                            'dd MMM yyyy, HH:mm',
                                          ).format(
                                            DateTime.parse(trx['created_at']),
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
