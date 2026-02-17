import 'dart:io';
import 'package:flutter/material.dart';
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
  bool showLowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = await dbHelper.database;
    final result = await db.query('products', orderBy: 'name ASC');

    setState(() {
      products = result;
      _applyFilters();
      isLoading = false;
    });
  }

  void _applyFilters() {
    var filtered = products;

    // Filter berdasarkan pencarian
    if (searchController.text.isNotEmpty) {
      final query = searchController.text.toLowerCase();
      filtered = filtered.where((product) {
        final name = product['name'].toString().toLowerCase();
        final barcode = product['barcode'].toString().toLowerCase();
        return name.contains(query) || barcode.contains(query);
      }).toList();
    }

    // Filter stok menipis
    if (showLowStockOnly) {
      filtered = filtered.where((product) {
        final stock = (product['stock'] ?? 0.0) is int
            ? (product['stock'] as int).toDouble()
            : product['stock'] as double;
        final minStock = (product['min_stock'] ?? 0.0) is int
            ? (product['min_stock'] as int).toDouble()
            : product['min_stock'] as double;
        return stock <= minStock && minStock > 0;
      }).toList();
    }

    setState(() {
      filteredProducts = filtered;
    });
  }

  Future<void> _deleteProduct(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: const Text('Yakin ingin menghapus produk ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final db = await dbHelper.database;
      await db.delete('products', where: 'id = ?', whereArgs: [id]);
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk berhasil dihapus'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _showProductDetails(Map<String, dynamic> product) async {
    // Load alternative units
    final units = await dbHelper.getProductUnits(product['id']);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Gambar Produk
                  if (product['image_path'] != null &&
                      product['image_path'].toString().isNotEmpty)
                    Center(
                      child: Container(
                        width: 120,
                        height: 120,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(product['image_path'].toString()),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(
                                Icons.inventory_2,
                                size: 60,
                                color: Colors.grey.shade400,
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                  Text(
                    product['name'],
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Barcode: ${product['barcode']}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const Divider(height: 32),

                  // Satuan Dasar
                  Text(
                    'Satuan Dasar',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                product['base_unit'],
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                NumberFormat.currency(
                                  locale: 'id',
                                  symbol: 'Rp ',
                                  decimalDigits: 0,
                                ).format(product['base_price']),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Stok: ${_formatStock(product['stock'])} ${product['base_unit']}',
                            style: GoogleFonts.poppins(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (units.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Satuan Alternatif',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...units.map((unit) {
                      final unitImagePath = unit['image_path'];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              if (unitImagePath != null &&
                                  unitImagePath.toString().isNotEmpty)
                                Container(
                                  width: 50,
                                  height: 50,
                                  margin: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(unitImagePath.toString()),
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Icon(
                                              Icons.inventory_2,
                                              color: Colors.grey.shade400,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  unit['unit_name'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Text(
                                NumberFormat.currency(
                                  locale: 'id',
                                  symbol: 'Rp ',
                                  decimalDigits: 0,
                                ).format(unit['price']),
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    AddProductScreen(product: product),
                              ),
                            );
                            if (result == true) {
                              _loadProducts();
                            }
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteProduct(product['id']);
                          },
                          icon: const Icon(Icons.delete),
                          label: const Text('Hapus'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatStock(dynamic stock) {
    if (stock == null) return '0';

    double stockValue = stock is int ? stock.toDouble() : stock as double;

    if (stockValue == stockValue.toInt()) {
      return stockValue.toInt().toString();
    }
    return stockValue.toString().replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Stok Produk',
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
      body: Column(
        children: [
          // Search & Filter
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari produk...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) => _applyFilters(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: showLowStockOnly
                                ? Colors.orange.shade700
                                : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Stok Menipis',
                            style: GoogleFonts.poppins(fontSize: 13),
                          ),
                        ],
                      ),
                      selected: showLowStockOnly,
                      onSelected: (value) {
                        setState(() {
                          showLowStockOnly = value;
                          _applyFilters();
                        });
                      },
                      selectedColor: Colors.orange.shade100,
                      checkmarkColor: Colors.orange.shade700,
                    ),
                    const Spacer(),
                    Text(
                      '${filteredProducts.length} produk',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Product List
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Belum ada produk',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadProducts,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final stock = (product['stock'] ?? 0.0) is int
                            ? (product['stock'] as int).toDouble()
                            : product['stock'] as double;
                        final minStock = (product['min_stock'] ?? 0.0) is int
                            ? (product['min_stock'] as int).toDouble()
                            : product['min_stock'] as double;
                        final isLowStock = stock <= minStock && minStock > 0;

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () => _showProductDetails(product),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: isLowStock
                                          ? Colors.orange.shade100
                                          : Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child:
                                        product['image_path'] != null &&
                                            product['image_path']
                                                .toString()
                                                .isNotEmpty
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: Image.file(
                                              File(
                                                product['image_path']
                                                    .toString(),
                                              ),
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                    return Icon(
                                                      Icons.inventory_2,
                                                      color: isLowStock
                                                          ? Colors
                                                                .orange
                                                                .shade700
                                                          : Colors
                                                                .blue
                                                                .shade700,
                                                    );
                                                  },
                                            ),
                                          )
                                        : Icon(
                                            Icons.inventory_2,
                                            color: isLowStock
                                                ? Colors.orange.shade700
                                                : Colors.blue.shade700,
                                          ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['name'],
                                          style: GoogleFonts.poppins(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_formatStock(stock)} ${product['base_unit']} • ${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(product['base_price'])}',
                                          style: GoogleFonts.poppins(
                                            fontSize: 13,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                        if (isLowStock)
                                          Container(
                                            margin: const EdgeInsets.only(
                                              top: 4,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Stok Menipis',
                                              style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                color: Colors.orange.shade700,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddProductScreen()),
          );
          if (result == true) {
            _loadProducts();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
    );
  }
}
