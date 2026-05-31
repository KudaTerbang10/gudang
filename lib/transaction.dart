import 'package:hive/hive.dart';
import 'product.dart';

part 'transaction.g.dart';

@HiveType(typeId: 1)
class Transaction extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String type; // 'incoming' atau 'outgoing'

  @HiveField(2)
  final int quantity;

  @HiveField(3)
  final String documentNumber; // Nomor surat serah terima atau invoice/resi

  @HiveField(4)
  final String? notes;

  @HiveField(5)
  final int previousStock;

  @HiveField(6)
  final int newStock;

  @HiveField(7)
  final DateTime timestamp;

  @HiveField(8)
  final String? expedition;

  @HiveField(9)
  final String? recipientName;

  @HiveField(10)
  final String productId;

  @HiveField(11)
  final bool isSynced;

  @HiveField(12)
  final String productName;

  Transaction({
    required this.id,
    required this.productId,
    required this.productName,
    required this.type,
    required this.quantity,
    required this.documentNumber,
    this.notes,
    required this.previousStock,
    required this.newStock,
    required this.timestamp,
    this.expedition,
    this.recipientName,
    required this.isSynced,
  });

  Transaction copyWith({
    String? id,
    String? productId,
    String? productName,
    String? type,
    int? quantity,
    String? documentNumber,
    String? notes,
    int? previousStock,
    int? newStock,
    DateTime? timestamp,
    String? expedition,
    String? recipientName,
    bool? isSynced,
  }) {
    return Transaction(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      type: type ?? this.type,
      quantity: quantity ?? this.quantity,
      documentNumber: documentNumber ?? this.documentNumber,
      notes: notes ?? this.notes,
      previousStock: previousStock ?? this.previousStock,
      newStock: newStock ?? this.newStock,
      timestamp: timestamp ?? this.timestamp,
      expedition: expedition ?? this.expedition,
      recipientName: recipientName ?? this.recipientName,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  bool get isIncoming => type == 'incoming';
  bool get isOutgoing => type == 'outgoing';

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'productId': productId,
      'productName': productName,
      'type': type,
      'quantity': quantity,
      'documentNumber': documentNumber,
      'notes': notes,
      'previousStock': previousStock,
      'newStock': newStock,
      'timestamp': timestamp.toIso8601String(),
      'expedition': expedition,
      'recipientName': recipientName,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      productName: json['productName'] as String? ?? '',
      type: json['type'] as String? ?? 'incoming',
      quantity: json['quantity'] as int? ?? 0,
      documentNumber: json['documentNumber'] as String? ?? '',
      notes: json['notes'] as String?,
      previousStock: json['previousStock'] as int? ?? 0,
      newStock: json['newStock'] as int? ?? 0,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      expedition: json['expedition'] as String?,
      recipientName: json['recipientName'] as String?,
      isSynced: true,
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, type: $type, qty: $quantity, docNumber: $documentNumber, timestamp: $timestamp)';
  }
}

class TransactionWithProduct {
  final Transaction transaction;
  final Product product;
  TransactionWithProduct(this.transaction, this.product);
}
