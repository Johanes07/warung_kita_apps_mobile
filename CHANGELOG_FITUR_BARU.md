# Changelog - Fitur Baru Stok Produk

## Perubahan yang Ditambahkan

### 1. Upload Gambar dengan Opsi Kamera atau Galeri
- **Sebelumnya**: Hanya bisa memilih gambar dari galeri
- **Sekarang**: Bisa memilih antara:
  - 📷 Ambil foto langsung dengan kamera
  - 🖼️ Pilih dari galeri foto
- **Lokasi**: 
  - Gambar produk utama
  - Gambar untuk setiap satuan alternatif

### 2. Barcode untuk Satuan Alternatif
- **Fitur Baru**: Setiap satuan alternatif bisa punya barcode sendiri
- **Contoh Penggunaan**:
  - Produk: Indomie
  - Satuan Dasar (pcs): Barcode `8991234567890`
  - Satuan Box: Barcode `8991234567999` (berbeda!)
- **Manfaat**: Saat scan barcode box, langsung terdeteksi sebagai box, bukan pcs
- **Opsional**: Barcode satuan alternatif tidak wajib diisi

### 3. Stok Awal dan Stok Minimum untuk Satuan Alternatif
- **Fitur Baru**: Tracking stok terpisah untuk setiap satuan
- **Tracking Independen**: Setiap satuan punya stok sendiri, tidak ada konversi otomatis
- **Contoh**:
  ```
  Produk: Indomie
  
  Satuan Dasar (pcs):
  - Stok: 50 pcs
  - Stok Minimum: 20 pcs
  
  Satuan Box:
  - Stok: 5 box
  - Stok Minimum: 2 box
  
  Satuan Karton:
  - Stok: 2 karton
  - Stok Minimum: 1 karton
  ```
- **Notifikasi Stok Menipis**: 
  - Tampil badge "Stok Menipis" jika stok <= stok minimum
  - Warna orange untuk highlight
  - Berlaku untuk satuan dasar dan satuan alternatif

## Perubahan Database

### Tabel `product_units` (Versi 6)
Struktur tabel satuan alternatif:
- `id` - ID unik
- `product_id` - ID produk induk
- `unit_name` - Nama satuan (Box, Karton, Lusin, dll)
- `barcode` (TEXT, UNIQUE, nullable) - Barcode khusus untuk satuan ini
- `price` - Harga per satuan
- `stock` (REAL, default 0) - Stok untuk satuan ini
- `min_stock` (REAL, default 0) - Stok minimum untuk notifikasi
- `image_path` - Path gambar satuan (opsional)

**CATATAN**: Field `conversion_rate` dihapus karena membingungkan. Setiap satuan sekarang independen.

### Migrasi Otomatis
- Database akan otomatis upgrade dari versi 5 ke versi 6
- Data lama tetap aman
- Kolom baru akan diisi dengan nilai default (0 untuk stok)
- Field conversion_rate akan dihapus otomatis

## Cara Menggunakan

### Menambah Produk dengan Satuan Alternatif:

1. **Isi Data Produk Utama**
   - Scan/ketik barcode produk
   - Nama produk
   - Upload gambar (pilih kamera atau galeri)
   - Satuan dasar (contoh: pcs)
   - Harga satuan dasar
   - Stok awal dan stok minimum

2. **Tambah Satuan Alternatif**
   - Klik tombol "Tambah" di bagian Satuan Alternatif
   - Isi form:
     - Upload gambar satuan (opsional) - pilih kamera atau galeri
     - Nama satuan (contoh: Box, Karton, Lusin)
     - Barcode satuan (opsional, bisa scan atau ketik)
     - Harga per satuan
     - Stok awal satuan ini
     - Stok minimum satuan ini

3. **Simpan Produk**

### Melihat Stok:

- **List Produk**: Menampilkan stok satuan dasar
- **Detail Produk**: 
  - Tap produk untuk melihat detail lengkap
  - Lihat semua satuan alternatif dengan stok masing-masing
  - Badge "Stok Menipis" muncul jika stok <= minimum

### Filter Stok Menipis:

- Gunakan filter "Stok Menipis" di halaman stok
- Menampilkan produk yang stok satuan dasarnya menipis
- Cek detail untuk lihat satuan alternatif yang menipis

## Catatan Penting

1. **Barcode Satuan Alternatif**:
   - Harus unik (tidak boleh sama dengan barcode lain)
   - Opsional (boleh dikosongkan)
   - Berguna untuk scanning yang lebih akurat

2. **Stok Independen**:
   - Setiap satuan punya tracking stok sendiri
   - TIDAK ADA konversi otomatis antar satuan
   - Lebih sederhana dan tidak membingungkan
   - Cocok untuk sistem inventory yang terpisah per kemasan

3. **Gambar**:
   - Setiap satuan bisa punya gambar berbeda
   - Bisa ambil dari kamera atau galeri
   - Berguna untuk membedakan kemasan (pcs vs box)
   - Opsional untuk semua satuan

## Contoh Kasus Penggunaan

### Contoh 1: Toko Kelontong
```
Produk: Indomie Goreng

Satuan Dasar (pcs):
- Barcode: 089686010107
- Harga: Rp 3.000
- Stok: 100 pcs
- Min: 20 pcs

Satuan Box:
- Barcode: 089686010114 (barcode box berbeda!)
- Harga: Rp 70.000
- Stok: 3 box
- Min: 1 box
```

### Contoh 2: Toko Elektronik
```
Produk: Baterai AA

Satuan Dasar (pcs):
- Barcode: 123456789012
- Harga: Rp 5.000
- Stok: 50 pcs
- Min: 10 pcs

Satuan Pack (4 pcs):
- Barcode: 123456789029
- Harga: Rp 18.000
- Stok: 10 pack
- Min: 3 pack

Satuan Box (48 pcs):
- Barcode: 123456789036
- Harga: Rp 200.000
- Stok: 2 box
- Min: 1 box
```

## Testing

Untuk menguji fitur baru:

1. Buat produk baru dengan satuan alternatif
2. Tambahkan barcode berbeda untuk setiap satuan
3. Set stok dan stok minimum
4. Upload gambar dari kamera atau galeri
5. Coba scan barcode satuan alternatif di kasir
6. Lihat notifikasi stok menipis

## Troubleshooting

Jika database error setelah update:
- Database akan otomatis migrasi ke versi 6
- Field conversion_rate akan dihapus otomatis
- Jika ada masalah, data lama akan tetap aman
- Hubungi developer jika ada error
