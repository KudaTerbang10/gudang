import 'package:flutter/material.dart';
import 'product.dart';
import 'transaction.dart';
import 'hive_boxes.dart';

/// Helper class untuk menggabungkan transaksi dengan informasi produknya
class TransactionWithProduct {
  final Transaction transaction;
  final Product product;
  TransactionWithProduct(this.transaction, this.product);
}

class InventoryProvider extends ChangeNotifier {
  late List<Product> _allProducts;
  List<Product> _filteredProducts = [];
  bool _isTableView = true;
  String _searchQuery = '';
  bool _isSortAscending = true;
  int? _sortColumnIndex;

  InventoryProvider() {
    _loadFromHive();
  }

  // ===== GETTERS =====
  List<Product> get products => _filteredProducts;
  List<Product> get allProducts => _allProducts;
  bool get isTableView => _isTableView;
  bool get isSortAscending => _isSortAscending;
  int? get sortColumnIndex => _sortColumnIndex;

  /// Mengambil semua transaksi dari semua produk dan diurutkan berdasarkan waktu terbaru
  List<TransactionWithProduct> get allTransactionsWithProduct {
    List<TransactionWithProduct> all = [];
    for (var product in _allProducts) {
      for (var tx in product.history) {
        all.add(TransactionWithProduct(tx, product));
      }
    }
    // Urutkan berdasarkan timestamp terbaru (descending)
    all.sort(
      (a, b) => b.transaction.timestamp.compareTo(a.transaction.timestamp),
    );
    return all;
  }

  // ===== INITIALIZATION & PERSISTENCE =====
  void _loadFromHive() {
    try {
      final box = HiveBoxes.getProductsBox();
      _allProducts = box.values.toList().cast<Product>();

      // If empty, initialize with default data
      if (_allProducts.isEmpty) {
        _initializeDefaultProducts();
      }

      _filteredProducts = List.from(_allProducts);
      print('✅ Loaded ${_allProducts.length} products from Hive');
    } catch (e) {
      print('❌ Error loading from Hive: $e');
      _allProducts = [];
      _filteredProducts = [];
    }
  }

  void _initializeDefaultProducts() {
    final defaultProducts = [
      Product(
        id: '1',
        name: 'Thermal 100x150 Isi 500 ROLL ECO',
        stock: 50,
        location: 'A1',
      ),
      Product(
        id: '2',
        name: 'Semicoated (SC) 80x50 Isi 1000 ROLL',
        stock: 100,
        location: 'B1',
      ),
      Product(
        id: '3',
        name: 'Thermal 78x100 Isi 500 ROLL',
        stock: 75,
        location: 'A4',
      ),
      Product(
        id: '4',
        name: 'Yupo 50x30 Isi 2000 ROLL (Anti Sobek)',
        stock: 40,
        location: 'C1',
      ),
      Product(
        id: '5',
        name: 'Thermal 40x30 Isi 1000 ROLL',
        stock: 120,
        location: 'B2',
      ),
      Product(
        id: '6',
        name: 'SC 33x15 3 Line Isi 5000 ROLL',
        stock: 30,
        location: 'D1',
      ),
      Product(
        id: '7',
        name: 'Thermal 80x80 OTANI Roll Kasir',
        stock: 200,
        location: 'E1',
      ),
      Product(
        id: '8',
        name: 'HW220 Ribbon Wax Resin 110x300',
        stock: 60,
        location: 'F1',
      ),
      Product(
        id: '9',
        name: 'Thermal 50x20 2 Line Isi 2000 ROLL',
        stock: 500,
        location: 'G1',
      ),
      Product(
        id: '10',
        name: 'Semicoated (SC) 100x50 Isi 1000 ROLL',
        stock: 25,
        location: 'A3',
      ),
    ];

    for (final product in defaultProducts) {
      _allProducts.add(product);
    }
    _saveToHive();
    print('✅ Initialized ${_allProducts.length} default products');
  }

