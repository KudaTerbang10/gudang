import 'package:hive/hive.dart';
import 'product.dart';
import 'transaction.dart';

class HiveBoxes {
  static const String productsBox = 'products';
  static const String transactionsBox = 'transactions';
  static const String pendingDeletionsBox = 'pending_deletions';

  /// Initialize Hive and open boxes
  static Future<void> init() async {
    try {
      // Register adapters
      Hive.registerAdapter(ProductAdapter());
      Hive.registerAdapter(TransactionAdapter());

      // Open boxes
      await Hive.openBox<Product>(productsBox);
      await Hive.openBox<Transaction>(transactionsBox);
      await Hive.openBox<String>(pendingDeletionsBox);

      print('✅ Hive initialized successfully');
    } catch (e) {
      print('❌ Error initializing Hive: $e');
      rethrow;
    }
  }

  /// Get products box
  static Box<Product> getProductsBox() {
    return Hive.box<Product>(productsBox);
  }

  /// Get transactions box
  static Box<Transaction> getTransactionsBox() {
    return Hive.box<Transaction>(transactionsBox);
  }

  /// Get pending deletions box
  static Box<String> getPendingDeletionsBox() {
    return Hive.box<String>(pendingDeletionsBox);
  }

  /// Close all boxes
  static Future<void> closeAllBoxes() async {
    await Hive.close();
  }
}
