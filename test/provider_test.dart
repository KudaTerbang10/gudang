import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gudang/hive_boxes.dart';
import 'package:gudang/inventory_provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('gudang_test_');
    Hive.init(tempDir.path);
    await HiveBoxes.init();
  });

  tearDownAll(() async {
    await HiveBoxes.closeAllBoxes();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    // Clear all boxes before each test
    await HiveBoxes.getProductsBox().clear();
    await HiveBoxes.getTransactionsBox().clear();
    await HiveBoxes.getPendingDeletionsBox().clear();
  });

  group('InventoryProvider - offline operations', () {
    late InventoryProvider provider;

    setUp(() {
      provider = InventoryProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('starts with empty data', () {
      expect(provider.allProducts, isEmpty);
      expect(provider.allTransactions, isEmpty);
      expect(provider.isConnected, false);
    });

    test('addProduct creates product and updates list', () async {
      await provider.addProduct('Kain Cotton 30s', 50, 'A1');
      expect(provider.allProducts.length, 1);
      expect(provider.allProducts.first.name, 'Kain Cotton 30s');
      expect(provider.allProducts.first.stock, 50);
      expect(provider.allProducts.first.location, 'A1');
    });

    test('addProduct persists to Hive', () async {
      await provider.addProduct('Kain Rayon', 20, 'B2');
      final box = HiveBoxes.getProductsBox();
      expect(box.values.length, 1);
      expect(box.values.first.name, 'Kain Rayon');
    });

    test('addProduct sets isSynced false for offline', () async {
      await provider.addProduct('Test', 10, 'C1');
      expect(provider.allProducts.first.isSynced, false);
    });

    test('addProduct with empty search restores all products', () async {
      await provider.addProduct('A', 10, 'L1');
      await provider.addProduct('B', 20, 'L2');
      provider.searchProduct('');
      await Future.delayed(const Duration(milliseconds: 350));
      expect(provider.products.length, 2);
    });

    test('searchProduct filters by name', () async {
      await provider.addProduct('Kain Cotton', 10, 'A1');
      await Future.delayed(const Duration(milliseconds: 1));
      await provider.addProduct('Benang Jahit', 5, 'B1');
      await Future.delayed(const Duration(milliseconds: 1));
      await provider.addProduct('Kain Rayon', 15, 'C1');
      provider.searchProduct('Kain');
      await Future.delayed(const Duration(milliseconds: 350));
      expect(provider.products.length, 2);
      expect(provider.products.every((p) => p.name.contains('Kain')), true);
    });

    test('searchProduct with empty query returns all', () async {
      await provider.addProduct('Cotton', 10, 'A1');
      await provider.addProduct('Rayon', 5, 'B1');
      provider.searchProduct('');
      await Future.delayed(const Duration(milliseconds: 350));
      expect(provider.products.length, 2);
    });

    test('updateProduct changes product fields', () async {
      await provider.addProduct('Cotton', 10, 'A1');
      final id = provider.allProducts.first.id;
      await provider.updateProduct(id: id, name: 'Cotton Premium', stock: 15, location: 'A2');
      expect(provider.allProducts.length, 1);
      expect(provider.allProducts.first.name, 'Cotton Premium');
      expect(provider.allProducts.first.stock, 15);
      expect(provider.allProducts.first.location, 'A2');
    });

    test('deleteProduct removes product and persists', () async {
      await provider.addProduct('Cotton', 10, 'A1');
      final id = provider.allProducts.first.id;
      await provider.deleteProduct(id);
      expect(provider.allProducts, isEmpty);
      final box = HiveBoxes.getProductsBox();
      expect(box.values, isEmpty);
    });

    test('addIncoming updates stock and creates transaction', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      final id = provider.allProducts.first.id;
      final result = await provider.addIncoming(
        productId: id,
        quantity: 10,
        documentNumber: 'DO/001',
      );
      expect(result, true);
      expect(provider.allProducts.first.stock, 60);
      expect(provider.allTransactions.length, 1);
      expect(provider.allTransactions.first.type, 'incoming');
      expect(provider.allTransactions.first.quantity, 10);
    });

    test('addIncoming rejects duplicate document number', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      final id = provider.allProducts.first.id;
      await provider.addIncoming(productId: id, quantity: 10, documentNumber: 'DO/001');
      expect(
        () async => await provider.addIncoming(productId: id, quantity: 5, documentNumber: 'DO/001'),
        throwsException,
      );
    });

    test('addOutgoing decreases stock', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      final id = provider.allProducts.first.id;
      await provider.addOutgoing(productId: id, quantity: 10, documentNumber: 'INV/001');
      expect(provider.allProducts.first.stock, 40);
      expect(provider.allTransactions.first.type, 'outgoing');
    });

    test('addOutgoing rejects insufficient stock', () async {
      await provider.addProduct('Cotton', 5, 'A1');
      final id = provider.allProducts.first.id;
      expect(
        () async => await provider.addOutgoing(productId: id, quantity: 10, documentNumber: 'INV/001'),
        throwsException,
      );
    });

    test('getTransactionHistory returns per-product transactions', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final cottonId = provider.allProducts[0].id;
      final rayonId = provider.allProducts[1].id;
      await provider.addIncoming(productId: cottonId, quantity: 10, documentNumber: 'DO/001');
      await provider.addIncoming(productId: rayonId, quantity: 5, documentNumber: 'DO/002');
      final cottonHistory = provider.getTransactionHistory(cottonId);
      final rayonHistory = provider.getTransactionHistory(rayonId);
      expect(cottonHistory.length, 1);
      expect(rayonHistory.length, 1);
    });

    test('getProductById returns correct product', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      final id = provider.allProducts.first.id;
      final found = provider.getProductById(id);
      expect(found, isNotNull);
      expect(found!.name, 'Cotton');
      final notFound = provider.getProductById('nonexistent');
      expect(notFound, isNull);
    });

    test('allTransactionsWithProduct is cached and contains product info', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      final id = provider.allProducts.first.id;
      await provider.addIncoming(productId: id, quantity: 10, documentNumber: 'DO/001');
      final result = provider.allTransactionsWithProduct;
      expect(result.length, 1);
      expect(result.first.product.name, 'Cotton');
      expect(result.first.transaction.quantity, 10);

      // Second call returns cached
      final result2 = provider.allTransactionsWithProduct;
      expect(identical(result, result2), true);
    });

    test('toggleView switches table/card view', () {
      expect(provider.isTableView, true);
      provider.toggleView();
      expect(provider.isTableView, false);
      provider.toggleView();
      expect(provider.isTableView, true);
    });

    test('isDocumentNumberExists checks by product', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final cottonId = provider.allProducts[0].id;
      final rayonId = provider.allProducts[1].id;
      expect(cottonId, isNot(equals(rayonId)), reason: 'IDs must be unique for this test');
      await provider.addIncoming(productId: cottonId, quantity: 10, documentNumber: 'DO/001');
      expect(provider.isDocumentNumberExists(cottonId, 'DO/001'), true);
      expect(provider.isDocumentNumberExists(rayonId, 'DO/001'), false);
      expect(provider.isDocumentNumberExists(cottonId, 'DO/999'), false);
    });

    test('addBulkTransactions creates transactions for multiple products', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Sutra', 20, 'C1');
      final ids = provider.allProducts.map((p) => p.id).toList();

      await provider.addBulkTransactions(
        type: 'incoming',
        documentNumber: 'BULK/001',
        items: [
          {'productId': ids[0], 'quantity': 5},
          {'productId': ids[1], 'quantity': 3},
          {'productId': ids[2], 'quantity': 7},
        ],
      );

      expect(provider.allTransactions.length, 3);
      expect(provider.allTransactions.every((t) => t.documentNumber == 'BULK/001'), true);
      expect(provider.allTransactions.every((t) => t.type == 'incoming'), true);
    });

    test('addBulkTransactions updates product stocks', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final ids = provider.allProducts.map((p) => p.id).toList();

      await provider.addBulkTransactions(
        type: 'incoming',
        documentNumber: 'BULK/002',
        items: [
          {'productId': ids[0], 'quantity': 10},
          {'productId': ids[1], 'quantity': 5},
        ],
      );

      final cotton = provider.getProductById(ids[0])!;
      final rayon = provider.getProductById(ids[1])!;
      expect(cotton.stock, 60);
      expect(rayon.stock, 35);
    });

    test('addBulkTransactions outgoing decreases stock', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final ids = provider.allProducts.map((p) => p.id).toList();

      await provider.addBulkTransactions(
        type: 'outgoing',
        documentNumber: 'BULK/OUT/001',
        items: [
          {'productId': ids[0], 'quantity': 5},
          {'productId': ids[1], 'quantity': 3},
        ],
      );

      expect(provider.getProductById(ids[0])!.stock, 45);
      expect(provider.getProductById(ids[1])!.stock, 27);
    });

    test('addBulkTransactions rejects duplicate document number for same product', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final ids = provider.allProducts.map((p) => p.id).toList();

      // First bulk: success
      await provider.addBulkTransactions(
        type: 'incoming',
        documentNumber: 'BULK/DUP/001',
        items: [
          {'productId': ids[0], 'quantity': 5},
          {'productId': ids[1], 'quantity': 3},
        ],
      );

      // Second bulk with same document number for cotton should fail
      await expectLater(
        () => provider.addBulkTransactions(
          type: 'incoming',
          documentNumber: 'BULK/DUP/001',
          items: [
            {'productId': ids[0], 'quantity': 2},
          ],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('addBulkTransactions rejects insufficient stock for outgoing', () async {
      await provider.addProduct('Cotton', 5, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final ids = provider.allProducts.map((p) => p.id).toList();

      await expectLater(
        () => provider.addBulkTransactions(
          type: 'outgoing',
          documentNumber: 'BULK/OUT/002',
          items: [
            {'productId': ids[0], 'quantity': 10}, // exceeds Cotton stock of 5
            {'productId': ids[1], 'quantity': 3},
          ],
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('addBulkTransactions persists transactions to Hive', () async {
      await provider.addProduct('Cotton', 50, 'A1');
      await Future.delayed(const Duration(milliseconds: 2));
      await provider.addProduct('Rayon', 30, 'B1');
      final ids = provider.allProducts.map((p) => p.id).toList();

      await provider.addBulkTransactions(
        type: 'incoming',
        documentNumber: 'BULK/HIVE/001',
        items: [
          {'productId': ids[0], 'quantity': 5},
          {'productId': ids[1], 'quantity': 3},
        ],
      );

      final txBox = HiveBoxes.getTransactionsBox();
      expect(txBox.values.length, 2);
    });

    test('addBulkTransactions with empty items throws', () async {
      await expectLater(
        () => provider.addBulkTransactions(
          type: 'incoming',
          documentNumber: 'BULK/EMPTY/001',
          items: [],
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('sync related', () {
    late InventoryProvider provider;

    setUp(() {
      provider = InventoryProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('_lastSyncedAt starts null when never synced', () {
      expect(provider.lastSyncTime, isNull);
      expect(provider.isConnected, false);
      expect(provider.isConnecting, false);
      expect(provider.isSyncing, false);
    });
  });
}