  Future<void> _saveToHive() async {
    try {
      final box = HiveBoxes.getProductsBox();
      await box.clear();
      await box.addAll(_allProducts);
      print('✅ Saved ${_allProducts.length} products to Hive');
    } catch (e) {
      print('❌ Error saving to Hive: $e');
      rethrow;
    }
  }

  // ===== PRODUCT OPERATIONS =====
  void toggleView() {
    _isTableView = !_isTableView;
    notifyListeners();
  }

  void searchProduct(String query) {
    _searchQuery = query;
    if (query.isEmpty) {
      _filteredProducts = List.from(_allProducts);
    } else {
      _filteredProducts = _allProducts
          .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
          .toList();
    }
    _applySort();
    notifyListeners();
  }

  void sortProductsByStock(int columnIndex, bool ascending) {
    _sortColumnIndex = columnIndex;
    _isSortAscending = ascending;
    _applySort();
    notifyListeners();
  }

  void _applySort() {
    if (_sortColumnIndex == 1) {
      // Index 1 adalah kolom Stok
      if (_isSortAscending) {
        _filteredProducts.sort((a, b) => a.stock.compareTo(b.stock));
      } else {
        _filteredProducts.sort((a, b) => b.stock.compareTo(a.stock));
      }
    }
  }

  void addProduct(String name, int stock, String location) {
    final newProduct = Product(
      id: DateTime.now().toString(),
      name: name,
      stock: stock,
      location: location,
    );
    _allProducts.add(newProduct);
    _saveToHive();
    searchProduct(_searchQuery);
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required int stock,
    required String location,
  }) async {
    final index = _allProducts.indexWhere((p) => p.id == id);
    if (index != -1) {
      final oldProduct = _allProducts[index];
      _allProducts[index] = Product(
        id: id,
        name: name,
        stock: stock,
        location: location,
        history: oldProduct.history,
      );
      await _saveToHive();
      searchProduct(_searchQuery);
    }
  }

  Future<void> deleteProduct(String productId) async {
    _allProducts.removeWhere((p) => p.id == productId);
    await _saveToHive();
    searchProduct(_searchQuery);
  }

  // ===== TRANSACTION OPERATIONS (BARANG MASUK/KELUAR) =====

  /// Check if document number already exists for this product
  bool isDocumentNumberExists(String productId, String documentNumber) {
    final product = _allProducts.firstWhere(
      (p) => p.id == productId,
      orElse: () => throw Exception('Product not found'),
    );

    return product.history.any(
      (t) => t.documentNumber.toLowerCase() == documentNumber.toLowerCase(),
    );
  }

  /// Add incoming stock (Barang Masuk)
  /// documentNumber: nomor surat serah terima barang
  Future<bool> addIncoming({
    required String productId,
    required int quantity,
    required String documentNumber,
    String? notes,
  }) async {
    try {
      // Validate inputs
      if (quantity <= 0) {
        throw Exception('Quantity harus lebih besar dari 0');
      }
      if (documentNumber.trim().isEmpty) {
        throw Exception('Nomor surat jalan tidak boleh kosong');
      }

      // Check for duplicate document number
      if (isDocumentNumberExists(productId, documentNumber)) {
        throw Exception(
          'Nomor surat jalan "$documentNumber" sudah digunakan untuk produk ini',
        );
      }

      // Find product
      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) {
        throw Exception('Product tidak ditemukan');
      }

      final product = _allProducts[productIndex];
      final previousStock = product.stock;
      final newStock = previousStock + quantity;

      // Create transaction
      final transaction = Transaction(
        id: DateTime.now().toString(),
        type: 'incoming',
        quantity: quantity,
        documentNumber: documentNumber,
        notes: notes,
        previousStock: previousStock,
        newStock: newStock,
        timestamp: DateTime.now(),
      );

      // Update product
      product.stock = newStock;
      product.history.add(transaction);

      // Save to Hive
      await _saveToHive();
      notifyListeners();

      print(
        '✅ Barang Masuk: $quantity unit of "${product.name}" | '
        'Stock: $previousStock → $newStock | Doc: $documentNumber',
      );
      return true;
    } catch (e) {
      print('❌ Error adding incoming: $e');
      rethrow;
    }
  }

  /// Add outgoing stock (Barang Keluar)
  /// documentNumber: nomor invoice/resi penjualan online
  Future<bool> addOutgoing({
    required String productId,
    required int quantity,
    required String documentNumber,
    String? recipientName,
    String? expedition,
    String? notes,
  }) async {
    try {
      // Validate inputs
      if (quantity <= 0) {
        throw Exception('Quantity harus lebih besar dari 0');
      }
      if (documentNumber.trim().isEmpty) {
        throw Exception('Nomor invoice/resi tidak boleh kosong');
      }

      // Find product
      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) {
        throw Exception('Product tidak ditemukan');
      }

      final product = _allProducts[productIndex];

      // Check if outgoing quantity exceeds current stock
      if (quantity > product.stock) {
        throw Exception(
          'Stok tidak cukup. Stok tersedia: ${product.stock}, diminta: $quantity',
        );
      }

      // Check for duplicate document number
      if (isDocumentNumberExists(productId, documentNumber)) {
        throw Exception(
          'Nomor surat jalan/resi "$documentNumber" sudah digunakan untuk produk ini',
        );
      }

      final previousStock = product.stock;
      final newStock = previousStock - quantity;

      // Create transaction
      final transaction = Transaction(
        id: DateTime.now().toString(),
        type: 'outgoing',
        quantity: quantity,
        documentNumber: documentNumber,
        notes: notes,
        previousStock: previousStock,
        newStock: newStock,
        timestamp: DateTime.now(),
        expedition: expedition,
        recipientName: recipientName,
      );

      // Update product
      product.stock = newStock;
      product.history.add(transaction);

      // Save to Hive
      await _saveToHive();
      notifyListeners();

      print(
        '✅ Barang Keluar: $quantity unit of "${product.name}" | '
        'Stock: $previousStock → $newStock | Doc: $documentNumber',
      );
      return true;
    } catch (e) {
      print('❌ Error adding outgoing: $e');
      rethrow;
    }
  }

  /// Edit transaction quantity and adjust product stock accordingly
  Future<void> editTransactionQuantity({
    required String productId,
    required String transactionId,
    required int newQuantity,
  }) async {
    try {
      if (newQuantity <= 0) {
        throw Exception('Quantity harus lebih besar dari 0');
      }

      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) throw Exception('Product tidak ditemukan');

      final product = _allProducts[productIndex];
      final transactionIndex = product.history.indexWhere(
        (t) => t.id == transactionId,
      );
      if (transactionIndex == -1) throw Exception('Transaksi tidak ditemukan');

      final oldTransaction = product.history[transactionIndex];
      final int oldQuantity = oldTransaction.quantity;
      final int diff = newQuantity - oldQuantity;

      // Penyesuaian stok produk berdasarkan tipe transaksi
      if (oldTransaction.isIncoming) {
        // Jika barang masuk dikurangi, pastikan stok tidak jadi negatif
        if (product.stock + diff < 0) {
          throw Exception('Stok tidak mencukupi untuk penyesuaian ini');
        }
        product.stock += diff;
      } else {
        // Jika barang keluar ditambah, pastikan stok mencukupi
        if (product.stock - diff < 0) {
          throw Exception('Stok tidak mencukupi untuk penyesuaian ini');
        }
        product.stock -= diff;
      }

      // Buat objek transaksi baru (karena field Transaction bersifat final)
      final updatedTransaction = Transaction(
        id: oldTransaction.id,
        type: oldTransaction.type,
        quantity: newQuantity,
        documentNumber: oldTransaction.documentNumber,
        notes: oldTransaction.notes,
        previousStock: oldTransaction.previousStock,
        newStock:
            oldTransaction.previousStock +
            (oldTransaction.isIncoming ? newQuantity : -newQuantity),
        timestamp: oldTransaction.timestamp,
        expedition: oldTransaction.expedition,
        recipientName: oldTransaction.recipientName,
      );

      // Update history
      product.history[transactionIndex] = updatedTransaction;

      // Save to Hive
      await _saveToHive();
      notifyListeners();
    } catch (e) {
      print('❌ Error editing transaction: $e');
      rethrow;
    }
  }

  /// Menambahkan transaksi massal (Bulk) secara atomik (semua berhasil atau semua gagal)
  Future<void> addBulkTransactions({
    required String type,
    required String documentNumber,
    required List<Map<String, dynamic>> items,
    String? recipientName,
    String? expedition,
    String? notes,
  }) async {
    try {
      final isIncoming = type == 'incoming';

      // Fase 1: Validasi semua item terlebih dahulu sebelum mengubah state apapun
      final List<Map<String, dynamic>> processingData = [];

      for (final item in items) {
        final String productId = item['productId'];
        final int quantity = item['quantity'];

        final productIndex = _allProducts.indexWhere((p) => p.id == productId);
        if (productIndex == -1) throw Exception('Produk tidak ditemukan');

        final product = _allProducts[productIndex];

        // Cek duplikasi nomor dokumen per produk
        if (isDocumentNumberExists(productId, documentNumber)) {
          throw Exception(
            'Nomor dokumen "$documentNumber" sudah digunakan untuk "${product.name}"',
          );
        }

        // Cek kecukupan stok jika barang keluar
        if (!isIncoming && quantity > product.stock) {
          throw Exception(
            'Stok "${product.name}" tidak mencukupi (Tersedia: ${product.stock}, Diminta: $quantity)',
          );
        }

        processingData.add({'product': product, 'quantity': quantity});
      }

      // Fase 2: Eksekusi perubahan ke memori jika semua validasi di atas lolos
      final now = DateTime.now();
      for (final data in processingData) {
        final Product product = data['product'];
        final int quantity = data['quantity'];

        final previousStock = product.stock;
        final newStock = isIncoming
            ? previousStock + quantity
            : previousStock - quantity;

        final transaction = Transaction(
          id: '${now.millisecondsSinceEpoch}_${product.id}',
          type: type,
          quantity: quantity,
          documentNumber: documentNumber,
          notes: notes,
          previousStock: previousStock,
          newStock: newStock,
          timestamp: now,
          expedition: expedition,
          recipientName: recipientName,
        );

        product.stock = newStock;
        product.history.add(transaction);
      }

      // Simpan semua perubahan sekaligus ke Hive
      await _saveToHive();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// Delete transaction and revert stock changes
  Future<void> deleteTransaction({
    required String productId,
    required String transactionId,
  }) async {
    try {
      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) throw Exception('Product tidak ditemukan');

      final product = _allProducts[productIndex];
      final transactionIndex = product.history.indexWhere(
        (t) => t.id == transactionId,
      );
      if (transactionIndex == -1) throw Exception('Transaksi tidak ditemukan');

      final transaction = product.history[transactionIndex];

      // Revert stock
      if (transaction.isIncoming) {
        if (product.stock - transaction.quantity < 0) {
          throw Exception('Gagal menghapus: Stok akan menjadi negatif');
        }
        product.stock -= transaction.quantity;
      } else {
        product.stock += transaction.quantity;
      }

      product.history.removeAt(transactionIndex);
      await _saveToHive();
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  /// Get transaction history for a product
  List<Transaction> getTransactionHistory(String productId) {
    try {
      final product = _allProducts.firstWhere(
        (p) => p.id == productId,
        orElse: () => throw Exception('Product not found'),
      );
      return product.history;
    } catch (e) {
      print('❌ Error getting transaction history: $e');
      return [];
    }
  }

  /// Get product by ID
  Product? getProductById(String productId) {
    try {
      return _allProducts.firstWhere((p) => p.id == productId);
    } catch (e) {
      return null;
    }
  }
}
