import 'package:flutter_test/flutter_test.dart';
import 'package:gudang/product.dart';
import 'package:gudang/transaction.dart';

void main() {
  group('Product', () {
    final now = DateTime(2026, 6, 2, 10, 0, 0);
    final product = Product(
      id: 'prod_1',
      name: 'Kain Cotton 30s',
      stock: 50,
      location: 'A1',
      updatedAt: now,
      isSynced: true,
    );

    test('copyWith creates modified copy', () {
      final modified = product.copyWith(stock: 30, name: 'Kain Cotton 40s');
      expect(modified.id, 'prod_1');
      expect(modified.name, 'Kain Cotton 40s');
      expect(modified.stock, 30);
      expect(modified.location, 'A1');
      expect(modified.isSynced, true);
    });

    test('toJson serializes correctly', () {
      final json = product.toJson();
      expect(json['_id'], 'prod_1');
      expect(json['name'], 'Kain Cotton 30s');
      expect(json['stock'], 50);
      expect(json['location'], 'A1');
      expect(json['updatedAt'], now.toIso8601String());
      expect(json.containsKey('isSynced'), false);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        '_id': 'prod_2',
        'name': 'Kain Rayon',
        'stock': 20,
        'location': 'B2',
        'updatedAt': now.toIso8601String(),
      };
      final result = Product.fromJson(json);
      expect(result.id, 'prod_2');
      expect(result.name, 'Kain Rayon');
      expect(result.stock, 20);
      expect(result.location, 'B2');
      expect(result.isSynced, true);
    });

    test('fromJson handles missing id gracefully', () {
      final json = {'name': 'Test', 'stock': 10, 'location': 'C1', 'updatedAt': now.toIso8601String()};
      final result = Product.fromJson(json);
      expect(result.id, '');
      expect(result.name, 'Test');
    });

    test('fromJson falls back to id key', () {
      final json = {'id': 'prod_3', 'name': 'Test'};
      final result = Product.fromJson(json);
      expect(result.id, 'prod_3');
    });
  });

  group('Transaction', () {
    final now = DateTime(2026, 6, 2, 10, 0, 0);
    final tx = Transaction(
      id: 'tx_1',
      productId: 'prod_1',
      productName: 'Kain Cotton 30s',
      type: 'incoming',
      quantity: 10,
      documentNumber: 'DO/001',
      notes: 'Restock',
      previousStock: 50,
      newStock: 60,
      timestamp: now,
      expedition: null,
      recipientName: null,
      isSynced: true,
    );

    test('isIncoming returns true for incoming type', () {
      expect(tx.isIncoming, true);
      expect(tx.isOutgoing, false);
    });

    test('copyWith modifies fields', () {
      final modified = tx.copyWith(quantity: 15, newStock: 65);
      expect(modified.quantity, 15);
      expect(modified.newStock, 65);
      expect(modified.documentNumber, 'DO/001');
    });

    test('toJson omits isSynced field', () {
      final json = tx.toJson();
      expect(json['_id'], 'tx_1');
      expect(json['productId'], 'prod_1');
      expect(json.containsKey('isSynced'), false);
    });

    test('fromJson sets isSynced to true', () {
      final json = tx.toJson();
      final result = Transaction.fromJson(json);
      expect(result.isSynced, true);
    });

    test('outgoing type returns isOutgoing true', () {
      final outgoing = tx.copyWith(type: 'outgoing', quantity: 5, previousStock: 60, newStock: 55);
      expect(outgoing.isIncoming, false);
      expect(outgoing.isOutgoing, true);
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};
      final result = Transaction.fromJson(json);
      expect(result.type, 'incoming');
      expect(result.quantity, 0);
      expect(result.isSynced, true);
    });
  });

  group('TransactionWithProduct', () {
    test('holds both transaction and product', () {
      final product = Product(id: 'p1', name: 'Test', stock: 10, location: 'A1', updatedAt: DateTime.now(), isSynced: true);
      final transaction = Transaction(id: 't1', productId: 'p1', productName: 'Test', type: 'incoming', quantity: 5, documentNumber: 'DOC/1', previousStock: 10, newStock: 15, timestamp: DateTime.now(), isSynced: true);
      final combined = TransactionWithProduct(transaction, product);
      expect(combined.transaction, transaction);
      expect(combined.product, product);
    });
  });
}
