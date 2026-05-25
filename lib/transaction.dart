import 'package:hive/hive.dart';

part 'transaction.g.dart';

enum TransactionType { incoming, outgoing }

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

  Transaction({
    required this.id,
    required this.type,
    required this.quantity,
    required this.documentNumber,
    this.notes,
    required this.previousStock,
    required this.newStock,
    required this.timestamp,
    this.expedition,
  });

  bool get isIncoming => type == 'incoming';
  bool get isOutgoing => type == 'outgoing';

  @override
  String toString() {
    return 'Transaction(id: $id, type: $type, qty: $quantity, docNumber: $documentNumber, timestamp: $timestamp)';
  }
}
