import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';
import 'package:gudang/hive_boxes.dart';
import 'package:gudang/product.dart';
import 'package:gudang/transaction.dart';
import 'package:gudang/inventory_provider.dart';
import 'package:gudang/inventory_page.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('gudang_widget_test_');
    Hive.init(tempDir.path);
    await HiveBoxes.init();
  });

  tearDownAll(() async {
    await HiveBoxes.closeAllBoxes();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveBoxes.getProductsBox().clear();
    await HiveBoxes.getTransactionsBox().clear();
  });

  testWidgets('InventoryPage shows empty state when no products', (tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ],
        child: const MaterialApp(home: InventoryPage()),
      ),
    );
    await tester.pump();
    expect(find.text('Belum Ada Produk'), findsOneWidget);
  });
}
