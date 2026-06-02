import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class MongodbService {
  static final MongodbService _instance = MongodbService._internal();
  factory MongodbService() => _instance;
  MongodbService._internal();

  Db? _db;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  /// Attempt connection to MongoDB Atlas
  Future<bool> connect() async {
    try {
      if (kIsWeb) {
        print("⚠️ MongoDB Direct Connection is not supported on Web browser.");
        return false;
      }

      if (_db != null && _isConnected) {
        return true;
      }

      await close();

      _db = await Db.create(
        "mongodb+srv://adiaz:100795@cluster0.w1nn1ua.mongodb.net/gudang?retryWrites=true&w=majority",
      );

      // Set timeout for direct connection attempts
      await _db!.open().timeout(const Duration(seconds: 8));
      _isConnected = true;

      // Menambahkan index untuk optimasi pencarian dan sorting
      if (_isConnected) {
        // 1. Prioritas Utama: Timestamp (untuk sorting default & filter periode)
        await _db!
            .collection('transactions')
            .createIndex(keys: {'timestamp': -1});

        // 2. Prioritas Kedua: Document Number (untuk pencarian spesifik/ID transaksi)
        await _db!
            .collection('transactions')
            .createIndex(keys: {'documentNumber': 1});

        // 3. Compound Index: Timestamp + Document Number
        // Ini sangat efektif untuk pencarian "Cari nomor dokumen di rentang waktu tertentu"
        await _db!
            .collection('transactions')
            .createIndex(keys: {'timestamp': -1, 'documentNumber': 1});

        // 4. Index untuk productId (per-product history query)
        await _db!
            .collection('transactions')
            .createIndex(keys: {'productId': 1, 'timestamp': -1});

        // Tambahkan index untuk nama produk agar pencarian di Atlas lebih cepat
        await _db!.collection('products').createIndex(keys: {'name': 1});
      }

      print("✅ Connected to MongoDB Atlas");
      return true;
    } catch (e) {
      print("❌ MongoDB connection error: $e");
      _isConnected = false;
      _db = null;
      return false;
    }
  }

  /// Close connection
  Future<void> close() async {
    try {
      if (_db != null) {
        await _db!.close();
      }
    } catch (e) {
      print("Error closing MongoDB connection: $e");
    } finally {
      _db = null;
      _isConnected = false;
    }
  }

  /// Fetch all products from Atlas
  Future<List<Map<String, dynamic>>> fetchProductsRaw() async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    return await _db!.collection('products').find().toList();
  }

  /// Fetch products updated since given timestamp (incremental sync)
  Future<List<Map<String, dynamic>>> fetchProductsSince(DateTime since) async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    final query = where.gte('updatedAt', since.toIso8601String());
    return await _db!.collection('products').find(query).toList();
  }

  /// Fetch all transactions from Atlas
  Future<List<Map<String, dynamic>>> fetchTransactionsRaw() async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    return await _db!.collection('transactions').find().toList();
  }

  /// Fetch only transaction IDs from Atlas (lightweight, for deletion detection)
  Future<Set<String>> fetchTransactionIdsRaw() async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    final docs =
        await _db!.collection('transactions').find(where.fields(['_id'])).toList();
    return docs
        .map((doc) => (doc['_id'] ?? doc['id']).toString())
        .toSet();
  }

  /// Fetch transactions created since given timestamp (incremental sync)
  Future<List<Map<String, dynamic>>> fetchTransactionsSince(
      DateTime since) async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    final query = where.gte('timestamp', since.toIso8601String());
    return await _db!.collection('transactions').find(query).toList();
  }

  /// Upsert a product to Atlas
  Future<void> saveProductRaw(Map<String, dynamic> productJson) async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    final coll = _db!.collection('products');
    final id = productJson['_id'];
    await coll.update(where.eq('_id', id), productJson, upsert: true);
  }

  /// Delete a product from Atlas
  Future<void> deleteProductRaw(String id) async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    await _db!.collection('products').remove(where.eq('_id', id));
  }

  /// Upsert a transaction to Atlas
  Future<void> saveTransactionRaw(Map<String, dynamic> transactionJson) async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    final coll = _db!.collection('transactions');
    final id = transactionJson['_id'];
    await coll.update(where.eq('_id', id), transactionJson, upsert: true);
  }

  /// Delete a transaction from Atlas
  Future<void> deleteTransactionRaw(String id) async {
    if (!isConnected) throw Exception("Not connected to Atlas");
    await _db!.collection('transactions').remove(where.eq('_id', id));
  }
}
