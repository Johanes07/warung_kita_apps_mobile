import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:fl_chart/fl_chart.dart';

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

  /// ================= LOAD TRANSAKSI =================
  Future<void> _loadTransactions() async {
    final db = await dbHelper.database;

    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (selectedRange != null) {
      whereClause = 'WHERE created_at BETWEEN ? AND ?';
      whereArgs = [
        selectedRange!.start.toIso8601String(),
        selectedRange!.end.toIso8601String(),
      ];
    }

    final listResult = await db.rawQuery('''
      SELECT * FROM transactions 
      $whereClause 
      ORDER BY created_at DESC
    ''', whereArgs);

    setState(() {
      transactions = listResult;
      isLoading = false;
    });
  }

  /// ================= DETAIL TRANSAKSI =================
  Future<List<Map<String, dynamic>>> _loadTransactionItems(int trxId) async {
    final db = await dbHelper.database;

    return await db.rawQuery('''
      SELECT ti.*, p.name, p.price 
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      WHERE ti.transaction_id = ?
    ''', [trxId]);
  }

  void _showTransactionDetail(Map<String, dynamic> trx) async {
    final items = await _loadTransactionItems(trx['id']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Detail Transaksi #${trx['id']}"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                dense: true,
                title: Text(item['name']),
                subtitle: Text("${item['quantity']} x Rp ${item['price']}"),
                trailing: Text("Rp ${item['subtotal']}"),
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Tutup")),
        ],
      ),
    );
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
        content: const Text("Apakah Anda yakin ingin menghapus semua data transaksi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
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

  /// ================= EXPORT PDF =================
  Future<void> _exportPDF() async {
    final pdf = pw.Document();
    final formatCurrency = NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Riwayat Transaksi",
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 16),
              ...transactions.map((trx) {
                return pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(
                    "ID: ${trx['id']} - ${DateFormat('dd MMM yyyy, HH:mm').format(DateTime.parse(trx['created_at']))} - ${formatCurrency.format(trx['total_amount'])}",
                  ),
                );
              }).toList(),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  /// ================= RINGKASAN DATA =================
  int get totalTransactions => transactions.length;

  int get totalRevenue {
    return transactions.fold<int>(
      0,
      (sum, trx) => sum + (trx['total_amount'] as int),
    );
  }

  /// ================= CHART DATA =================
  List<BarChartGroupData> getChartData() {
    final Map<String, int> dailyRevenue = {};

    for (var trx in transactions) {
      final date = DateFormat('dd/MM').format(DateTime.parse(trx['created_at']));
      dailyRevenue[date] = (dailyRevenue[date] ?? 0) + (trx['total_amount'] as int);
    }

    final keys = dailyRevenue.keys.toList()..sort((a, b) => a.compareTo(b));
    return List.generate(keys.length, (index) {
      final key = keys[index];
      final value = dailyRevenue[key]!;
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(toY: value.toDouble(), color: Colors.blueAccent, width: 18),
        ],
        showingTooltipIndicators: [0],
      );
    });
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      initialDateRange: selectedRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
    );

    if (picked != null) {
      setState(() {
        selectedRange = picked;
        isLoading = true;
      });
      _loadTransactions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency =
        NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: Text(
          "Riwayat Transaksi",
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600, color: const Color.fromARGB(255, 0, 0, 0)),
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
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            tooltip: "Export PDF",
            onPressed: _exportPDF,
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            tooltip: "Reset Data",
            onPressed: _confirmReset,
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _pickDateRange,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.date_range),
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : transactions.isEmpty
              ? const Center(child: Text("Tidak ada transaksi"))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// ======= RINGKASAN =======
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

                      /// ======= CHART =======
                      Text(
                        "Grafik Pendapatan",
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 200,
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            barTouchData: BarTouchData(enabled: true),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: true),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    final keys = transactions.map((trx) {
                                      return DateFormat('dd/MM').format(
                                          DateTime.parse(trx['created_at']));
                                    }).toSet().toList();
                                    if (index >= 0 && index < keys.length) {
                                      return Text(keys[index],
                                          style: const TextStyle(fontSize: 10));
                                    }
                                    return const Text('');
                                  },
                                ),
                              ),
                            ),
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            barGroups: getChartData(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      /// ======= LIST TRANSAKSI =======
                      Text(
                        "Daftar Transaksi",
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      ...transactions.map((trx) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long,
                                color: Color.fromARGB(255, 0, 112, 218)),
                            title: Text("Transaksi #${trx['id']}",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              DateFormat('dd MMM yyyy, HH:mm')
                                  .format(DateTime.parse(trx['created_at'])),
                            ),
                            trailing: Text(
                              formatCurrency.format(trx['total_amount']),
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.bold,
                                  color: const Color.fromARGB(255, 0, 112, 218)),
                            ),
                            onTap: () => _showTransactionDetail(trx),
                          ),
                        );
                      }).toList(),
                    ],
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
          Text(title, style: GoogleFonts.poppins(fontSize: 14)),
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
