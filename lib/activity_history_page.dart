import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'inventory_provider.dart';
import 'transaction.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'sounds.dart';
import 'analytics_page.dart';
import 'package:path_provider/path_provider.dart';

class ActivityHistoryPage extends StatefulWidget {
  const ActivityHistoryPage({super.key});

  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

enum HistoryFilter { today, thisWeek, thisMonth, customRange, all }

class _ActivityHistoryPageState extends State<ActivityHistoryPage> {
  HistoryFilter _selectedFilter = HistoryFilter.all;
  DateTimeRange? _customRange;
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _applyFilter(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (_selectedFilter) {
      case HistoryFilter.today:
        return timestamp.isAfter(today);
      case HistoryFilter.thisWeek:
        final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
        return timestamp.isAfter(startOfWeek);
      case HistoryFilter.thisMonth:
        final startOfMonth = DateTime(now.year, now.month, 1);
        return timestamp.isAfter(startOfMonth);
      case HistoryFilter.customRange:
        if (_customRange == null) return true;
        return timestamp.isAfter(_customRange!.start) &&
            timestamp.isBefore(_customRange!.end.add(const Duration(days: 1)));
      case HistoryFilter.all:
      default:
        return true;
    }
  }

  bool _applySearch(TransactionWithProduct item) {
    final query = _searchController.text.toLowerCase();
    if (query.isEmpty) return true;

    return item.transaction.documentNumber.toLowerCase().contains(query) ||
        (item.transaction.recipientName?.toLowerCase().contains(query) ??
            false);
  }

