import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'inventory_provider.dart';

class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analitik Aktivitas')),
      body: Stack(
        children: [
          const _AnalyticsBackground(),
          Consumer<InventoryProvider>(
            builder: (context, provider, child) {
              final allTransactions = provider.allTransactionsWithProduct;

              // Filter hanya transaksi keluar
              final outgoingTransactions = allTransactions
                  .where((item) => item.transaction.isOutgoing)
                  .toList();

              // Hitung Top 5 Barang Keluar
              final Map<String, int> productOutgoingCounts = {};
              for (var item in outgoingTransactions) {
                productOutgoingCounts.update(
                  item.product.name,
                  (value) => value + item.transaction.quantity,
                  ifAbsent: () => item.transaction.quantity,
                );
              }
              final top5Products = productOutgoingCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              // Hitung Top 3 Penerima
              final Map<String, int> recipientOutgoingCounts = {};
              for (var item in outgoingTransactions) {
                if (item.transaction.recipientName != null &&
                    item.transaction.recipientName!.isNotEmpty) {
                  recipientOutgoingCounts.update(
                    item.transaction.recipientName!,
                    (value) => value + item.transaction.quantity,
                    ifAbsent: () => item.transaction.quantity,
                  );
                }
              }
              final top3Recipients = recipientOutgoingCounts.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Top 5 Barang Keluar Terbanyak'),
                    const SizedBox(height: 16),
                    if (top5Products.isEmpty)
                      const Center(child: Text('Belum ada data barang keluar.'))
                    else
                      _buildBarChart(top5Products.take(5).toList()),
                    const SizedBox(height: 32),
                    _buildSectionTitle('Top 3 Customer'),
                    const SizedBox(height: 16),
                    if (top3Recipients.isEmpty)
                      const Center(child: Text('Belum ada data customer.'))
                    else
                      _buildBarChart(top3Recipients.take(3).toList()),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.orange,
      ),
    );
  }

  Widget _buildBarChart(List<MapEntry<String, int>> data) {
    if (data.isEmpty) {
      return const SizedBox.shrink();
    }

    final int maxQuantity = data
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: data.map((entry) {
        final double barWidth =
            (entry.value / maxQuantity) * 200; // Lebar maksimal bar 200
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: barWidth,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value} Roll',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _AnalyticsBackground extends StatelessWidget {
  const _AnalyticsBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.shade50,
            Colors.white,
            Colors.orange.shade50.withValues(alpha: 0.3),
          ],
        ),
      ),
      child: CustomPaint(painter: _AnalyticsPainter(), size: Size.infinite),
    );
  }
}

class _AnalyticsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.blue.shade200.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Menggambar Grid Garis Halus
    const double step = 30;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    // Menggambar elemen grafis abstrak (nodes) bernuansa data
    final nodePaint = Paint()
      ..color = Colors.orange.shade300.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(
      Offset(size.width * 0.1, size.height * 0.2),
      60,
      nodePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.9, size.height * 0.6),
      100,
      nodePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.4, size.height * 0.8),
      40,
      nodePaint,
    );

    // Garis data abstrak/trend di background
    final linePaint = Paint()
      ..color = Colors.blue.shade400.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width * 0.3,
      size.height * 0.65,
      size.width * 0.5,
      size.height * 0.75,
    );
    path.quadraticBezierTo(
      size.width * 0.8,
      size.height * 0.85,
      size.width,
      size.height * 0.7,
    );
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
