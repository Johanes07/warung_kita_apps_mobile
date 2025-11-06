import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:warung_kita/Screens/stock/addproductscreen.dart';
import 'package:warung_kita/db/database_helper.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];

  final TextEditingController searchController = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  /// Ambil semua produk dari database
  Future<void> _loadProducts() async {
    final db = await dbHelper.database;
    final result = await db.query('products', orderBy: 'name ASC');

    setState(() {
      products = result;
      filteredProducts = result;
      isLoading = false;
    });
  }

  /// Fungsi pencarian produk berdasarkan nama / barcode
  void _searchProducts(String query) {
    final filtered = products.where((product) {
      final name = product['name'].toString().toLowerCase();
      final barcode = product['barcode'].toString().toLowerCase();
      return name.contains(query.toLowerCase()) ||
          barcode.contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredProducts = filtered;
    });
  }

  /// Hapus produk dari database
  void _deleteProduct(int id) async {
    final db = await dbHelper.database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Produk berhasil dihapus')),
    );
    _loadProducts();
  }

  /// Dialog edit produk (Nama, Stok, Harga)
  void _editProduct(Map<String, dynamic> product) {
    final formatCurrency = NumberFormat.currency(locale: 'id', symbol: '', decimalDigits: 0);

    final TextEditingController nameController =
        TextEditingController(text: product['name']); // Nama Produk
    final TextEditingController stockController =
        TextEditingController(text: product['stock'].toString());
    final TextEditingController priceRetailController =
        TextEditingController(text: formatCurrency.format(product['price_retail']));
    final TextEditingController priceWholesaleController =
        TextEditingController(text: formatCurrency.format(product['price_wholesale']));

    /// Helper untuk format angka menjadi Rupiah saat mengetik
    String formatNumber(String value) {
      if (value.isEmpty) return '';
      final number = int.parse(value.replaceAll('.', ''));
      return formatCurrency.format(number);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Edit Produk",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
        content: SingleChildScrollView(
          child: Column(
            children: [
              /// Nama Produk
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: "Nama Produk"),
              ),
              const SizedBox(height: 12),

              /// Stok
              TextField(
                controller: stockController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly, // hanya angka
                ],
                decoration: const InputDecoration(labelText: "Stok"),
              ),
              const SizedBox(height: 12),

              /// Harga Eceran
              TextField(
                controller: priceRetailController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(labelText: "Harga Eceran"),
                onChanged: (value) {
                  final formatted = formatNumber(value);
                  priceRetailController.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(offset: formatted.length),
                  );
                },
              ),
              const SizedBox(height: 12),

              /// Harga Grosir
              TextField(
                controller: priceWholesaleController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(labelText: "Harga Grosir"),
                onChanged: (value) {
                  final formatted = formatNumber(value);
                  priceWholesaleController.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(offset: formatted.length),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final db = await dbHelper.database;

              // Update data produk
              await db.update(
                'products',
                {
                  'name': nameController.text, // Update nama produk
                  'stock': int.parse(stockController.text),
                  'price_retail': int.parse(priceRetailController.text.replaceAll('.', '')),
                  'price_wholesale': int.parse(priceWholesaleController.text.replaceAll('.', '')),
                },
                where: 'id = ?',
                whereArgs: [product['id']],
              );

              Navigator.pop(context);
              _loadProducts();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Produk berhasil diperbarui')),
              );
            },
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
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
      appBar: AppBar(
        title: Text(
          'Stok Produk',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: const Color.fromARGB(255, 0, 0, 0),
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage("assets/images/bgwarung2.jpg"),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),

      /// Tombol Tambah Produk
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProductScreen()),
          );

          if (result == true) {
            _loadProducts(); // refresh data setelah tambah
          }
        },
        label: const Text("Tambah Produk"),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.blueAccent,
      ),

      body: Column(
        children: [
          /// ====== Pencarian Produk ======
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: searchController,
              onChanged: _searchProducts,
              decoration: InputDecoration(
                hintText: "Cari produk berdasarkan nama / barcode...",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          /// ====== List Produk ======
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredProducts.isEmpty
                    ? const Center(child: Text("Tidak ada produk ditemukan"))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredProducts.length,
                        itemBuilder: (context, index) {
                          final product = filteredProducts[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(12),
                              leading: CircleAvatar(
                                backgroundColor:
                                    Colors.blueAccent.withOpacity(0.2),
                                child: const Icon(Icons.inventory_2_rounded,
                                    color: Colors.blueAccent),
                              ),
                              title: Text(
                                product['name'],
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Barcode: ${product['barcode']}"),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Harga Eceran: ${formatCurrency.format(product['price_retail'])}",
                                    style:
                                        const TextStyle(color: Colors.black87),
                                  ),
                                  Text(
                                    "Harga Grosir: ${formatCurrency.format(product['price_wholesale'])}",
                                    style:
                                        const TextStyle(color: Colors.black87),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "Stok: ${product['stock']}",
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _editProduct(product);
                                  } else if (value == 'delete') {
                                    _deleteProduct(product['id']);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit, color: Colors.blue),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Hapus'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
