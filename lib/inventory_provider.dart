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

  DateTime? _lastSyncedAt;
  List<TransactionWithProduct>? _cachedTransactionsWithProduct;

  // Map indexes untuk O(1) lookup
  final Map<String, Product> _productsById = {};
  final Map<String, List<Transaction>> _transactionsByProductId = {};
  final Map<String, Set<String>> _docNumbersByProductId = {};

  Timer? _searchDebounce;

  InventoryProvider() {
    _loadLastSyncedAt();
    _loadFromHive();
    // Connect and sync on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initiateConnectionAndSync();
    });

    // Run periodic sync in background every 3 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 3), (timer) {
      if (isConnected) {
        syncWithAtlas();
      } else {
        connectToAtlasSilently();
      }
    });
  }

  void _loadLastSyncedAt() {
    try {
      final box = HiveBoxes.getConfigBox();
      final val = box.get('lastSyncedAt');
      if (val != null) {
        _lastSyncedAt = DateTime.parse(val);
      }
    } catch (e) {
      print('Error loading lastSyncedAt: $e');
    }
  }

  void _saveLastSyncedAt(DateTime time) {
    _lastSyncedAt = time;
    try {
      final box = HiveBoxes.getConfigBox();
      box.put('lastSyncedAt', time.toIso8601String());
    } catch (e) {
      print('Error saving lastSyncedAt: $e');
    }
  }

  void _invalidateCache() {
    _cachedTransactionsWithProduct = null;
    _rebuildIndexes();
  }

  void _rebuildIndexes() {
    _productsById
      ..clear()
      ..addEntries(_allProducts.map((p) => MapEntry(p.id, p)));

    _transactionsByProductId.clear();
    _docNumbersByProductId.clear();
    for (var tx in _allTransactions) {
      _transactionsByProductId.putIfAbsent(tx.productId, () => []).add(tx);
      _docNumbersByProductId.putIfAbsent(tx.productId, () => {}).add(tx.documentNumber.toLowerCase());
    }
    // Sort each product's transaction list by timestamp descending
    for (final list in _transactionsByProductId.values) {
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _searchDebounce?.cancel();
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
    if (_cachedTransactionsWithProduct != null) {
      return _cachedTransactionsWithProduct!;
    }

    final all = <TransactionWithProduct>[];
    for (var tx in _allTransactions) {
      final product = _productsById[tx.productId] ??
          Product(
            id: tx.productId,
            name: tx.productName.isNotEmpty
                ? tx.productName
                : 'Produk Tidak Ditemukan (${tx.productId})',
            stock: 0,
            location: '-',
            updatedAt: DateTime.now(),
            isSynced: true,
          );
      all.add(TransactionWithProduct(tx, product));
    }

    // Sort by latest timestamp (descending)
    all.sort(
      (a, b) => b.transaction.timestamp.compareTo(a.transaction.timestamp),
    );

    _cachedTransactionsWithProduct = all;
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
      _invalidateCache();
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
      bool hasChanges = false;

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
      final unsyncedProducts =
          prodBox.values.where((p) => !p.isSynced).toList();
      for (var prod in unsyncedProducts) {
        try {
          await _mongodbService.saveProductRaw(prod.toJson());
          final updated = prod.copyWith(isSynced: true);
          await prodBox.put(updated.id, updated);
          final idx = _allProducts.indexWhere((p) => p.id == updated.id);
          if (idx != -1) {
            _allProducts[idx] = updated;
            hasChanges = true;
          }
        } catch (e) {
          print("Error pushing product ${prod.id}: $e");
        }
      }

      // 3. Push unsynced transactions
      final unsyncedTransactions =
          txBox.values.where((t) => !t.isSynced).toList();
      for (var tx in unsyncedTransactions) {
        try {
          await _mongodbService.saveTransactionRaw(tx.toJson());
          final updated = tx.copyWith(isSynced: true);
          await txBox.put(updated.id, updated);
          final idx = _allTransactions.indexWhere((t) => t.id == updated.id);
          if (idx != -1) {
            _allTransactions[idx] = updated;
            hasChanges = true;
          }
        } catch (e) {
          print("Error pushing transaction ${tx.id}: $e");
        }
      }

      // 4. Pull products from Atlas (full pull — products are few)
      final remoteProductsRaw = await _mongodbService.fetchProductsRaw();
      final remoteProdIds = remoteProductsRaw
          .map((raw) => (raw['_id'] ?? raw['id']).toString())
          .toSet();

      // Sync deletions from Atlas to Local (Products)
      for (var localProd in prodBox.values.toList()) {
        if (localProd.isSynced && !remoteProdIds.contains(localProd.id)) {
          await prodBox.delete(localProd.id);
          _allProducts.removeWhere((p) => p.id == localProd.id);
          hasChanges = true;
        }
      }

      for (var raw in remoteProductsRaw) {
        final remoteProd = Product.fromJson(raw);
        final localProd = prodBox.get(remoteProd.id);
        bool changed = false;

        if (localProd == null) {
          await prodBox.put(remoteProd.id, remoteProd);
          _allProducts.add(remoteProd);
          changed = true;
        } else {
          // If local has updates not synced, don't overwrite it
          if (localProd.isSynced &&
              remoteProd.updatedAt.isAfter(localProd.updatedAt)) {
            await prodBox.put(remoteProd.id, remoteProd);
            final idx = _allProducts.indexWhere((p) => p.id == remoteProd.id);
            if (idx != -1) {
              _allProducts[idx] = remoteProd;
            }
            changed = true;
          }
        }
        if (changed) hasChanges = true;
      }

      // 5. Pull transactions from Atlas (incremental if _lastSyncedAt exists)
      final List<Map<String, dynamic>> remoteTransactionsRaw;
      if (_lastSyncedAt != null) {
        remoteTransactionsRaw =
            await _mongodbService.fetchTransactionsSince(_lastSyncedAt!);
      } else {
        remoteTransactionsRaw = await _mongodbService.fetchTransactionsRaw();
      }

      // Selalu deteksi transaksi yang dihapus dari Atlas (lightweight ID check)
      final remoteTxIds = _lastSyncedAt != null
          ? await _mongodbService.fetchTransactionIdsRaw()
          : remoteTransactionsRaw
              .map((raw) => (raw['_id'] ?? raw['id']).toString())
              .toSet();

      for (var localTx in txBox.values.toList()) {
        if (localTx.isSynced && !remoteTxIds.contains(localTx.id)) {
          // Balikkan perubahan stock sebelum hapus transaksi
          final prodBox = HiveBoxes.getProductsBox();
          final product = _allProducts.where((p) => p.id == localTx.productId).firstOrNull;
          if (product != null) {
            final reversedStock = localTx.isIncoming
                ? product.stock - localTx.quantity
                : product.stock + localTx.quantity;
            final restored = product.copyWith(
              stock: reversedStock,
              updatedAt: DateTime.now(),
              isSynced: false,
            );
            await prodBox.put(restored.id, restored);
            final pIdx = _allProducts.indexWhere((p) => p.id == product.id);
            if (pIdx != -1) _allProducts[pIdx] = restored;
          }
          await txBox.delete(localTx.id);
          _allTransactions.removeWhere((t) => t.id == localTx.id);
          hasChanges = true;
        }
      }

      for (var raw in remoteTransactionsRaw) {
        final remoteTx = Transaction.fromJson(raw);
        final localTx = txBox.get(remoteTx.id);

        if (localTx == null) {
          await txBox.put(remoteTx.id, remoteTx);
          _allTransactions.insert(0, remoteTx);
          hasChanges = true;
        }
      }

      // Update _lastSyncedAt after successful sync
      _saveLastSyncedAt(DateTime.now());

      _lastSyncTime = DateFormat('HH:mm').format(DateTime.now());

      if (hasChanges) {
        _invalidateCache();
        _filteredProducts = List.from(_allProducts);
      }

      print("✅ DB Synced successfully at $_lastSyncTime (${hasChanges ? 'changes detected' : 'no changes'})");
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
          _invalidateCache();
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
          _invalidateCache();
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
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _applySearchImmediate(_searchQuery);
    });
  }

  void _refreshSearch() {
    _searchDebounce?.cancel();
    _applySearchImmediate(_searchQuery);
  }

  void _applySearchImmediate(String query) {
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
    _invalidateCache();
    _refreshSearch();

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
      _invalidateCache();
      _refreshSearch();

      // Sync to Atlas
      await _writeProductToAtlas(updatedProduct);
    }
  }

  Future<void> deleteProduct(String productId) async {
    final box = HiveBoxes.getProductsBox();
    await box.delete(productId);
    _allProducts.removeWhere((p) => p.id == productId);
    _invalidateCache();

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
    _invalidateCache();

    _refreshSearch();

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
    final docs = _docNumbersByProductId[productId];
    if (docs == null) return false;
    return docs.contains(documentNumber.toLowerCase());
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
        productName: product.name,
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
      _allTransactions.insert(0, transaction);

      _invalidateCache();
      _refreshSearch();

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
        productName: product.name,
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
      _allTransactions.insert(0, transaction);

      _invalidateCache();
      _refreshSearch();

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

      _invalidateCache();
      _refreshSearch();

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
      if (items.isEmpty) {
        throw Exception('Daftar item kosong. Tambahkan minimal 1 item.');
      }
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

      final List<Product> batchProducts = [];
      final List<Transaction> batchTransactions = [];

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
          productName: product.name,
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

        batchProducts.add(updatedProduct);
        batchTransactions.add(transaction);

        // Save locally
        await prodBox.put(product.id, updatedProduct);
        _allProducts[productIndex] = updatedProduct;

        await txBox.put(transaction.id, transaction);
        _allTransactions.insert(0, transaction);
      }

      // Sync ke Atlas (sequential, bukan parallel — hindari "No master connection")
      if (isConnected) {
        for (final p in batchProducts) {
          await _mongodbService.saveProductRaw(p.toJson());
        }
        for (final t in batchTransactions) {
          await _mongodbService.saveTransactionRaw(t.toJson());
        }
        for (final p in batchProducts) {
          final synced = p.copyWith(isSynced: true);
          await prodBox.put(synced.id, synced);
          final idx = _allProducts.indexWhere((x) => x.id == p.id);
          if (idx != -1) _allProducts[idx] = synced;
        }
        for (final t in batchTransactions) {
          final synced = t.copyWith(isSynced: true);
          await txBox.put(synced.id, synced);
          final idx = _allTransactions.indexWhere((x) => x.id == t.id);
          if (idx != -1) _allTransactions[idx] = synced;
        }
      }

      _invalidateCache();
      _refreshSearch();
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

      _invalidateCache();
      _refreshSearch();

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
    return _transactionsByProductId[productId] ?? [];
  }

  Product? getProductById(String productId) {
    return _productsById[productId];
  }
}
