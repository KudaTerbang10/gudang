import 'package:hive/hive.dart';
import 'product.dart';
import 'transaction.dart';

class HiveBoxes {
  static const String productsBox = 'products';

  /// Initialize Hive and open boxes
  static Future<void> init() async {
    try {
      // Register adapters
      Hive.registerAdapter(ProductAdapter());
      Hive.registerAdapter(TransactionAdapter());

      // Open boxes
      await Hive.openBox<Product>(productsBox);

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

  /// Close all boxes
  static Future<void> closeAllBoxes() async {
    await Hive.close();
  }
}
