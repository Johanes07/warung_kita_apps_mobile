import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:warung_kita/services/printer_service.dart';
import 'package:warung_kita/Screens/Cashier/checkoutscreen.dart';

class CashierScreen extends StatefulWidget {
  final bool editMode;
  final int? transactionId;
  final List<Map<String, dynamic>>? existingCart;

  const CashierScreen({
    super.key,
    this.editMode = false,
    this.transactionId,
    this.existingCart,
  });

  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  final dbHelper = DatabaseHelper.instance;
  final printerService = PrinterService();
  final formatCurrency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  List<Map<String, dynamic>> cart = [];
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> filteredProducts = [];

  final TextEditingController searchController = TextEditingController();
  int totalAmount = 0;
  bool isLoading = false;
  int? dailyTransactionNumber;

  @override
  void initState() {
    super.initState();
    _loadProducts();

    if (widget.editMode && widget.existingCart != null) {
      _loadExistingCart();
      _loadDailyNumber();
    }
  }

  Future<void> _loadDailyNumber() async {
    if (widget.transactionId != null) {
      final number = await _getDailyTransactionNumber(widget.transactionId!);
      setState(() {
        dailyTransactionNumber = number;
      });
    }
  }

  void _loadExistingCart() {
    setState(() {
      cart = widget.existingCart!.map((item) {
        return {
          'id': item['product_id'],
          'name': item['name'],
          'price': item['price'],
          'qty': item['quantity'],
          'unit': item['unit_name'] ?? item['unit'] ?? 'pcs',
        };
      }).toList();
      _calculateTotal();
    });
  }

  Future<int> _getDailyTransactionNumber(int transactionId) async {
    final db = await dbHelper.database;
    final trxResult = await db.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [transactionId],
    );

    if (trxResult.isEmpty) return transactionId;

