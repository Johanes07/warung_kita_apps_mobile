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

  Future<void> _applyFilters() async {
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

    // Filter stok menipis - cek satuan dasar DAN satuan alternatif
    if (showLowStockOnly) {
      List<Map<String, dynamic>> lowStockProducts = [];

      for (var product in filtered) {
        bool isLowStock = false;

        // Cek stok satuan dasar
        final stock = (product['stock'] ?? 0.0) is int
            ? (product['stock'] as int).toDouble()
            : product['stock'] as double;
        final minStock = (product['min_stock'] ?? 0.0) is int
            ? (product['min_stock'] as int).toDouble()
            : product['min_stock'] as double;

        if (stock <= minStock && minStock > 0) {
          isLowStock = true;
        }

        // Cek stok satuan alternatif
        if (!isLowStock) {
          final units = await dbHelper.getProductUnits(product['id']);
          for (var unit in units) {
            final unitStock = (unit['stock'] ?? 0.0) is int
                ? (unit['stock'] as int).toDouble()
                : unit['stock'] as double;
            final unitMinStock = (unit['min_stock'] ?? 0.0) is int
                ? (unit['min_stock'] as int).toDouble()
                : unit['min_stock'] as double;

            if (unitStock <= unitMinStock && unitMinStock > 0) {
              isLowStock = true;
              break;
            }
          }
        }

        if (isLowStock) {
          lowStockProducts.add(product);
        }
      }

      filtered = lowStockProducts;
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

    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;

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
              padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
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
                  SizedBox(height: isSmallScreen ? 16 : 20),

                  // Gambar Produk
                  if (product['image_path'] != null &&
                      product['image_path'].toString().isNotEmpty)
                    Center(
                      child: Container(
                        width: isSmallScreen ? 100 : 120,
                        height: isSmallScreen ? 100 : 120,
                        margin: EdgeInsets.only(
                          bottom: isSmallScreen ? 12 : 16,
                        ),
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
                                size: isSmallScreen ? 48 : 60,
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
                      fontSize: isSmallScreen ? 18 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'Barcode: ${product['barcode']}',
                    style: GoogleFonts.poppins(
                      fontSize: isSmallScreen ? 12 : 14,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Divider(height: isSmallScreen ? 24 : 32),

                  // Satuan Dasar
                  Text(
                    'Satuan Dasar',
                    style: GoogleFonts.poppins(
                      fontSize: isSmallScreen ? 14 : 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  Builder(
                    builder: (context) {
                      final baseStock = (product['stock'] ?? 0.0) is int
                          ? (product['stock'] as int).toDouble()
                          : product['stock'] as double;
                      final baseMinStock = (product['min_stock'] ?? 0.0) is int
                          ? (product['min_stock'] as int).toDouble()
                          : product['min_stock'] as double;
                      final isBaseLowStock =
                          baseStock <= baseMinStock && baseMinStock > 0;

                      return Card(
                        color: isBaseLowStock
                            ? Colors.orange.shade50
                            : Colors.blue.shade50,
                        child: Padding(
                          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    product['base_unit'],
                                    style: GoogleFonts.poppins(
                                      fontSize: isSmallScreen ? 14 : 16,
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
                                      fontSize: isSmallScreen ? 14 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: isSmallScreen ? 6 : 8),
                              Text(
                                'Stok: ${_formatStock(baseStock)} • Min: ${_formatStock(baseMinStock)}',
                                style: GoogleFonts.poppins(
                                  fontSize: isSmallScreen ? 12 : 14,
                                  color: isBaseLowStock
                                      ? Colors.orange.shade700
                                      : Colors.grey.shade700,
                                  fontWeight: isBaseLowStock
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                              if (isBaseLowStock)
                                Container(
                                  margin: EdgeInsets.only(
                                    top: isSmallScreen ? 6 : 8,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isSmallScreen ? 6 : 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Stok Menipis',
                                    style: GoogleFonts.poppins(
                                      fontSize: isSmallScreen ? 10 : 11,
                                      color: Colors.orange.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  if (units.isNotEmpty) ...[
                    SizedBox(height: isSmallScreen ? 16 : 24),
                    Text(
                      'Satuan Alternatif',
                      style: GoogleFonts.poppins(
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    ...units.map((unit) {
                      final unitImagePath = unit['image_path'];
                      final unitBarcode = unit['barcode'];
                      final unitStock = (unit['stock'] ?? 0.0) is int
                          ? (unit['stock'] as int).toDouble()
                          : unit['stock'] as double;
                      final unitMinStock = (unit['min_stock'] ?? 0.0) is int
                          ? (unit['min_stock'] as int).toDouble()
                          : unit['min_stock'] as double;
                      final isLowStock =
                          unitStock <= unitMinStock && unitMinStock > 0;

                      return Card(
                        margin: EdgeInsets.only(bottom: isSmallScreen ? 6 : 8),
                        color: isLowStock
                            ? Colors.orange.shade50
                            : Colors.white,
                        child: Padding(
                          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                          child: Row(
                            children: [
                              if (unitImagePath != null &&
                                  unitImagePath.toString().isNotEmpty)
                                Container(
                                  width: isSmallScreen ? 40 : 50,
                                  height: isSmallScreen ? 40 : 50,
                                  margin: EdgeInsets.only(
                                    right: isSmallScreen ? 8 : 12,
                                  ),
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
                                              size: isSmallScreen ? 20 : 24,
                                              color: Colors.grey.shade400,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      unit['unit_name'],
                                      style: GoogleFonts.poppins(
                                        fontSize: isSmallScreen ? 14 : 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (unitBarcode != null &&
                                        unitBarcode.toString().isNotEmpty)
                                      Text(
                                        'Barcode: $unitBarcode',
                                        style: GoogleFonts.poppins(
                                          fontSize: isSmallScreen ? 10 : 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    SizedBox(height: isSmallScreen ? 2 : 4),
                                    Text(
                                      NumberFormat.currency(
                                        locale: 'id',
                                        symbol: 'Rp ',
                                        decimalDigits: 0,
                                      ).format(unit['price']),
                                      style: GoogleFonts.poppins(
                                        fontSize: isSmallScreen ? 13 : 15,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade700,
                                      ),
                                    ),
                                    SizedBox(height: isSmallScreen ? 2 : 4),
                                    Text(
                                      'Stok: ${_formatStock(unitStock)} • Min: ${_formatStock(unitMinStock)}',
                                      style: GoogleFonts.poppins(
                                        fontSize: isSmallScreen ? 11 : 13,
                                        color: isLowStock
                                            ? Colors.orange.shade700
                                            : Colors.grey.shade600,
                                        fontWeight: isLowStock
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    if (isLowStock)
                                      Container(
                                        margin: EdgeInsets.only(
                                          top: isSmallScreen ? 2 : 4,
                                        ),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isSmallScreen ? 6 : 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          'Stok Menipis',
                                          style: GoogleFonts.poppins(
                                            fontSize: isSmallScreen ? 9 : 11,
                                            color: Colors.orange.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],

                  SizedBox(height: isSmallScreen ? 16 : 24),
                  isSmallScreen
                      ? Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
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
                                icon: const Icon(Icons.edit, size: 18),
                                label: const Text('Edit Produk'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _deleteProduct(product['id']);
                                },
                                icon: const Icon(Icons.delete, size: 18),
                                label: const Text('Hapus Produk'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Row(
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
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

  // Fungsi untuk cek apakah produk atau satuan alternatifnya ada yang menipis
  Future<bool> _hasLowStock(Map<String, dynamic> product) async {
    // Cek stok satuan dasar
    final stock = (product['stock'] ?? 0.0) is int
        ? (product['stock'] as int).toDouble()
        : product['stock'] as double;
    final minStock = (product['min_stock'] ?? 0.0) is int
        ? (product['min_stock'] as int).toDouble()
        : product['min_stock'] as double;

    if (stock <= minStock && minStock > 0) {
      return true;
    }

    // Cek stok satuan alternatif
    final units = await dbHelper.getProductUnits(product['id']);
    for (var unit in units) {
      final unitStock = (unit['stock'] ?? 0.0) is int
          ? (unit['stock'] as int).toDouble()
          : unit['stock'] as double;
      final unitMinStock = (unit['min_stock'] ?? 0.0) is int
          ? (unit['min_stock'] as int).toDouble()
          : unit['min_stock'] as double;

      if (unitStock <= unitMinStock && unitMinStock > 0) {
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    final isMediumScreen = screenWidth >= 600 && screenWidth < 900;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          'Stok Produk',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.black,
            fontSize: isSmallScreen ? 16 : 18,
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
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  style: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                  decoration: InputDecoration(
                    hintText: 'Cari produk...',
                    hintStyle: TextStyle(fontSize: isSmallScreen ? 13 : 14),
                    prefixIcon: Icon(
                      Icons.search,
                      size: isSmallScreen ? 20 : 24,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 12 : 16,
                      vertical: isSmallScreen ? 10 : 12,
                    ),
                  ),
                  onChanged: (value) => _applyFilters(),
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                Row(
                  children: [
                    FilterChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: isSmallScreen ? 14 : 16,
                            color: showLowStockOnly
                                ? Colors.orange.shade700
                                : Colors.grey,
                          ),
                          SizedBox(width: isSmallScreen ? 2 : 4),
                          Text(
                            'Stok Menipis',
                            style: GoogleFonts.poppins(
                              fontSize: isSmallScreen ? 11 : 13,
                            ),
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
                        fontSize: isSmallScreen ? 11 : 13,
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
                          size: isSmallScreen ? 60 : 80,
                          color: Colors.grey.shade300,
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 16),
                        Text(
                          'Belum ada produk',
                          style: GoogleFonts.poppins(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadProducts,
                    child: ListView.builder(
                      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final stock = (product['stock'] ?? 0.0) is int
                            ? (product['stock'] as int).toDouble()
                            : product['stock'] as double;
                        final minStock = (product['min_stock'] ?? 0.0) is int
                            ? (product['min_stock'] as int).toDouble()
                            : product['min_stock'] as double;
                        final isBaseUnitLowStock =
                            stock <= minStock && minStock > 0;

                        return FutureBuilder<bool>(
                          future: _hasLowStock(product),
                          builder: (context, snapshot) {
                            final hasAnyLowStock =
                                snapshot.data ?? isBaseUnitLowStock;

                            return Card(
                              elevation: 2,
                              margin: EdgeInsets.only(
                                bottom: isSmallScreen ? 8 : 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () => _showProductDetails(product),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: EdgeInsets.all(
                                    isSmallScreen ? 12 : 16,
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: isSmallScreen ? 40 : 50,
                                        height: isSmallScreen ? 40 : 50,
                                        decoration: BoxDecoration(
                                          color: hasAnyLowStock
                                              ? Colors.orange.shade100
                                              : Colors.blue.shade100,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child:
                                            product['image_path'] != null &&
                                                product['image_path']
                                                    .toString()
                                                    .isNotEmpty
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: Image.file(
                                                  File(
                                                    product['image_path']
                                                        .toString(),
                                                  ),
                                                  fit: BoxFit.cover,
                                                  errorBuilder:
                                                      (
                                                        context,
                                                        error,
                                                        stackTrace,
                                                      ) {
                                                        return Icon(
                                                          Icons.inventory_2,
                                                          size: isSmallScreen
                                                              ? 20
                                                              : 24,
                                                          color: hasAnyLowStock
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
                                                size: isSmallScreen ? 20 : 24,
                                                color: hasAnyLowStock
                                                    ? Colors.orange.shade700
                                                    : Colors.blue.shade700,
                                              ),
                                      ),
                                      SizedBox(width: isSmallScreen ? 12 : 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              product['name'],
                                              style: GoogleFonts.poppins(
                                                fontSize: isSmallScreen
                                                    ? 13
                                                    : 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            SizedBox(
                                              height: isSmallScreen ? 2 : 4,
                                            ),
                                            Text(
                                              '${_formatStock(stock)} ${product['base_unit']} • ${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(product['base_price'])}',
                                              style: GoogleFonts.poppins(
                                                fontSize: isSmallScreen
                                                    ? 11
                                                    : 13,
                                                color: Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (hasAnyLowStock)
                                              Container(
                                                margin: EdgeInsets.only(
                                                  top: isSmallScreen ? 2 : 4,
                                                ),
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: isSmallScreen
                                                      ? 6
                                                      : 8,
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
                                                    fontSize: isSmallScreen
                                                        ? 9
                                                        : 11,
                                                    color:
                                                        Colors.orange.shade700,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.chevron_right,
                                        size: isSmallScreen ? 20 : 24,
                                        color: Colors.grey.shade400,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: isSmallScreen
          ? FloatingActionButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddProductScreen(),
                  ),
                );
                if (result == true) {
                  _loadProducts();
                }
              },
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddProductScreen(),
                  ),
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
