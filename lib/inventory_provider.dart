import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart';
import 'product.dart';
import 'transaction.dart';
import 'hive_boxes.dart';
import 'mongodb_service.dart';

class InventoryProvider extends ChangeNotifier {
  late List<Product> _allProducts = [];
  late List<Transaction> _allTransactions = [];
  List<Product> _filteredProducts = [];
  bool _isTableView = true;
  String _searchQuery = '';
  bool _isSortAscending = true;
  int? _sortColumnIndex;

  final MongodbService _mongodbService = MongodbService();
  bool _isConnecting = false;
  bool _isSyncing = false;
  String? _lastSyncTime;
  Timer? _syncTimer;

  InventoryProvider() {
    _loadFromHive();
    // Connect and sync on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initiateConnectionAndSync();
    });

    // Run periodic sync in background every 30 seconds
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (isConnected) {
        syncWithAtlas();
      } else {
        connectToAtlasSilently();
      }
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  // ===== GETTERS =====
  List<Product> get products => _filteredProducts;
  List<Product> get allProducts => _allProducts;
  List<Transaction> get allTransactions => _allTransactions;
  bool get isTableView => _isTableView;
  bool get isSortAscending => _isSortAscending;
  int? get sortColumnIndex => _sortColumnIndex;

  bool get isConnected => _mongodbService.isConnected;
  bool get isConnecting => _isConnecting;
  bool get isSyncing => _isSyncing;
  String? get lastSyncTime => _lastSyncTime;

  /// Merge transaction history with product info dynamically
  List<TransactionWithProduct> get allTransactionsWithProduct {
    List<TransactionWithProduct> all = [];
    for (var tx in _allTransactions) {
      final product = _allProducts.firstWhere(
        (p) => p.id == tx.productId,
        orElse: () => Product(
          id: tx.productId,
          name: 'Produk Tidak Ditemukan (${tx.productId})',
          stock: 0,
          location: '-',
          updatedAt: DateTime.now(),
          isSynced: true,
        ),
      );
      all.add(TransactionWithProduct(tx, product));
    }
    // Sort by latest timestamp
    all.sort(
      (a, b) => b.transaction.timestamp.compareTo(a.transaction.timestamp),
    );
    return all;
  }

  // ===== INITIALIZATION & LOCAL PERSISTENCE =====
  void _loadFromHive() {
    try {
      final prodBox = HiveBoxes.getProductsBox();
      _allProducts = prodBox.values.toList().cast<Product>();

      final txBox = HiveBoxes.getTransactionsBox();
      _allTransactions = txBox.values.toList().cast<Transaction>();

      _filteredProducts = List.from(_allProducts);
      print(
        '✅ Loaded ${_allProducts.length} products and ${_allTransactions.length} transactions from Hive',
      );
    } catch (e) {
      print('❌ Error loading from Hive: $e');
      _allProducts = [];
      _allTransactions = [];
      _filteredProducts = [];
    }
  }

  // ===== MONGO DB SYNC MECHANISMS =====

  Future<void> connectToAtlasSilently() async {
    final connected = await _mongodbService.connect();
    if (connected) {
      notifyListeners();
      syncWithAtlas();
    }
  }

  Future<void> initiateConnectionAndSync() async {
    _isConnecting = true;
    notifyListeners();

    final connected = await _mongodbService.connect();
    _isConnecting = false;
    notifyListeners();

    if (kIsWeb && !connected) {
      _lastSyncTime = "Mode Web (Lokal Saja)";
      notifyListeners();
      return;
    }

    if (connected) {
      syncWithAtlas();
    }
  }

  /// Two-way synchronization between Hive and MongoDB Atlas
  Future<void> syncWithAtlas() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();

    try {
      final connected = await _mongodbService.connect();
      if (!connected) {
        _isSyncing = false;
        notifyListeners();
        return;
      }

      final prodBox = HiveBoxes.getProductsBox();
      final txBox = HiveBoxes.getTransactionsBox();
      final delBox = HiveBoxes.getPendingDeletionsBox();

      // 1. Process pending deletions from Atlas
      final deletions = List<String>.from(delBox.values);
      for (var deletion in deletions) {
        final parts = deletion.split(':');
        if (parts.length == 2) {
          final type = parts[0];
          final id = parts[1];
          try {
            if (type == 'product') {
              await _mongodbService.deleteProductRaw(id);
            } else if (type == 'transaction') {
              await _mongodbService.deleteTransactionRaw(id);
            }
            final key = delBox.keys.firstWhere(
              (k) => delBox.get(k) == deletion,
            );
            await delBox.delete(key);
          } catch (e) {
            print("Error syncing deletion $deletion: $e");
          }
        }
      }

      // 2. Push unsynced products
      final unsyncedProducts = prodBox.values
          .where((p) => !p.isSynced)
          .toList();
      for (var prod in unsyncedProducts) {
        try {
          await _mongodbService.saveProductRaw(prod.toJson());
          final updated = prod.copyWith(isSynced: true);
          await prodBox.put(updated.id, updated);
        } catch (e) {
          print("Error pushing product ${prod.id}: $e");
        }
      }

      // 3. Push unsynced transactions
      final unsyncedTransactions = txBox.values
          .where((t) => !t.isSynced)
          .toList();
      for (var tx in unsyncedTransactions) {
        try {
          await _mongodbService.saveTransactionRaw(tx.toJson());
          final updated = tx.copyWith(isSynced: true);
          await txBox.put(updated.id, updated);
        } catch (e) {
          print("Error pushing transaction ${tx.id}: $e");
        }
      }

      // 4. Pull products from Atlas
      final remoteProductsRaw = await _mongodbService.fetchProductsRaw();
      for (var raw in remoteProductsRaw) {
        final remoteProd = Product.fromJson(raw);
        final localProd = prodBox.get(remoteProd.id);

        if (localProd == null) {
          await prodBox.put(remoteProd.id, remoteProd);
        } else {
          // If local has updates not synced, don't overwrite it
          if (localProd.isSynced &&
              remoteProd.updatedAt.isAfter(localProd.updatedAt)) {
            await prodBox.put(remoteProd.id, remoteProd);
          }
        }
      }

      // 5. Pull transactions from Atlas
      final remoteTransactionsRaw = await _mongodbService
          .fetchTransactionsRaw();
      for (var raw in remoteTransactionsRaw) {
        final remoteTx = Transaction.fromJson(raw);
        final localTx = txBox.get(remoteTx.id);

        if (localTx == null) {
          await txBox.put(remoteTx.id, remoteTx);
        }
      }

      _loadFromHive();
      _lastSyncTime = DateFormat('HH:mm').format(DateTime.now());
      print("✅ DB Synced successfully at $_lastSyncTime");
    } catch (e) {
      print("❌ Sync failed: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _writeProductToAtlas(Product product) async {
    try {
      if (isConnected) {
        await _mongodbService.saveProductRaw(product.toJson());
        final box = HiveBoxes.getProductsBox();
        final updated = product.copyWith(isSynced: true);
        await box.put(updated.id, updated);

        final idx = _allProducts.indexWhere((p) => p.id == product.id);
        if (idx != -1) {
          _allProducts[idx] = updated;
          final fIdx = _filteredProducts.indexWhere((p) => p.id == product.id);
          if (fIdx != -1) _filteredProducts[fIdx] = updated;
          notifyListeners();
        }
      }
    } catch (e) {
      print("Error writing product to Atlas: $e");
    }
  }

  Future<void> _writeTransactionToAtlas(Transaction tx) async {
    try {
      if (isConnected) {
        await _mongodbService.saveTransactionRaw(tx.toJson());
        final box = HiveBoxes.getTransactionsBox();
        final updated = tx.copyWith(isSynced: true);
        await box.put(updated.id, updated);

        final idx = _allTransactions.indexWhere((t) => t.id == tx.id);
        if (idx != -1) {
          _allTransactions[idx] = updated;
          notifyListeners();
        }
      }
    } catch (e) {
      print("Error writing transaction to Atlas: $e");
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
      if (_isSortAscending) {
        _filteredProducts.sort((a, b) => a.stock.compareTo(b.stock));
      } else {
        _filteredProducts.sort((a, b) => b.stock.compareTo(a.stock));
      }
    }
  }

  Future<void> addProduct(String name, int stock, String location) async {
    final newProduct = Product(
      id: 'prod_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      stock: stock,
      location: location,
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    // Save locally
    final box = HiveBoxes.getProductsBox();
    box.put(newProduct.id, newProduct);
    _allProducts.add(newProduct);
    searchProduct(_searchQuery);

    // Sync to Atlas
    await _writeProductToAtlas(newProduct);
  }

  Future<void> updateProduct({
    required String id,
    required String name,
    required int stock,
    required String location,
  }) async {
    final index = _allProducts.indexWhere((p) => p.id == id);
    if (index != -1) {
      final updatedProduct = Product(
        id: id,
        name: name,
        stock: stock,
        location: location,
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      // Save locally
      final box = HiveBoxes.getProductsBox();
      await box.put(id, updatedProduct);
      _allProducts[index] = updatedProduct;
      searchProduct(_searchQuery);

      // Sync to Atlas
      await _writeProductToAtlas(updatedProduct);
    }
  }

  Future<void> deleteProduct(String productId) async {
    final box = HiveBoxes.getProductsBox();
    await box.delete(productId);
    _allProducts.removeWhere((p) => p.id == productId);

    // Delete associated transactions locally
    final txBox = HiveBoxes.getTransactionsBox();
    final txToDelete = _allTransactions
        .where((t) => t.productId == productId)
        .toList();
    for (var tx in txToDelete) {
      await txBox.delete(tx.id);
      _allTransactions.removeWhere((t) => t.id == tx.id);
      if (isConnected) {
        await _mongodbService
            .deleteTransactionRaw(tx.id)
            .catchError((e) => print(e));
      } else {
        final delBox = HiveBoxes.getPendingDeletionsBox();
        await delBox.add('transaction:${tx.id}');
      }
    }

    searchProduct(_searchQuery);

    // Sync deletion to Atlas
    if (isConnected) {
      try {
        await _mongodbService.deleteProductRaw(productId);
      } catch (e) {
        print("Failed to delete product from Atlas: $e");
      }
    } else {
      final delBox = HiveBoxes.getPendingDeletionsBox();
      await delBox.add('product:$productId');
    }
  }

  // ===== TRANSACTION OPERATIONS =====

  bool isDocumentNumberExists(String productId, String documentNumber) {
    return _allTransactions.any(
      (t) =>
          t.productId == productId &&
          t.documentNumber.toLowerCase() == documentNumber.toLowerCase(),
    );
  }

  Future<bool> addIncoming({
    required String productId,
    required int quantity,
    required String documentNumber,
    String? notes,
  }) async {
    try {
      if (quantity <= 0) {
        throw Exception('Quantity harus lebih besar dari 0');
      }
      if (documentNumber.trim().isEmpty) {
        throw Exception('Nomor surat jalan tidak boleh kosong');
      }
      if (isDocumentNumberExists(productId, documentNumber)) {
        throw Exception(
          'Nomor surat jalan "$documentNumber" sudah digunakan untuk produk ini',
        );
      }

      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) {
        throw Exception('Product tidak ditemukan');
      }

      final product = _allProducts[productIndex];
      final previousStock = product.stock;
      final newStock = previousStock + quantity;

      // Update product
      final updatedProduct = product.copyWith(
        stock: newStock,
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      // Create transaction
      final transaction = Transaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        productId: productId,
        type: 'incoming',
        quantity: quantity,
        documentNumber: documentNumber,
        notes: notes,
        previousStock: previousStock,
        newStock: newStock,
        timestamp: DateTime.now(),
        isSynced: false,
      );

      // Save locally
      final prodBox = HiveBoxes.getProductsBox();
      await prodBox.put(productId, updatedProduct);
      _allProducts[productIndex] = updatedProduct;

      final txBox = HiveBoxes.getTransactionsBox();
      await txBox.put(transaction.id, transaction);
      _allTransactions.add(transaction);

      searchProduct(_searchQuery);

      // Sync to Atlas
      await _writeProductToAtlas(updatedProduct);
      await _writeTransactionToAtlas(transaction);

      return true;
    } catch (e) {
      print('Error adding incoming: $e');
      rethrow;
    }
  }

  Future<bool> addOutgoing({
    required String productId,
    required int quantity,
    required String documentNumber,
    String? recipientName,
    String? expedition,
    String? notes,
  }) async {
    try {
      if (quantity <= 0) {
        throw Exception('Quantity harus lebih besar dari 0');
      }
      if (documentNumber.trim().isEmpty) {
        throw Exception('Nomor invoice/resi tidak boleh kosong');
      }

      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) {
        throw Exception('Product tidak ditemukan');
      }

      final product = _allProducts[productIndex];

      if (quantity > product.stock) {
        throw Exception(
          'Stok tidak cukup. Stok tersedia: ${product.stock}, diminta: $quantity',
        );
      }

      if (isDocumentNumberExists(productId, documentNumber)) {
        throw Exception(
          'Nomor surat jalan/resi "$documentNumber" sudah digunakan untuk produk ini',
        );
      }

      final previousStock = product.stock;
      final newStock = previousStock - quantity;

      // Update product
      final updatedProduct = product.copyWith(
        stock: newStock,
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      // Create transaction
      final transaction = Transaction(
        id: 'tx_${DateTime.now().millisecondsSinceEpoch}',
        productId: productId,
        type: 'outgoing',
        quantity: quantity,
        documentNumber: documentNumber,
        notes: notes,
        previousStock: previousStock,
        newStock: newStock,
        timestamp: DateTime.now(),
        expedition: expedition,
        recipientName: recipientName,
        isSynced: false,
      );

      // Save locally
      final prodBox = HiveBoxes.getProductsBox();
      await prodBox.put(productId, updatedProduct);
      _allProducts[productIndex] = updatedProduct;

      final txBox = HiveBoxes.getTransactionsBox();
      await txBox.put(transaction.id, transaction);
      _allTransactions.add(transaction);

      searchProduct(_searchQuery);

      // Sync to Atlas
      await _writeProductToAtlas(updatedProduct);
      await _writeTransactionToAtlas(transaction);

      return true;
    } catch (e) {
      print('Error adding outgoing: $e');
      rethrow;
    }
  }

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

      final txIndex = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (txIndex == -1) throw Exception('Transaksi tidak ditemukan');
      final oldTransaction = _allTransactions[txIndex];

      final int oldQuantity = oldTransaction.quantity;
      final int diff = newQuantity - oldQuantity;

      int newProductStock = product.stock;
      if (oldTransaction.isIncoming) {
        if (product.stock + diff < 0) {
          throw Exception('Stok tidak mencukupi untuk penyesuaian ini');
        }
        newProductStock += diff;
      } else {
        if (product.stock - diff < 0) {
          throw Exception('Stok tidak mencukupi untuk penyesuaian ini');
        }
        newProductStock -= diff;
      }

      final updatedProduct = product.copyWith(
        stock: newProductStock,
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      final updatedTransaction = oldTransaction.copyWith(
        quantity: newQuantity,
        newStock:
            oldTransaction.previousStock +
            (oldTransaction.isIncoming ? newQuantity : -newQuantity),
        isSynced: false,
      );

      // Save locally
      final prodBox = HiveBoxes.getProductsBox();
      await prodBox.put(productId, updatedProduct);
      _allProducts[productIndex] = updatedProduct;

      final txBox = HiveBoxes.getTransactionsBox();
      await txBox.put(transactionId, updatedTransaction);
      _allTransactions[txIndex] = updatedTransaction;

      searchProduct(_searchQuery);

      // Sync to Atlas
      await _writeProductToAtlas(updatedProduct);
      await _writeTransactionToAtlas(updatedTransaction);
    } catch (e) {
      print('Error editing transaction: $e');
      rethrow;
    }
  }

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
      final List<Map<String, dynamic>> processingData = [];

      // Validation
      for (final item in items) {
        final String productId = item['productId'];
        final int quantity = item['quantity'];

        final productIndex = _allProducts.indexWhere((p) => p.id == productId);
        if (productIndex == -1) throw Exception('Produk tidak ditemukan');

        final product = _allProducts[productIndex];

        if (isDocumentNumberExists(productId, documentNumber)) {
          throw Exception(
            'Nomor dokumen "$documentNumber" sudah digunakan untuk "${product.name}"',
          );
        }

        if (!isIncoming && quantity > product.stock) {
          throw Exception(
            'Stok "${product.name}" tidak mencukupi (Tersedia: ${product.stock}, Diminta: $quantity)',
          );
        }

        processingData.add({
          'product': product,
          'quantity': quantity,
          'index': productIndex,
        });
      }

      // Execution
      final now = DateTime.now();
      final prodBox = HiveBoxes.getProductsBox();
      final txBox = HiveBoxes.getTransactionsBox();

      for (final data in processingData) {
        final Product product = data['product'];
        final int quantity = data['quantity'];
        final int productIndex = data['index'];

        final previousStock = product.stock;
        final newStock = isIncoming
            ? previousStock + quantity
            : previousStock - quantity;

        final updatedProduct = product.copyWith(
          stock: newStock,
          updatedAt: now,
          isSynced: false,
        );

        final transaction = Transaction(
          id: 'tx_${now.millisecondsSinceEpoch}_${product.id}',
          productId: product.id,
          type: type,
          quantity: quantity,
          documentNumber: documentNumber,
          notes: notes,
          previousStock: previousStock,
          newStock: newStock,
          timestamp: now,
          expedition: expedition,
          recipientName: recipientName,
          isSynced: false,
        );

        // Save locally
        await prodBox.put(product.id, updatedProduct);
        _allProducts[productIndex] = updatedProduct;

        await txBox.put(transaction.id, transaction);
        _allTransactions.add(transaction);

        // Sync to Atlas
        await _writeProductToAtlas(updatedProduct);
        await _writeTransactionToAtlas(transaction);
      }

      searchProduct(_searchQuery);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteTransaction({
    required String productId,
    required String transactionId,
  }) async {
    try {
      final productIndex = _allProducts.indexWhere((p) => p.id == productId);
      if (productIndex == -1) throw Exception('Product tidak ditemukan');
      final product = _allProducts[productIndex];

      final txIndex = _allTransactions.indexWhere((t) => t.id == transactionId);
      if (txIndex == -1) throw Exception('Transaksi tidak ditemukan');
      final transaction = _allTransactions[txIndex];

      int newStock = product.stock;
      if (transaction.isIncoming) {
        if (product.stock - transaction.quantity < 0) {
          throw Exception('Gagal menghapus: Stok akan menjadi negatif');
        }
        newStock -= transaction.quantity;
      } else {
        newStock += transaction.quantity;
      }

      final updatedProduct = product.copyWith(
        stock: newStock,
        updatedAt: DateTime.now(),
        isSynced: false,
      );

      // Save locally
      final prodBox = HiveBoxes.getProductsBox();
      await prodBox.put(productId, updatedProduct);
      _allProducts[productIndex] = updatedProduct;

      final txBox = HiveBoxes.getTransactionsBox();
      await txBox.delete(transactionId);
      _allTransactions.removeAt(txIndex);

      searchProduct(_searchQuery);

      // Sync to Atlas
      await _writeProductToAtlas(updatedProduct);
      if (isConnected) {
        try {
          await _mongodbService.deleteTransactionRaw(transactionId);
        } catch (e) {
          print("Failed to delete transaction from Atlas: $e");
        }
      } else {
        final delBox = HiveBoxes.getPendingDeletionsBox();
        await delBox.add('transaction:$transactionId');
      }
    } catch (e) {
      rethrow;
    }
  }

  List<Transaction> getTransactionHistory(String productId) {
    return _allTransactions.where((t) => t.productId == productId).toList();
  }

  Product? getProductById(String productId) {
    try {
      return _allProducts.firstWhere((p) => p.id == productId);
    } catch (e) {
      return null;
    }
  }
}
