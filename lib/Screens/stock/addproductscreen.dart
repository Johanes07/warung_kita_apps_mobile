import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:warung_kita/db/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.currency(
    locale: 'id_ID',
    symbol: '',
    decimalDigits: 0,
  );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = _formatter.format(int.parse(digitsOnly));

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AddProductScreen extends StatefulWidget {
  final Map<String, dynamic>? product;

  const AddProductScreen({super.key, this.product});

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  final dbHelper = DatabaseHelper.instance;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController barcodeController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController basePriceController = TextEditingController();
  final TextEditingController baseUnitController = TextEditingController();
  final TextEditingController stockController = TextEditingController();
  final TextEditingController minStockController = TextEditingController();

  List<Map<String, dynamic>> alternativeUnits = [];
  bool isSaving = false;
  bool isEdit = false;
  String? imagePath;

  // Helper untuk format angka: hilangkan .0 jika bilangan bulat
  String _formatNumber(dynamic number) {
    if (number == null) return '0';
    final double value = number is int ? number.toDouble() : number as double;
    return value % 1 == 0
        ? value.toInt().toString()
        : value.toString().replaceAll('.', ',');
  }

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      isEdit = true;
      _loadProductData();
    }
  }

  Future<void> _loadProductData() async {
    final product = widget.product!;
    barcodeController.text = product['barcode'] ?? '';
    nameController.text = product['name'] ?? '';
    basePriceController.text = NumberFormat(
      '#,###',
      'id_ID',
    ).format(product['base_price'] ?? 0);
    baseUnitController.text = product['base_unit'] ?? '';
    imagePath = product['image_path'];

    double stock = (product['stock'] ?? 0.0) is int
        ? (product['stock'] as int).toDouble()
        : product['stock'] as double;
    // Format stok: hilangkan .0 jika bilangan bulat
    stockController.text = stock % 1 == 0
        ? stock.toInt().toString()
        : stock.toString().replaceAll('.', ',');

    double minStock = (product['min_stock'] ?? 0.0) is int
        ? (product['min_stock'] as int).toDouble()
        : product['min_stock'] as double;
    // Format min stok: hilangkan .0 jika bilangan bulat
    minStockController.text = minStock % 1 == 0
        ? minStock.toInt().toString()
        : minStock.toString().replaceAll('.', ',');

    final units = await dbHelper.getProductUnits(product['id']);
    setState(() {
      // Buat salinan mutable dari data units
      alternativeUnits = units
          .map((unit) => Map<String, dynamic>.from(unit))
          .toList();
    });
  }

  @override
  void dispose() {
    barcodeController.dispose();
    nameController.dispose();
    basePriceController.dispose();
    baseUnitController.dispose();
    stockController.dispose();
    minStockController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName =
            '${DateTime.now().millisecondsSinceEpoch}${path.extension(image.path)}';
        final savedImage = await File(
          image.path,
        ).copy('${appDir.path}/$fileName');

        setState(() {
          imagePath = savedImage.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memilih gambar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );

    if (result != null && result is String) {
      setState(() {
        barcodeController.text = result;
      });
    }
  }

  void _addAlternativeUnit() {
    _showAlternativeUnitDialog();
  }

  void _editAlternativeUnit(int index) {
    final unit = alternativeUnits[index];
    // Format konversi: hilangkan .0 jika bilangan bulat
    final conversionRate = unit['conversion_rate'] as double;
    final conversionText = conversionRate % 1 == 0
        ? conversionRate.toInt().toString()
        : conversionRate.toString().replaceAll('.', ',');

    _showAlternativeUnitDialog(
      index: index,
      initialUnitName: unit['unit_name'],
      initialConversion: conversionText,
      initialPrice: NumberFormat('#,###', 'id_ID').format(unit['price']),
      initialImagePath: unit['image_path'],
    );
  }

  void _showAlternativeUnitDialog({
    int? index,
    String? initialUnitName,
    String? initialConversion,
    String? initialPrice,
    String? initialImagePath,
  }) {
    final isEdit = index != null;

    showDialog(
      context: context,
      builder: (context) {
        final unitNameController = TextEditingController(text: initialUnitName);
        final conversionController = TextEditingController(
          text: initialConversion,
        );
        final priceController = TextEditingController(text: initialPrice);
        String? unitImagePath = initialImagePath;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                isEdit ? 'Edit Satuan Alternatif' : 'Tambah Satuan Alternatif',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      children: [
                        // Placeholder atau preview gambar satuan
                        GestureDetector(
                          onTap: () async {
                            try {
                              final XFile? image = await _picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );

                              if (image != null) {
                                final appDir =
                                    await getApplicationDocumentsDirectory();
                                final fileName =
                                    '${DateTime.now().millisecondsSinceEpoch}${path.extension(image.path)}';
                                final savedImage = await File(
                                  image.path,
                                ).copy('${appDir.path}/$fileName');

                                setDialogState(() {
                                  unitImagePath = savedImage.path;
                                });
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Gagal memilih gambar: $e'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                          child: Container(
                            width: 100,
                            height: 100,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: unitImagePath != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      File(unitImagePath!),
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate,
                                        size: 36,
                                        color: Colors.grey.shade500,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Tap untuk\npilih gambar',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        if (unitImagePath != null)
                          TextButton.icon(
                            onPressed: () {
                              setDialogState(() {
                                unitImagePath = null;
                              });
                            },
                            icon: const Icon(
                              Icons.delete,
                              size: 16,
                              color: Colors.red,
                            ),
                            label: const Text(
                              'Hapus Gambar',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: unitNameController,
                      decoration: InputDecoration(
                        labelText: 'Nama Satuan (contoh: Box, Karton)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: conversionController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                      ],
                      decoration: InputDecoration(
                        labelText:
                            'Konversi (contoh: 1 Box = 24 ${baseUnitController.text})',
                        hintText: 'Contoh: 24 atau 24,5',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [CurrencyInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'Harga per Satuan',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (unitNameController.text.isNotEmpty &&
                        conversionController.text.isNotEmpty &&
                        priceController.text.isNotEmpty) {
                      setState(() {
                        final unitData = {
                          'unit_name': unitNameController.text.trim(),
                          'conversion_rate': double.parse(
                            conversionController.text.replaceAll(',', '.'),
                          ),
                          'price': int.parse(
                            priceController.text.replaceAll('.', ''),
                          ),
                          'image_path': unitImagePath,
                        };

                        if (isEdit) {
                          alternativeUnits[index] = unitData;
                        } else {
                          alternativeUnits.add(unitData);
                        }
                      });
                      Navigator.pop(context);
                    }
                  },
                  child: Text(isEdit ? 'Update' : 'Tambah'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isSaving = true);

    try {
      final db = await dbHelper.database;

      double stock = stockController.text.isEmpty
          ? 0.0
          : double.parse(stockController.text.replaceAll(',', '.'));
      double minStock = minStockController.text.isEmpty
          ? 0.0
          : double.parse(minStockController.text.replaceAll(',', '.'));

      final productData = {
        'name': nameController.text.trim(),
        'barcode': barcodeController.text.trim(),
        'base_price': int.parse(basePriceController.text.replaceAll('.', '')),
        'base_unit': baseUnitController.text.trim(),
        'stock': stock,
        'min_stock': minStock,
        'image_path': imagePath,
      };

      int productId;
      if (isEdit) {
        productId = widget.product!['id'];
        await db.update(
          'products',
          productData,
          where: 'id = ?',
          whereArgs: [productId],
        );

        await db.delete(
          'product_units',
          where: 'product_id = ?',
          whereArgs: [productId],
        );
      } else {
        productId = await db.insert('products', productData);
      }

      for (var unit in alternativeUnits) {
        await dbHelper.addProductUnit(
          productId,
          unit['unit_name'],
          unit['conversion_rate'],
          unit['price'],
          imagePath: unit['image_path'],
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit
                  ? 'Produk berhasil diupdate!'
                  : 'Produk berhasil ditambahkan!',
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        title: Text(
          isEdit ? 'Edit Produk' : 'Tambah Produk',
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
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Barcode ──────────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Barcode',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: barcodeController,
                              decoration: InputDecoration(
                                hintText: 'Scan atau ketik barcode',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Barcode tidak boleh kosong';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Nama Produk ───────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nama Produk',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          hintText: 'Masukkan nama produk',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Nama produk tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Gambar Produk ─────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gambar Produk (Opsional)',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Column(
                          children: [
                            // FIX: Selalu tampilkan area gambar —
                            // placeholder jika belum ada, preview jika sudah ada
                            GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                width: 150,
                                height: 150,
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                                child: imagePath != null
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(12),
                                        child: Image.file(
                                          File(imagePath!),
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.add_photo_alternate,
                                            size: 48,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Tap untuk\npilih gambar',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.poppins(
                                              fontSize: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            // Tombol selalu tampil
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _pickImage,
                                icon: const Icon(Icons.add_photo_alternate),
                                label: Text(
                                  imagePath != null
                                      ? 'Ganti Gambar'
                                      : 'Pilih Gambar',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 14,
                                  ),
                                ),
                              ),
                            ),
                            // Tombol hapus gambar — hanya muncul kalau ada gambar
                            if (imagePath != null) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      imagePath = null;
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  label: const Text(
                                    'Hapus Gambar',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Satuan Dasar ──────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Satuan Dasar',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: baseUnitController,
                        decoration: InputDecoration(
                          labelText: 'Satuan (contoh: pcs, kg, liter)',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Satuan tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: basePriceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [CurrencyInputFormatter()],
                        decoration: InputDecoration(
                          labelText: 'Harga per Satuan Dasar',
                          prefixText: 'Rp ',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Harga tidak boleh kosong';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Stok ─────────────────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stok Satuan Dasar',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                        ],
                        decoration: InputDecoration(
                          labelText:
                              'Stok Awal (opsional, gunakan koma untuk desimal)',
                          hintText: 'Contoh: 100 atau 100,5',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: minStockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                        ],
                        decoration: InputDecoration(
                          labelText:
                              'Stok Minimum (untuk notifikasi stok menipis)',
                          hintText: 'Contoh: 10 atau 10,5',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Satuan Alternatif ─────────────────────────────────────
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Satuan Alternatif (Opsional)',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _addAlternativeUnit,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Tambah'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (alternativeUnits.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Belum ada satuan alternatif',
                              style: GoogleFonts.poppins(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        )
                      else
                        ...alternativeUnits.asMap().entries.map((entry) {
                          final index = entry.key;
                          final unit = entry.value;
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
                                          errorBuilder:
                                              (context, error, stackTrace) {
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
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'Konversi: ${_formatNumber(unit['conversion_rate'])} ${baseUnitController.text}\nHarga: ${NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0).format(unit['price'])}',
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.blue,
                                    ),
                                    onPressed: () {
                                      _editAlternativeUnit(index);
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        alternativeUnits.removeAt(index);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // ── Tombol Simpan ─────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSaving ? null : _saveProduct,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEdit ? 'Update Produk' : 'Simpan Produk',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
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
