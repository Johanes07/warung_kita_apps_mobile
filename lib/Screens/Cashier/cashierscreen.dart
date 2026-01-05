import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:warung_kita/services/printer_service.dart';

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
  final printerService = PrinterService(); // ✅ Gunakan singleton
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

  @override
  void initState() {
    super.initState();
    _loadProducts();

    // ✅ Jika mode edit, load cart dari existingCart
    if (widget.editMode && widget.existingCart != null) {
      _loadExistingCart();
    }
  }

  /// ✅ Load cart dari transaksi yang sudah ada
  void _loadExistingCart() {
    setState(() {
      cart = widget.existingCart!.map((item) {
        return {
          'id': item['product_id'],
          'name': item['name'],
          'price': item['price'],
          'qty': item['quantity'],
          'price_retail': item['price_retail'],
          'price_wholesale': item['price_wholesale'],
          'price_type': item['price_type'],
        };
      }).toList();
      _calculateTotal();
    });
  }

  /// ✅ Validasi saat keluar halaman (Simplified - tanpa cek printer)
  Future<bool> _onWillPop() async {
    // ✅ Jika mode edit dan ada perubahan di cart
    if (widget.editMode) {
      final hasChanges = cart.isNotEmpty;
      if (hasChanges) {
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              "Batalkan Edit?",
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            ),
            content: const Text(
              "Perubahan belum disimpan. Yakin ingin keluar?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Lanjut Edit"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Ya, Keluar"),
              ),
            ],
          ),
        );
        return result ?? false;
      }
    }
    return true;
  }

  Future<void> _loadProducts() async {
    final db = await dbHelper.database;
    final result = await db.query('products', orderBy: 'name ASC');

    setState(() {
      products = result;
      filteredProducts = result;
    });
  }

  void _searchProducts(String query) {
    final filtered = products.where((product) {
      final name = (product['name'] ?? '').toString().toLowerCase();
      final barcode = (product['barcode'] ?? '').toString().toLowerCase();
      return name.contains(query.toLowerCase()) ||
          barcode.contains(query.toLowerCase());
    }).toList();

    setState(() {
      filteredProducts = filtered;
    });
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CashierBarcodeScannerScreen(),
      ),
    );

    if (result != null && result is String) {
      _addProductToCartByBarcode(result);
    }
  }

  Future<void> _addProductToCartByBarcode(String barcode) async {
    final db = await dbHelper.database;
    final result = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode.trim()],
    );

    if (result.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Produk tidak ditemukan")));
      return;
    }

    final product = result.first;
    _showPriceOptionDialog(product);
  }

  void _showPriceOptionDialog(Map<String, dynamic> product) {
    final qtyController = TextEditingController(text: "1");
    final stockRetail = product['stock_retail'] ?? 0;
    final stockWholesale = product['stock_wholesale'] ?? 0;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            "Pilih Harga",
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(product['name'], style: GoogleFonts.poppins(fontSize: 16)),
              const SizedBox(height: 12),

              /// Opsi Harga Eceran
              ListTile(
                tileColor: stockRetail > 0 ? Colors.grey[100] : Colors.red[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Harga Eceran",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: stockRetail > 0
                            ? Colors.green.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Stok: $stockRetail",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: stockRetail > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  formatCurrency.format(product['price_retail']),
                  style: GoogleFonts.poppins(color: Colors.black87),
                ),
                enabled: stockRetail > 0,
                onTap: stockRetail > 0
                    ? () {
                        Navigator.pop(context);
                        _addProductToCart(
                          product,
                          int.tryParse(qtyController.text) ?? 1,
                          product['price_retail'],
                          'retail',
                        );
                      }
                    : null,
              ),
              const SizedBox(height: 8),

              /// Opsi Harga Grosir
              ListTile(
                tileColor: stockWholesale > 0
                    ? Colors.grey[100]
                    : Colors.red[50],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Harga Grosir",
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: stockWholesale > 0
                            ? Colors.orange.withOpacity(0.2)
                            : Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        "Stok: $stockWholesale",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: stockWholesale > 0
                              ? Colors.orange
                              : Colors.red,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  formatCurrency.format(product['price_wholesale']),
                  style: GoogleFonts.poppins(color: Colors.black87),
                ),
                enabled: stockWholesale > 0,
                onTap: stockWholesale > 0
                    ? () {
                        Navigator.pop(context);
                        _addProductToCart(
                          product,
                          int.tryParse(qtyController.text) ?? 1,
                          product['price_wholesale'],
                          'wholesale',
                        );
                      }
                    : null,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Jumlah",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _addProductToCart(
    Map<String, dynamic> product,
    int qty,
    int price,
    String priceType,
  ) {
    setState(() {
      final index = cart.indexWhere(
        (item) => item['id'] == product['id'] && item['price'] == price,
      );

      if (index >= 0) {
        cart[index]['qty'] += qty;
      } else {
        cart.add({
          'id': product['id'],
          'name': product['name'],
          'price': price,
          'qty': qty,
          'price_retail': product['price_retail'],
          'price_wholesale': product['price_wholesale'],
          'price_type': priceType,
        });
      }
      _calculateTotal();
    });
  }

  void _calculateTotal() {
    setState(() {
      totalAmount = cart.fold(0, (sum, item) {
        final price = int.tryParse(item['price'].toString()) ?? 0;
        final qty = int.tryParse(item['qty'].toString()) ?? 0;
        return sum + (price * qty);
      });
    });
  }

  void _updateQty(int index, int delta) {
    setState(() {
      cart[index]['qty'] += delta;
      if (cart[index]['qty'] <= 0) {
        cart.removeAt(index);
      }
      _calculateTotal();
    });
  }

  void _removeItem(int index) {
    setState(() {
      cart.removeAt(index);
      _calculateTotal();
    });
  }

  /// ✅ Print Receipt - Menggunakan PrinterService
  Future<void> _printReceiptBluetooth(
    int transactionId,
    List<Map<String, dynamic>> items,
    int total,
  ) async {
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
      printerService.printer.printNewLine();
      printerService.printer.printCustom("TOKO RIZKI", 3, 1);
      printerService.printer.printCustom("Transaksi #$transactionId", 1, 1);
      printerService.printer.printCustom(
        DateFormat('dd MMM yyyy, HH:mm').format(DateTime.now()),
        1,
        1,
      );
      printerService.printer.printNewLine();

      for (var item in items) {
        final name = item['name'];
        final qty = item['qty'];
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
        formatCurrency.format(total),
        2,
      );
      printerService.printer.printNewLine();
      printerService.printer.printCustom(
        "Terima kasih telah berbelanja!",
        1,
        1,
      );

      // ✅ Tambahkan label jika edit mode
      if (widget.editMode) {
        printerService.printer.printCustom("--- TRANSAKSI DIUPDATE ---", 0, 1);
      }

      printerService.printer.printNewLine();
      printerService.printer.printNewLine();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error print: $e")));
    }
  }

  /// ✅ CHECKOUT - Support untuk mode edit
  Future<void> _checkout() async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Keranjang kosong")));
      return;
    }

    final db = await dbHelper.database;
    setState(() => isLoading = true);

    try {
      int userId = 1;
      int transactionId = widget.transactionId ?? 0;

      await db.transaction((txn) async {
        // ✅ Jika mode edit, kembalikan stok lama terlebih dahulu
        if (widget.editMode && widget.transactionId != null) {
          // Ambil item transaksi lama
          final oldItems = await txn.rawQuery(
            '''
            SELECT * FROM transaction_items WHERE transaction_id = ?
          ''',
            [widget.transactionId],
          );

          // Kembalikan stok produk lama
          for (var oldItem in oldItems) {
            String oldPriceType =
                (oldItem['price_type']?.toString() ?? 'retail');
            int oldQuantity =
                int.tryParse(oldItem['quantity']?.toString() ?? '0') ?? 0;
            int oldProductId =
                int.tryParse(oldItem['product_id']?.toString() ?? '0') ?? 0;

            if (oldPriceType == 'retail') {
              await txn.rawUpdate(
                'UPDATE products SET stock = stock + ?, stock_retail = stock_retail + ? WHERE id = ?',
                [oldQuantity, oldQuantity, oldProductId],
              );
            } else {
              await txn.rawUpdate(
                'UPDATE products SET stock = stock + ?, stock_wholesale = stock_wholesale + ? WHERE id = ?',
                [oldQuantity, oldQuantity, oldProductId],
              );
            }
          }

          // Hapus transaction_items lama
          await txn.delete(
            'transaction_items',
            where: 'transaction_id = ?',
            whereArgs: [widget.transactionId],
          );

          // Update transaksi dengan total baru
          await txn.update(
            'transactions',
            {'total_amount': totalAmount},
            where: 'id = ?',
            whereArgs: [widget.transactionId],
          );
        } else {
          // Mode baru - create transaksi baru
          transactionId = await txn.insert('transactions', {
            'user_id': userId,
            'total_amount': totalAmount,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        // Insert transaction_items baru dan kurangi stok
        for (var item in cart) {
          String priceType = item['price_type']?.toString() ?? 'retail';

          await txn.insert('transaction_items', {
            'transaction_id': transactionId,
            'product_id': item['id'],
            'quantity': item['qty'],
            'price': item['price'],
            'price_type': priceType,
          });

          // Kurangi stok
          if (priceType == 'retail') {
            await txn.rawUpdate(
              'UPDATE products SET stock = stock - ?, stock_retail = stock_retail - ? WHERE id = ?',
              [item['qty'], item['qty'], item['id']],
            );
          } else {
            await txn.rawUpdate(
              'UPDATE products SET stock = stock - ?, stock_wholesale = stock_wholesale - ? WHERE id = ?',
              [item['qty'], item['qty'], item['id']],
            );
          }
        }
      });

      await _printReceiptBluetooth(transactionId, List.from(cart), totalAmount);

      setState(() {
        cart.clear();
        totalAmount = 0;
      });

      _showTransactionSuccessDialog(transactionId);
    } catch (e) {
      debugPrint("Error checkout: $e");
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Gagal menyimpan transaksi: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  void _showTransactionSuccessDialog(int transactionId) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 8),
            Text(
              widget.editMode ? "Edit Berhasil" : "Transaksi Berhasil",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        content: Text(
          widget.editMode
              ? "Transaksi #$transactionId berhasil diupdate!"
              : "Struk berhasil dicetak dan transaksi tersimpan.",
          style: GoogleFonts.poppins(),
          textAlign: TextAlign.center,
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Tutup dialog
                if (widget.editMode) {
                  Navigator.pop(
                    context,
                    true,
                  ); // Kembali ke IncomeScreen dengan result=true
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("OK", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          elevation: 0,
          title: Text(
            widget.editMode
                ? "Edit Transaksi #${widget.transactionId}"
                : "Kasir",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          backgroundColor: Colors.transparent,
          actions: [
            // ✅ Status printer (tanpa popup menu)
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
            if (!widget.editMode)
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                tooltip: "Scan Barcode",
                onPressed: _scanBarcode,
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
        body: Column(
          children: [
            // ✅ Banner mode edit
            if (widget.editMode)
              Container(
                color: Colors.orange.shade100,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.edit, color: Colors.orange, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Mode Edit: Ubah produk transaksi #${widget.transactionId}",
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ✅ Banner status printer
            if (!printerService.connected)
              Container(
                color: Colors.red.shade50,
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Printer belum terhubung. Hubungkan di halaman utama.",
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: searchController,
                onChanged: _searchProducts,
                decoration: InputDecoration(
                  hintText: "Cari produk nama / barcode...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: filteredProducts.isEmpty
                  ? const Center(child: Text("Produk tidak ditemukan"))
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                            childAspectRatio: 0.75,
                          ),
                      itemCount: filteredProducts.length,
                      itemBuilder: (context, index) {
                        final product = filteredProducts[index];
                        final stockRetail = product['stock_retail'] ?? 0;
                        final stockWholesale = product['stock_wholesale'] ?? 0;

                        return GestureDetector(
                          onTap: () => _showPriceOptionDialog(product),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.inventory_2,
                                  color: Colors.white,
                                  size: 32,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  product['name'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  "Ecer: ${formatCurrency.format(product['price_retail'])}",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  "Grosir: ${formatCurrency.format(product['price_wholesale'])}",
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "E: $stockRetail",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        "G: $stockWholesale",
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
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
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                children: [
                  if (cart.isNotEmpty)
                    Column(
                      children: [
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: cart.length,
                          itemBuilder: (context, index) {
                            final item = cart[index];
                            final priceType = item['price_type'] ?? 'retail';

                            return ListTile(
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
                                      priceType == 'retail' ? 'E' : 'G',
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
                              subtitle: Text(
                                formatCurrency.format(item['price']),
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                    ),
                                    onPressed: () => _updateQty(index, -1),
                                  ),
                                  Text(
                                    item['qty'].toString(),
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: () => _updateQty(index, 1),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => _removeItem(index),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const Divider(),
                      ],
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total",
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        formatCurrency.format(totalAmount),
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : Icon(widget.editMode ? Icons.save : Icons.payment),
                      label: Text(
                        isLoading
                            ? "Memproses..."
                            : (widget.editMode
                                  ? "Simpan Perubahan"
                                  : "Checkout"),
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: widget.editMode
                            ? Colors.orange
                            : Colors.blueAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isLoading ? null : _checkout,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CashierBarcodeScannerScreen extends StatelessWidget {
  const CashierBarcodeScannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Produk"),
        backgroundColor: Colors.blueAccent,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty) {
            final value = barcodes.first.rawValue;
            Navigator.pop(context, value);
          }
        },
      ),
    );
  }
}
