import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'inventory_provider.dart';
import 'product.dart';
import 'product_detail_page.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';

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
        title: const Text('Gudang - Aneka Sarana Prima'),
        actions: [
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
                    child: provider.isTableView
                        ? _buildTableView(context, provider)
                        : _buildCardView(provider.products),
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
    AudioPlayer().play(AssetSource('sounds/success.mp3'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  static void _showErrorSnackBar(BuildContext context, String message) {
    AudioPlayer().play(AssetSource('sounds/error.mp3'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        duration: const Duration(seconds: 3),
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
    'Wahana',
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
                AudioPlayer().play(AssetSource('sounds/scan.mp3'));
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
      title: Text(
        isIncoming ? '📥 Barang Masuk (Bulk)' : '📤 Barang Keluar (Bulk)',
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
                      ? 'No. Surat Jalan'
                      : 'No. Surat Jalan / Resi',
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
                        flex: 3,
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
                        flex: 1,
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
              for (var item in _items) {
                if (item.product == null) throw 'Ada barang yang belum dipilih';
                int? qty = int.tryParse(item.qtyController.text);
                if (qty == null || qty <= 0) {
                  throw 'Qty untuk ${item.product!.name} tidak valid';
                }

                if (isIncoming) {
                  await provider.addIncoming(
                    productId: item.product!.id,
                    quantity: qty,
                    documentNumber: doc,
                  );
                } else {
                  await provider.addOutgoing(
                    productId: item.product!.id,
                    quantity: qty,
                    documentNumber: doc,
                    expedition: _expeditionController.text.trim(),
                  );
                }
              }
              if (mounted) {
                Navigator.pop(context);
                AudioPlayer().play(AssetSource('sounds/success.mp3'));
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
    AudioPlayer().play(AssetSource('sounds/error.mp3'));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }
}