  void _openScanner(BuildContext context, TextEditingController controller) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: MobileScanner(
          onDetect: (capture) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              final String? code = barcodes.first.rawValue;
              if (code != null) {
                AppAudio().playScan();
                controller.text = code;
                setState(() {});
                Navigator.pop(context);
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _selectedFilter = HistoryFilter.customRange;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final filteredHistory = provider.allTransactionsWithProduct
        .where((item) => _applySearch(item))
        .where((item) => _applyFilter(item.transaction.timestamp))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Aktivitas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AnalyticsPage()),
              );
            },
            tooltip: 'Analitik',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari No. Dokumen / Penerima...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: () => _openScanner(context, _searchController),
                    ),
                  ],
                ),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (value) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 300),
                  () => setState(() {}),
                );
              },
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const _WaveBackground(),
          Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _filterChip(HistoryFilter.all, 'Semua'),
                _filterChip(HistoryFilter.today, 'Hari Ini'),
                _filterChip(HistoryFilter.thisWeek, 'Minggu Ini'),
                _filterChip(HistoryFilter.thisMonth, 'Bulan Ini'),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: ActionChip(
                    avatar: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      _customRange == null
                          ? 'Pilih Range'
                          : '${DateFormat('dd MMM yyyy').format(_customRange!.start)} - ${DateFormat('dd MMM yyyy').format(_customRange!.end)}',
                    ),
                    onPressed: () => _selectDateRange(context),
                    backgroundColor:
                        _selectedFilter == HistoryFilter.customRange
                        ? Colors.orange.shade100
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final history = filteredHistory;

                if (history.isEmpty) {
                  return const Center(
                    child: Text('Tidak ada riwayat ditemukan.'),
                  );
                }

                // Group by nomor dokumen
                final Map<String, List<TransactionWithProduct>> grouped = {};
                for (final item in history) {
                  final doc = item.transaction.documentNumber;
                  grouped.putIfAbsent(doc, () => []);
                  grouped[doc]!.add(item);
                }

                // Sort grup berdasarkan timestamp terbaru
                final sortedGroups = grouped.entries.toList()
                  ..sort((a, b) {
                    final aLatest = a.value
                        .map((e) => e.transaction.timestamp)
                        .reduce((a, b) => a.isAfter(b) ? a : b);
                    final bLatest = b.value
                        .map((e) => e.transaction.timestamp)
                        .reduce((a, b) => a.isAfter(b) ? a : b);
                    return bLatest.compareTo(aLatest);
                  });

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: sortedGroups.length,
                  itemBuilder: (context, index) {
                    final group = sortedGroups[index];
                    final docNumber = group.key;
                    final items = group.value;
                    final isAllIncoming =
                        items.every((e) => e.transaction.isIncoming);

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 4,
                      ),
                      elevation: 2,
                      child: ExpansionTile(
                        initiallyExpanded: items.length == 1,
                        leading: CircleAvatar(
                          backgroundColor: isAllIncoming
                              ? Colors.green.shade600
                              : Colors.red.shade600,
                          foregroundColor: Colors.white,
                          child: Icon(
                            isAllIncoming
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                          ),
                        ),
                        title: Text(
                          docNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${items.length} item · ${DateFormat('dd MMM yyyy, HH:mm').format(items.first.transaction.timestamp)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        children: items.map((item) {
                          final tx = item.transaction;
                          final prod = item.product;
                          return ListTile(
                            onTap: () => _showTransactionDetails(
                                context, tx, prod.name),
                            onLongPress: () =>
                                _showEditTransactionDialog(
                                    context, tx, prod.id),
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: tx.isIncoming
                                  ? Colors.green.shade100
                                  : Colors.red.shade100,
                              child: Text(
                                (items.indexOf(item) + 1).toString(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: tx.isIncoming
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                            ),
                            title: Text(
                              prod.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              'Stok: ${tx.previousStock} → ${tx.newStock}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            trailing: Text(
                              '${tx.isIncoming ? "+" : "-"}${tx.quantity} Roll',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: tx.isIncoming
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ],
  ),
);
}

Widget _filterChip(HistoryFilter filter, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedFilter == filter,
        onSelected: (bool selected) {
          if (selected) {
            setState(() {
              _selectedFilter = filter;
              if (filter != HistoryFilter.customRange) _customRange = null;
            });
          }
        },
      ),
    );
  }

  void _showTransactionDetails(
    BuildContext context,
    Transaction transaction,
    String productName,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            transaction.isIncoming
                ? '📥 Detail Barang Masuk'
                : '📤 Detail Barang Keluar',
            maxLines: 1,
            softWrap: false,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Produk:', productName),
              _detailRow('Tipe:', transaction.isIncoming ? 'Masuk' : 'Keluar'),
              _detailRow('Jumlah:', '${transaction.quantity} Roll'),
              _detailRow('No. Dokumen:', transaction.documentNumber),
              if (transaction.recipientName != null)
                _detailRow('Penerima:', transaction.recipientName!),
              if (transaction.expedition != null)
                _detailRow('Ekspedisi:', transaction.expedition!),
              _detailRow(
                'Waktu:', // Menggunakan format lengkap untuk detail
                DateFormat('dd MMM yyyy, HH:mm').format(transaction.timestamp),
              ),
              _detailRow(
                'Stok:',
                '${transaction.previousStock} → ${transaction.newStock}',
              ),
              if (transaction.notes != null &&
                  transaction.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Catatan:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(transaction.notes!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _showEditTransactionDialog(
    BuildContext context,
    Transaction transaction,
    String productId,
  ) {
    final controller = TextEditingController(
      text: transaction.quantity.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Jumlah Transaksi'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Jumlah Baru',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          GestureDetector(
            onLongPress: () async {
              try {
                await context.read<InventoryProvider>().deleteTransaction(
                  productId: productId,
                  transactionId: transaction.id,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  _showSuccessSnackBar(context, 'Transaksi berhasil dihapus');
                }
              } catch (e) {
                _showErrorSnackBar(context, e.toString());
              }
            },
            child: IconButton(
              icon: Icon(Icons.delete_outline, color: Colors.red.shade700),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Tahan ikon sampah untuk menghapus'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final qty = int.tryParse(controller.text);
                  if (qty != null && qty > 0) {
                    try {
                      await context
                          .read<InventoryProvider>()
                          .editTransactionQuantity(
                            productId: productId,
                            transactionId: transaction.id,
                            newQuantity: qty,
                          );
                      if (context.mounted) Navigator.pop(context);
                    } catch (e) {
                      _showErrorSnackBar(context, e.toString());
                    }
                  }
                },
                child: const Text('Simpan'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(BuildContext context, String message) {
    AppAudio().playSuccess();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    AppAudio().playError();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

class _WaveBackground extends StatelessWidget {
  const _WaveBackground();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F2FD),
              Color(0xFFBBDEFB),
              Color(0xFFE0F7FA),
              Color(0xFFF1F8E9),
            ],
            stops: [0.0, 0.35, 0.7, 1.0],
          ),
        ),
        child: CustomPaint(
          painter: _WavePainter(),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final wavePaint1 = Paint()
      ..color = const Color(0x3381D4FA)
      ..style = PaintingStyle.fill;
    final wavePaint2 = Paint()
      ..color = const Color(0x267CB342)
      ..style = PaintingStyle.fill;
    final wavePaint3 = Paint()
      ..color = const Color(0x1A4DD0E1)
      ..style = PaintingStyle.fill;

    void drawWave(Paint paint, double offsetY, double amplitude,
        double frequency, double phase) {
      final path = Path();
      path.moveTo(0, size.height * offsetY);
      for (double x = 0; x <= size.width; x++) {
        path.lineTo(
          x,
          size.height * offsetY +
              math.sin((x * frequency * math.pi / 180) + phase) * amplitude,
        );
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, paint);
    }

    drawWave(wavePaint1, 0.85, 18, 0.6, 0);
    drawWave(wavePaint2, 0.88, 14, 0.8, math.pi / 3);
    drawWave(wavePaint3, 0.92, 10, 0.5, math.pi / 4);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
