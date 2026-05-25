import 'package:hive/hive.dart';
import 'transaction.dart';

part 'product.g.dart';

@HiveType(typeId: 0)
class Product extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  int stock;

  @HiveField(3)
  final String location;

  @HiveField(4)
  final List<Transaction> history;

  Product({
    required this.id,
    required this.name,
    required this.stock,
    required this.location,
    List<Transaction>? history,
  }) : history = history ?? [];

  @override
  String toString() =>
      'Product(id: $id, name: $name, stock: $stock, location: $location)';
}
