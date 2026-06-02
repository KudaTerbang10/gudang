import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'inventory_provider.dart';
import 'product.dart';
import 'product_detail_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'sounds.dart';
import 'activity_history_page.dart';

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ASP Gudang'),
        actions: [
          Consumer<InventoryProvider>(
            builder: (context, provider, _) =>
                _buildConnectionIndicator(context, provider),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ActivityHistoryPage(),
                ),
              );
            },
            tooltip: 'Riwayat Aktivitas',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _showBulkTransactionDialog(context, 'incoming'),
            tooltip: 'Barang Masuk (Massal)',
          ),
          IconButton(
            icon: const Icon(Icons.upload),
            onPressed: () => _showBulkTransactionDialog(context, 'outgoing'),
            tooltip: 'Barang Keluar (Massal)',
          ),
          Consumer<InventoryProvider>(
            builder: (context, provider, _) => IconButton(
              icon: Icon(
                provider.isTableView ? Icons.grid_view : Icons.table_chart,
              ),
              onPressed: () => provider.toggleView(),
              tooltip: 'Switch View',
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          const _StaticGraphicBackground(),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.9),
                    labelText: 'Cari Produk',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              context.read<InventoryProvider>().searchProduct(
                                '',
                              );
                              setState(() {});
                            },
                          )
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    context.read<InventoryProvider>().searchProduct(value);
                    setState(() {});
                  },
                ),
              ),
              Expanded(
                child: Consumer<InventoryProvider>(
                  builder: (context, provider, _) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.2, 0),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                    child: provider.allProducts.isEmpty
                        ? _buildEmptyState(context)
                        : (provider.isTableView
                              ? _buildTableView(context, provider)
                              : _buildCardView(provider.products)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 48,
        height: 48,
        child: FloatingActionButton(
          onPressed: () => _showAddProductDialog(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildTableView(BuildContext context, InventoryProvider provider) {
    final products = provider.products;
    final screenWidth = MediaQuery.of(context).size.width;

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: DataTable(
        sortColumnIndex: provider.sortColumnIndex,
        sortAscending: provider.isSortAscending,
        headingRowColor: WidgetStateProperty.all(Colors.orange.shade800),
        headingTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        columnSpacing: 20,
        horizontalMargin: 12,
        columns: [
          const DataColumn(label: Text('Nama Produk')),
          DataColumn(
            label: const Text('Stok', style: TextStyle(color: Colors.white)),
            numeric: true,
            onSort: (columnIndex, ascending) {
              context.read<InventoryProvider>().sortProductsByStock(
                columnIndex,
                ascending,
              );
            },
          ),
          const DataColumn(label: Text('Lokasi')),
        ],
        rows: products.asMap().entries.map((entry) {
          final index = entry.key;
          final p = entry.value;
          return DataRow(
            color: WidgetStateProperty.resolveWith<Color?>((states) {
              return index.isEven
                  ? Colors.orange.withValues(alpha: 0.05)
                  : Colors.white;
            }),
            cells: [
              DataCell(
                SizedBox(
                  width: screenWidth * 0.45,
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
              DataCell(
                Text(
                  p.stock.toString(),
                  style: TextStyle(
                    color: p.stock <= 20 ? Colors.red : Colors.black,
                    fontWeight: p.stock <= 20
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),
              DataCell(Text(p.location)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCardView(List<Product> products) {
    return ListView.builder(
      key: const ValueKey('CardView'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProductDetailPage(productId: p.id),
              ),
            );
          },
          onLongPress: () => _showEditProductDialog(context, p),
          child: Card(
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: CircleAvatar(child: Text(p.location)),
              title: Text(
                p.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Lokasi: ${p.location}'),
              trailing: Text(
                '${p.stock} Roll',
                style: TextStyle(
                  color: p.stock <= 20 ? Colors.red : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showEditProductDialog(BuildContext context, Product product) {
    final nameController = TextEditingController(text: product.name);
    final stockController = TextEditingController(
      text: product.stock.toString(),
    );
    final locController = TextEditingController(text: product.location);
    bool allowStockEdit = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Informasi Produk'),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nama Produk'),
                ),
                TextField(
                  controller: locController,
                  decoration: const InputDecoration(labelText: 'Lokasi'),
                ),
                const SizedBox(height: 16),
                const Divider(),
                SwitchListTile(
                  title: const Text(
                    'Buka Kunci Stok',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Aktifkan hanya untuk koreksi stok manual',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: allowStockEdit,
                  onChanged: (val) => setState(() => allowStockEdit = val),
                ),
                TextField(
                  controller: stockController,
                  decoration: InputDecoration(
                    labelText: 'Stok (Roll)',
                    filled: !allowStockEdit,
                    fillColor: allowStockEdit ? null : Colors.grey.shade100,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: allowStockEdit,
                ),
              ],
            ),
          ),
          actions: [
            GestureDetector(
              onLongPress: () async {
                await context.read<InventoryProvider>().deleteProduct(
                  product.id,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  _showSuccessSnackBar(context, 'Produk berhasil dihapus');
                }
              },
              child: IconButton(
                icon: Icon(Icons.delete_forever, color: Colors.red.shade700),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Tahan ikon sampah untuk menghapus produk'),
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
                  onPressed: () {
                    context.read<InventoryProvider>().updateProduct(
                      id: product.id,
                      name: nameController.text,
                      stock:
                          int.tryParse(stockController.text) ?? product.stock,
                      location: locController.text,
                    );
                    Navigator.pop(context);
                  },
                  child: const Text('Simpan'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showBulkTransactionDialog(BuildContext context, String type) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _BulkTransactionDialog(type: type),
    );
  }

  void _showAddProductDialog(BuildContext context) {
    final nameController = TextEditingController();
    final stockController = TextEditingController();
    final locController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambah Produk Baru'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nama Produk'),
            ),
            TextField(
              controller: stockController,
              decoration: const InputDecoration(labelText: 'Stok'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: locController,
              decoration: const InputDecoration(
                labelText: 'Lokasi (Contoh: A1)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                context.read<InventoryProvider>().addProduct(
                  nameController.text,
                  int.tryParse(stockController.text) ?? 0,
                  locController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  static void _showSuccessSnackBar(BuildContext context, String message) {
    AppAudio().playSuccess();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    AppAudio().playError();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildConnectionIndicator(
    BuildContext context,
    InventoryProvider provider,
  ) {
    Color color;
    String text;
    IconData icon;

    if (provider.isConnecting) {
      color = Colors.blue;
      text = 'Menghubungkan ke Atlas...';
      icon = Icons.sync;
    } else if (provider.isSyncing) {
      color = Colors.blue;
      text = 'Menyingkronkan data...';
      icon = Icons.sync;
    } else if (provider.isConnected) {
      color = Colors.green;
      text = 'Terhubung ke Atlas (Last: ${provider.lastSyncTime ?? '-'})';
      icon = Icons.cloud_done;
    } else {
      color = Colors.orange;
      text = 'Offline (Menggunakan data lokal)';
      icon = Icons.cloud_off;
    }

    return Tooltip(
      message: text,
      child: InkWell(
        onTap: () {
          provider.syncWithAtlas();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (provider.isSyncing || provider.isConnecting)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color == Colors.green
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (color == Colors.green
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent)
                                .withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 6),
              Icon(icon, size: 16, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 80,
              color: Colors.orange.shade200,
            ),
            const SizedBox(height: 16),
            const Text(
              'Belum Ada Produk',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Database Anda kosong. Silakan tambahkan produk secara manual menggunakan tombol + di bawah.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaticGraphicBackground extends StatelessWidget {
  const _StaticGraphicBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade50, Colors.white, Colors.blue.shade100],
        ),
      ),
      child: CustomPaint(painter: _GraphicPainter(), size: Size.infinite),
    );
  }
}

class _GraphicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final lightBluePaint = Paint()
      ..color = Colors.blue.shade200.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final darkBluePaint = Paint()
      ..color = Colors.blue.shade700.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final sunPaint = Paint()
      ..color = Colors.orange.shade300.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    // Menggambar Matahari di pojok kanan atas
    canvas.drawCircle(
      Offset(size.width * 0.85, size.height * 0.12),
      55,
      sunPaint,
    );

    // Menggambar Gelombang Biru Muda (Wave 1)
    final Path wave1 = Path();
    wave1.moveTo(0, size.height * 0.82);
    wave1.quadraticBezierTo(
      size.width * 0.25,
      size.height * 0.75,
      size.width * 0.5,
      size.height * 0.82,
    );
    wave1.quadraticBezierTo(
      size.width * 0.75,
      size.height * 0.88,
      size.width,
      size.height * 0.82,
    );
    wave1.lineTo(size.width, size.height);
    wave1.lineTo(0, size.height);
    wave1.close();
    canvas.drawPath(wave1, lightBluePaint);

    // Menggambar Gelombang Biru Tua (Wave 2)
    final Path wave2 = Path();
    wave2.moveTo(0, size.height * 0.87);
    wave2.quadraticBezierTo(
      size.width * 0.35,
      size.height * 0.93,
      size.width * 0.6,
      size.height * 0.84,
    );
    wave2.quadraticBezierTo(
      size.width * 0.85,
      size.height * 0.76,
      size.width,
      size.height * 0.87,
    );
    wave2.lineTo(size.width, size.height);
    wave2.lineTo(0, size.height);
    wave2.close();
    canvas.drawPath(wave2, darkBluePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BulkTransactionDialog extends StatefulWidget {
  final String type;
  const _BulkTransactionDialog({required this.type});

  @override
  State<_BulkTransactionDialog> createState() => _BulkTransactionDialogState();
}

class _BulkTransactionItem {
  Product? product;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController productSearchController = TextEditingController();
}

class _BulkTransactionDialogState extends State<_BulkTransactionDialog> {
  final _docController = TextEditingController();
  final _expeditionController = TextEditingController();
  final _notesController = TextEditingController();
  final _recipientController = TextEditingController();
  final List<_BulkTransactionItem> _items = [_BulkTransactionItem()];

  final List<String> _expeditions = [
    'Instant Gosend',
    'Instant Grab',
    'Instant SPX',
    'Same Day Gosend',
    'Same Day Grab',
    'Same Day SPX',
    'SPX Standard',
    'SiCepat',
    'JNE',
    'J&T Express',
    'J&T Cargo',
    'ID Express',
    'Paxel',
    'PosAja',
    'Ninja Express',
    'Lion Parcel',
    'AnterAja',
    'Wahana Express',
    'Baraka Express',
    'Hira Express',
    'APM',
    'Redex',
  ];

  void _openScanner(TextEditingController controller) {
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
                Navigator.pop(context);
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final isIncoming = widget.type == 'incoming';

    return AlertDialog(
      title: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          isIncoming ? '📥 Barang Masuk (Bulk)' : '📤 Barang Keluar (Bulk)',
          maxLines: 1,
          softWrap: false,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _docController,
                decoration: InputDecoration(
                  labelText: isIncoming
                      ? 'Nomor Surat Jalan'
                      : 'Nomor Resi / Invoice',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.assignment),
                  suffixIcon: !isIncoming
                      ? IconButton(
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () => _openScanner(_docController),
                        )
                      : null,
                ),
              ),
              if (!isIncoming) ...[
                const SizedBox(height: 12),
                Autocomplete<String>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) return _expeditions;
                    return _expeditions.where(
                      (option) => option.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      ),
                    );
                  },
                  onSelected: (selection) =>
                      _expeditionController.text = selection,
                  fieldViewBuilder: (ctx, ctrl, focus, onComplete) {
                    if (_expeditionController.text != ctrl.text) {
                      ctrl.text = _expeditionController.text;
                    }
                    return TextField(
                      controller: ctrl,
                      focusNode: focus,
                      onChanged: (val) => _expeditionController.text = val,
                      decoration: const InputDecoration(
                        labelText: 'Jasa Ekspedisi',
                        hintText: 'Pilih atau ketik manual',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_shipping),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              if (!isIncoming) ...[
                TextField(
                  controller: _recipientController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Penerima (Opsional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Catatan Dokumen (Opsional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const Divider(height: 32),
              const Text(
                'Daftar Barang',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._items.asMap().entries.map((entry) {
                int index = entry.key;
                _BulkTransactionItem item = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Autocomplete<Product>(
                          displayStringForOption: (p) => p.name,
                          optionsBuilder: (textValue) {
                            if (textValue.text.isEmpty) {
                              return const Iterable.empty();
                            }
                            return provider.allProducts.where(
                              (p) => p.name.toLowerCase().contains(
                                textValue.text.toLowerCase(),
                              ),
                            );
                          },
                          onSelected: (p) => setState(() => item.product = p),
                          fieldViewBuilder: (ctx, ctrl, focus, onComplete) {
                            return TextField(
                              controller: ctrl,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText: 'Cari Produk...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: item.qtyController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Qty',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => setState(() => _items.removeAt(index)),
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _items.add(_BulkTransactionItem())),
                icon: const Icon(Icons.add),
                label: const Text('Tambah Baris Barang'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isIncoming
                ? Colors.green.shade700
                : Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            final doc = _docController.text.trim();
            if (doc.isEmpty) {
              _error('Nomor dokumen wajib diisi');
              return;
            }
            if (_items.isEmpty) {
              _error('Minimal harus ada 1 barang');
              return;
            }

            try {
              final List<Map<String, dynamic>> bulkItems = [];
              for (var item in _items) {
                if (item.product == null) throw 'Ada barang yang belum dipilih';
                int? qty = int.tryParse(item.qtyController.text);
                if (qty == null || qty <= 0) {
                  throw 'Qty untuk ${item.product!.name} tidak valid';
                }
                bulkItems.add({'productId': item.product!.id, 'quantity': qty});
              }

              await provider.addBulkTransactions(
                type: widget.type,
                documentNumber: doc,
                items: bulkItems,
                recipientName: _recipientController.text.trim().isNotEmpty
                    ? _recipientController.text.trim()
                    : null,
                expedition: _expeditionController.text.trim().isNotEmpty
                    ? _expeditionController.text.trim()
                    : null,
                notes: _notesController.text.trim().isNotEmpty
                    ? _notesController.text.trim()
                    : null,
              );

              if (mounted) {
                Navigator.pop(context);
                AppAudio().playSuccess();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Transaksi Berhasil Disimpan'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            } catch (e) {
              _error(e.toString());
            }
          },
          child: const Text('Simpan Transaksi'),
        ),
      ],
    );
  }

  void _error(String msg) {
    AppAudio().playError();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }
}
