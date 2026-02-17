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

    final listResult = await db.rawQuery('''
      SELECT * FROM transactions t $whereClause ORDER BY t.created_at DESC
    ''', whereArgs);

    setState(() {
      totalIncome = (totalResult.first['total'] ?? 0) as int;
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
      SELECT ti.*, p.name, p.base_unit, p.stock
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''',
      [transactionId],
    );

    return result;
  }

  Future<int> _getDailyTransactionNumber(Map<String, dynamic> trx) async {
    final db = await dbHelper.database;

    String transactionDate = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.parse(trx['created_at']));

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

  Future<void> _reprintReceipt(Map<String, dynamic> trx) async {
    if (!printerService.connected || printerService.selectedDevice == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Printer belum terhubung. Silakan hubungkan printer di halaman utama.",
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
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
        final unit = item['unit_name'] ?? 'pcs';
        final subtotal = (qty * price).round();

        final qtyStr = (qty is double ? qty : (qty as num).toDouble())
            .toStringAsFixed((qty % 1 == 0) ? 0 : 1);

        printerService.printer.printLeftRight(
          name,
          formatCurrency.format(subtotal),
          1,
        );
        printerService.printer.printCustom(
          "$qtyStr $unit x ${formatCurrency.format(price)}",
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

      final paymentMethod = trx['payment_method'] ?? 'cash';
      final cashReceived = trx['cash_received'] ?? 0;
      final changeAmount = trx['change_amount'] ?? 0;

      printerService.printer.printLeftRight(
        "METODE",
        paymentMethod == 'cash' ? 'TUNAI' : 'QRIS',
        1,
      );

      if (paymentMethod == 'cash' && cashReceived > 0) {
        printerService.printer.printLeftRight(
          "TUNAI",
          formatCurrency.format(cashReceived),
          1,
        );
        printerService.printer.printLeftRight(
          "KEMBALI",
          formatCurrency.format(changeAmount),
          1,
        );
      }

      printerService.printer.printNewLine();
      printerService.printer.printCustom(
        "Terima kasih telah berbelanja!",
        1,
        1,
      );
      printerService.printer.printCustom("--- CETAK ULANG ---", 0, 1);
      printerService.printer.printNewLine();
      printerService.printer.printNewLine();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Struk Transaksi #$dailyNumber berhasil dicetak"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Gagal cetak struk: $e")));
      }
    }
  }

  Future<void> _editTransaction(Map<String, dynamic> trx) async {
    final items = await _getTransactionItems(trx['id']);

    if (mounted) {
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
  }

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
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: (trx['payment_method'] ?? 'cash') == 'cash'
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (trx['payment_method'] ?? 'cash') == 'cash'
                        ? Colors.green.shade200
                        : Colors.blue.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      (trx['payment_method'] ?? 'cash') == 'cash'
                          ? Icons.payments
                          : Icons.qr_code_2,
                      size: 16,
                      color: (trx['payment_method'] ?? 'cash') == 'cash'
                          ? Colors.green.shade700
                          : Colors.blue.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      (trx['payment_method'] ?? 'cash') == 'cash'
                          ? 'Cash'
                          : 'QRIS',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: (trx['payment_method'] ?? 'cash') == 'cash'
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

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
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                          color: Colors.white.withValues(alpha: 0.2),
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
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${items.length} item',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Info Tanggal dan Metode Pembayaran
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat(
                          'dd MMM yyyy, HH:mm',
                        ).format(DateTime.parse(trx['created_at'])),
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: (trx['payment_method'] ?? 'cash') == 'cash'
                              ? Colors.green.shade50
                              : Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (trx['payment_method'] ?? 'cash') == 'cash'
                                ? Colors.green.shade200
                                : Colors.blue.shade200,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              (trx['payment_method'] ?? 'cash') == 'cash'
                                  ? Icons.payments
                                  : Icons.qr_code_2,
                              size: 14,
                              color: (trx['payment_method'] ?? 'cash') == 'cash'
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              (trx['payment_method'] ?? 'cash') == 'cash'
                                  ? 'Cash'
                                  : 'QRIS',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color:
                                    (trx['payment_method'] ?? 'cash') == 'cash'
                                    ? Colors.green.shade700
                                    : Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

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
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              Divider(color: Colors.grey.shade200, height: 1),
                          itemBuilder: (context, idx) {
                            final item = items[idx];
                            final qty = item['quantity'] is int
                                ? (item['quantity'] as int).toDouble()
                                : item['quantity'] as double;
                            final price = (item['price'] as int).toDouble();
                            final subtotal = (price * qty).round();

                            // Format qty: hilangkan .0 jika bilangan bulat
                            final qtyText = qty % 1 == 0
                                ? qty.toInt().toString()
                                : qty.toString().replaceAll('.', ',');

                            return Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 8,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Nomor urut
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(6),
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

                                  // Info Produk
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item['name'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.grey.shade800,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                '$qtyText ${item['unit_name']}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.grey.shade700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              '× ${formatCurrency.format(price)}',
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          formatCurrency.format(subtotal),
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                const SizedBox(height: 16),

                // Total
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total Belanja",
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      Text(
                        formatCurrency.format(trx['total_amount']),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Tombol Aksi
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _editTransaction(trx);
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: Colors.grey.shade700,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
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
                            color: Colors.black12.withValues(alpha: 0.05),
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

                    const SizedBox(height: 8),

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
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.receipt_long_outlined,
                                          size: 64,
                                          color: Colors.grey.shade300,
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          "Tidak ada transaksi",
                                          style: GoogleFonts.poppins(
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
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
                                        final paymentMethod =
                                            trx['payment_method'] ?? 'cash';

                                        return Card(
                                          margin: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: ListTile(
                                            leading: CircleAvatar(
                                              backgroundColor:
                                                  paymentMethod == 'cash'
                                                  ? Colors.green.shade100
                                                  : Colors.blue.shade100,
                                              child: Icon(
                                                paymentMethod == 'cash'
                                                    ? Icons.payments
                                                    : Icons.qr_code_2,
                                                color: paymentMethod == 'cash'
                                                    ? Colors.green
                                                    : Colors.blue,
                                              ),
                                            ),
                                            title: Text(
                                              "Transaksi #$dailyNumber",
                                              style: GoogleFonts.poppins(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            subtitle: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  DateFormat(
                                                    'dd MMM yyyy, HH:mm',
                                                  ).format(
                                                    DateTime.parse(
                                                      trx['created_at'],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color:
                                                        paymentMethod == 'cash'
                                                        ? Colors.green.shade50
                                                        : Colors.blue.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          4,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    paymentMethod == 'cash'
                                                        ? 'Cash'
                                                        : 'QRIS',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          paymentMethod ==
                                                              'cash'
                                                          ? Colors
                                                                .green
                                                                .shade700
                                                          : Colors
                                                                .blue
                                                                .shade700,
                                                    ),
                                                  ),
                                                ),
                                              ],
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