    String transactionDate = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.parse(trxResult.first['created_at'].toString()));

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM transactions
      WHERE DATE(created_at) = ? AND id <= ?
      ORDER BY created_at ASC
    ''',
      [transactionDate, transactionId],
    );

    return result.first['count'] as int;
  }

  Future<void> _loadProducts() async {
    setState(() => isLoading = true);
    final db = await dbHelper.database;
    final result = await db.query('products', orderBy: 'name ASC');

    setState(() {
      products = result;
      filteredProducts = result;
      isLoading = false;
    });
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        filteredProducts = products;
      } else {
        filteredProducts = products.where((product) {
          final name = product['name'].toString().toLowerCase();
          final barcode = product['barcode'].toString().toLowerCase();
          return name.contains(query.toLowerCase()) ||
              barcode.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );

    if (result != null && result is String) {
      final product = products.firstWhere(
        (p) => p['barcode'] == result,
        orElse: () => {},
      );

      if (product.isNotEmpty) {
        _showUnitSelectionDialog(product);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Produk tidak ditemukan'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _showUnitSelectionDialog(Map<String, dynamic> product) async {
    final units = await dbHelper.getProductUnits(product['id']);

    final List<Map<String, dynamic>> unitOptions = [
      {
        'unit_name': product['base_unit'],
        'price': product['base_price'],
        'conversion_rate': 1.0,
        'is_base': true,
        'image_path': product['image_path'],
      },
      ...units.map((u) => {...u, 'is_base': false}),
    ];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pilih Satuan',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product['name'],
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const Divider(height: 24),
              ...unitOptions.map((unit) {
                final unitImagePath = unit['image_path'];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child:
                          unitImagePath != null &&
                              unitImagePath.toString().isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(unitImagePath.toString()),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(
                                    Icons.inventory_2,
                                    color: Colors.grey.shade400,
                                  );
                                },
                              ),
                            )
                          : Icon(
                              Icons.inventory_2,
                              color: Colors.grey.shade400,
                            ),
                    ),
                    title: Text(
                      unit['unit_name'],
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      formatCurrency.format(unit['price']),
                      style: GoogleFonts.poppins(fontSize: 13),
                    ),
                    trailing: unit['is_base']
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Dasar',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(context);
                      _showQuantityDialog(product, unit);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _showQuantityDialog(
    Map<String, dynamic> product,
    Map<String, dynamic> selectedUnit,
  ) {
    final qtyController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Jumlah',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${product['name']} (${selectedUnit['unit_name']})',
                style: GoogleFonts.poppins(fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Jumlah (gunakan koma untuk desimal)',
                  hintText: 'Contoh: 5 atau 2,5',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(
                  qtyController.text.replaceAll(',', '.'),
                );
                if (qty != null && qty > 0) {
                  _addToCart(product, selectedUnit, qty);
                  Navigator.pop(context);
                }
              },
              child: const Text('Tambah'),
            ),
          ],
        );
      },
    );
  }

  void _showEditQuantityDialog(Map<String, dynamic> item, int index) {
    final currentQty = item['qty'] is int
        ? (item['qty'] as int).toDouble()
        : item['qty'] as double;
    final qtyText = currentQty % 1 == 0
        ? currentQty.toInt().toString()
        : currentQty.toString().replaceAll('.', ',');
    final qtyController = TextEditingController(text: qtyText);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Edit Jumlah',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item['name']} (${item['unit']})',
                style: GoogleFonts.poppins(fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Jumlah (gunakan koma untuk desimal)',
                  hintText: 'Contoh: 5 atau 2,5',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(
                  qtyController.text.replaceAll(',', '.'),
                );
                if (qty != null && qty > 0) {
                  setState(() {
                    cart[index]['qty'] = qty;
                    _calculateTotal();
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  void _addToCart(
    Map<String, dynamic> product,
    Map<String, dynamic> unit,
    double qty,
  ) {
    final existingIndex = cart.indexWhere(
      (item) =>
          item['id'] == product['id'] && item['unit'] == unit['unit_name'],
    );

    setState(() {
      if (existingIndex >= 0) {
        cart[existingIndex]['qty'] += qty;
      } else {
        cart.add({
          'id': product['id'],
          'name': product['name'],
          'price': unit['price'],
          'qty': qty,
          'unit': unit['unit_name'],
          'conversion_rate': unit['conversion_rate'] ?? 1.0,
        });
      }
      _calculateTotal();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product['name']} ditambahkan ke keranjang'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _calculateTotal() {
    int total = 0;
    for (var item in cart) {
      final price = (item['price'] as int).toDouble();
      final qty = item['qty'] is int
          ? (item['qty'] as int).toDouble()
          : item['qty'] as double;
      total += (price * qty).round();
    }
    setState(() {
      totalAmount = total;
    });
  }

  void _clearCart() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi'),
        content: const Text('Yakin ingin mengosongkan keranjang?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                cart.clear();
                _calculateTotal();
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width > 1200) return 6;
    if (width > 900) return 4;
    if (width > 600) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          widget.editMode ? 'Edit Pembelian' : 'Kasir',
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
        actions: [
          if (cart.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _clearCart,
              tooltip: 'Kosongkan Keranjang',
            ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
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
                    onChanged: _filterProducts,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredProducts.isEmpty
                ? Center(
                    child: Text(
                      'Produk tidak ditemukan',
                      style: GoogleFonts.poppins(color: Colors.grey.shade600),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: _getCrossAxisCount(context),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: filteredProducts.length,
                    itemBuilder: (context, index) {
                      final product = filteredProducts[index];
                      final imagePath = product['image_path'];

                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _showUnitSelectionDialog(product),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child:
                                      imagePath != null &&
                                          imagePath.toString().isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: Image.file(
                                            File(imagePath.toString()),
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Icon(
                                                    Icons.inventory_2,
                                                    size: 40,
                                                    color: Colors.blue.shade700,
                                                  );
                                                },
                                          ),
                                        )
                                      : Icon(
                                          Icons.inventory_2,
                                          size: 40,
                                          color: Colors.blue.shade700,
                                        ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  product['name'],
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const Spacer(),
                                Text(
                                  formatCurrency.format(product['base_price']),
                                  style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                Text(
                                  'per ${product['base_unit']}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),

          if (cart.isNotEmpty)
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header Keranjang
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shopping_cart,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Keranjang Belanja',
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade700,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${cart.length} item',
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

                  // Daftar Item di Keranjang
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: cart.length,
                      separatorBuilder: (context, index) =>
                          Divider(height: 1, color: Colors.grey.shade200),
                      itemBuilder: (context, index) {
                        final item = cart[index];
                        final qty = item['qty'] is int
                            ? (item['qty'] as int).toDouble()
                            : item['qty'] as double;
                        final price = (item['price'] as int).toDouble();
                        final subtotal = (price * qty).round();

                        // Format qty: hilangkan .0 jika bilangan bulat
                        final qtyText = qty % 1 == 0
                            ? qty.toInt().toString()
                            : qty.toString().replaceAll('.', ',');

                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Info Produk
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'],
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${formatCurrency.format(price)} / ${item['unit']}',
                                      style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
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
                              const SizedBox(width: 8),
                              // Kontrol Quantity
                              Column(
                                children: [
                                  // Tombol Delete
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        final removedItem = cart[index];
                                        cart.removeAt(index);
                                        _calculateTotal();

                                        ScaffoldMessenger.of(
                                          context,
                                        ).clearSnackBars();
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${removedItem['name']} dihapus',
                                            ),
                                            backgroundColor: Colors.red,
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                            action: SnackBarAction(
                                              label: 'BATAL',
                                              textColor: Colors.white,
                                              onPressed: () {
                                                setState(() {
                                                  cart.insert(
                                                    index,
                                                    removedItem,
                                                  );
                                                  _calculateTotal();
                                                });
                                              },
                                            ),
                                          ),
                                        );
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Kontrol +/-
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Tombol Minus
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (qty > 1) {
                                                cart[index]['qty'] = qty - 1;
                                              } else if (qty > 0.1) {
                                                // Kurangi 0.1 jika qty < 1
                                                final newQty =
                                                    (qty * 10 - 1) / 10;
                                                cart[index]['qty'] = newQty > 0
                                                    ? newQty
                                                    : 0.1;
                                              }
                                              _calculateTotal();
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.remove,
                                              size: 16,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                        // Display Quantity (tap untuk edit manual)
                                        InkWell(
                                          onTap: () {
                                            _showEditQuantityDialog(
                                              item,
                                              index,
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              border: Border.symmetric(
                                                vertical: BorderSide(
                                                  color: Colors.grey.shade300,
                                                ),
                                              ),
                                            ),
                                            child: Text(
                                              qtyText,
                                              style: GoogleFonts.poppins(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                        // Tombol Plus
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (qty >= 1) {
                                                cart[index]['qty'] = qty + 1;
                                              } else {
                                                // Tambah 0.1 jika qty < 1
                                                cart[index]['qty'] =
                                                    (qty * 10 + 1) / 10;
                                              }
                                              _calculateTotal();
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            child: Icon(
                                              Icons.add,
                                              size: 16,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                      ],
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

                  // Total dan Tombol Checkout
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey.shade300, width: 2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total Belanja',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              formatCurrency.format(totalAmount),
                              style: GoogleFonts.poppins(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CheckoutScreen(
                                    cart: cart,
                                    totalAmount: totalAmount,
                                    editMode: widget.editMode,
                                    transactionId: widget.transactionId,
                                    dailyNumber: dailyTransactionNumber,
                                  ),
                                ),
                              );

                              if (result == true && mounted) {
                                // Jika edit mode, kembali ke halaman sebelumnya
                                if (widget.editMode) {
                                  if (context.mounted) {
                                    Navigator.pop(context, true);
                                  }
                                } else {
                                  // Jika transaksi baru, kosongkan keranjang
                                  setState(() {
                                    cart.clear();
                                    _calculateTotal();
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Transaksi berhasil! Siap untuk transaksi baru.',
                                      ),
                                      backgroundColor: Colors.green,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.payment, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  widget.editMode
                                      ? 'Update Pembelian'
                                      : 'Checkout',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Barcode'),
        backgroundColor: Colors.black,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            if (barcode.rawValue != null) {
              Navigator.pop(context, barcode.rawValue);
              return;
            }
          }
        },
      ),
    );
  }
}
