import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:warung_kita/Screens/Cashier/cashierscreen.dart';
import 'package:warung_kita/Screens/History/historyscreen.dart';
import 'package:warung_kita/Screens/Income/incomescreen.dart';
import 'package:warung_kita/Screens/stock/stockscreen.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:warung_kita/Screens/Login/loginscreen.dart';

class HomeScreen extends StatefulWidget {
  final int userId;

  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final dbHelper = DatabaseHelper.instance;
  int totalProducts = 0;
  int totalTransactions = 0;
  int todayIncome = 0;

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAndResetIncome();
    _loadDashboardData();
  }

  /// Mengecek apakah hari sudah berganti, jika ya reset pemasukan & transaksi ke 0
  Future<void> _checkAndResetIncome() async {
    final prefs = await SharedPreferences.getInstance();
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final lastDate = prefs.getString('last_open_date');

    if (lastDate == null || lastDate != today) {
      // Hari berganti, reset pemasukan & transaksi
      setState(() {
        todayIncome = 0;
        totalTransactions = 0;
      });
      await prefs.setString('last_open_date', today);
    }
  }

  /// Load data dashboard seperti produk, transaksi, pemasukan hari ini
  Future<void> _loadDashboardData() async {
    final db = await dbHelper.database;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Total Produk (tidak pernah reset)
    final products = await db.rawQuery('SELECT COUNT(*) as count FROM products');

    // Total Transaksi HANYA untuk hari ini
    final transactions = await db.rawQuery('''
      SELECT COUNT(*) as count 
      FROM transactions 
      WHERE DATE(created_at) = ?
    ''', [today]);

    // Total Pemasukan HANYA untuk hari ini
    final income = await db.rawQuery('''
      SELECT SUM(total_amount) as total
      FROM transactions
      WHERE DATE(created_at) = ?
    ''', [today]);

    setState(() {
      totalProducts = products.first['count'] as int;
      totalTransactions = transactions.first['count'] as int;
      todayIncome = (income.first['total'] != null)
          ? income.first['total'] as int
          : 0;
      isLoading = false;
    });
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text("Konfirmasi Logout"),
        content: const Text("Apakah Anda yakin ingin logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
              );
            },
            child: const Text("Logout", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatCurrency =
        NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          automaticallyImplyLeading: false,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              image: DecorationImage(
                image: AssetImage("assets/images/bgwarung2.jpg"),
                fit: BoxFit.cover,
              ),
            ),
          ),
          backgroundColor: const Color.fromARGB(0, 0, 0, 0),
          elevation: 0,
          title: Text(
            'Warung Kita',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              fontSize: 22,
              color: const Color.fromARGB(255, 0, 0, 0),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              tooltip: "Logout",
              onPressed: _logout,
            ),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// ======= Ringkasan =======
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Ringkasan Hari Ini",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryCard(
                                  title: "Produk",
                                  value: totalProducts.toString(),
                                  icon: Icons.inventory_2_rounded,
                                  color: Colors.blueAccent,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSummaryCard(
                                  title: "Transaksi",
                                  value: totalTransactions.toString(),
                                  icon: Icons.receipt_long_rounded,
                                  color: Colors.deepPurple,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSummaryCard(
                                  title: "Pemasukan",
                                  value: formatCurrency.format(todayIncome),
                                  icon: Icons.attach_money_rounded,
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    /// ======= Menu Utama =======
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Menu Utama",
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GridView.count(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 1.2,
                            children: [
                              _buildMenuButton(
                                Icons.list_alt_rounded,
                                "Stok Produk",
                                Colors.blue,
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const StockScreen()),
                                  );
                                },
                              ),
                              _buildMenuButton(
                                Icons.point_of_sale_rounded,
                                "Kasir",
                                Colors.green,
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const CashierScreen()),
                                  );
                                },
                              ),
                              _buildMenuButton(
                                Icons.history_rounded,
                                "Riwayat",
                                Colors.purple,
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const HistoryScreen()),
                                  );
                                },
                              ),
                              _buildMenuButton(
                                Icons.bar_chart_rounded,
                                "Pemasukan",
                                Colors.redAccent,
                                () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            const IncomeScreen()),
                                  );
                                },
                              ),
                            ],
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

  /// ======= Widget Ringkasan =======
  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
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
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.2),
            radius: 20,
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  /// ======= Widget Menu =======
  Widget _buildMenuButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black12.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              radius: 24,
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
