import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/db/database_helper.dart';

class IncomeScreen extends StatefulWidget {
  const IncomeScreen({super.key});

  @override
  State<IncomeScreen> createState() => _IncomeScreenState();
}

class _IncomeScreenState extends State<IncomeScreen> {
  final dbHelper = DatabaseHelper.instance;
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
    _loadIncomeData(); // load awal hari ini
  }

  /// ================= LOAD DATA BERDASARKAN RANGE =================
  Future<void> _loadIncomeData() async {
    final db = await dbHelper.database;

    String whereClause = "";
    List<dynamic> whereArgs = [];

    if (selectedDateRange != null) {
      String startDate =
          DateFormat('yyyy-MM-dd').format(selectedDateRange!.start);
      String endDate = DateFormat('yyyy-MM-dd').format(selectedDateRange!.end);
      whereClause = "WHERE DATE(created_at) BETWEEN ? AND ?";
      whereArgs = [startDate, endDate];
    } else {
      // Default: hari ini
      String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      whereClause = "WHERE DATE(created_at) = ?";
      whereArgs = [today];
    }

    final totalResult = await db.rawQuery('''
      SELECT SUM(total_amount) as total FROM transactions $whereClause
    ''', whereArgs);

    final listResult = await db.rawQuery('''
      SELECT * FROM transactions $whereClause ORDER BY created_at DESC
    ''', whereArgs);

    setState(() {
      totalIncome = (totalResult.first['total'] ?? 0) as int;
      transactions = listResult;
      isLoading = false;
    });
  }

  /// ================= AMBIL DETAIL ITEM TRANSAKSI =================
  Future<List<Map<String, dynamic>>> _getTransactionItems(
      int transactionId) async {
    final db = await dbHelper.database;

    final result = await db.rawQuery('''
      SELECT ti.*, p.name 
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''', [transactionId]);

    return result;
  }

  /// ================= PILIH RANGE TANGGAL =================
  Future<void> _pickDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDateRange: selectedDateRange ??
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

  /// ================= SHOW DETAIL TRANSAKSI =================
  void _showTransactionDetail(Map<String, dynamic> trx) async {
    final items = await _getTransactionItems(trx['id']);

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item['name'], style: GoogleFonts.poppins()),
                        subtitle: Text("Qty: ${item['quantity']}"),
                        trailing: Text(
                          formatCurrency.format(item['price']),
                          style:
                              GoogleFonts.poppins(fontWeight: FontWeight.w600),
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
            color: const Color.fromARGB(255, 0, 0, 0), // biar kontras dengan background gambar
          ),
        ),
        backgroundColor: Colors.transparent, // transparan supaya gambar kelihatan
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range, color: Color.fromARGB(255, 0, 0, 0)),
            tooltip: "Pilih Range Tanggal",
            onPressed: _pickDateRange,
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/bgwarung2.jpg"), // ganti path sesuai assetmu
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
                    /// ======= Ringkasan =======
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
                                fontSize: 16, color: Colors.black54),
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
                                  fontSize: 12, color: Colors.grey),
                            )
                          else
                            Text(
                              "Hari ini",
                              style: GoogleFonts.poppins(
                                  fontSize: 12, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),

                    /// ======= List Transaksi =======
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
                                  physics:
                                      const NeverScrollableScrollPhysics(),
                                  itemCount: transactions.length,
                                  itemBuilder: (context, index) {
                                    final trx = transactions[index];
                                    return Card(
                                      margin:
                                          const EdgeInsets.only(bottom: 12),
                                      child: ListTile(
                                        leading: const Icon(Icons.receipt_long,
                                            color: Colors.green),
                                        title: Text(
                                          "Transaksi #${trx['id']}",
                                          style: GoogleFonts.poppins(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        subtitle: Text(
                                          DateFormat('dd MMM yyyy, HH:mm')
                                              .format(DateTime.parse(
                                                  trx['created_at'])),
                                        ),
                                        trailing: Text(
                                          formatCurrency
                                              .format(trx['total_amount']),
                                          style: GoogleFonts.poppins(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green,
                                          ),
                                        ),
                                        onTap: () =>
                                            _showTransactionDetail(trx),
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
