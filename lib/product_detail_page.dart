import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'inventory_provider.dart';
import 'product.dart';
import 'transaction.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    return Scaffold(
      // Remove floatingActionButton and floatingActionButtonLocation
      // floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      // floatingActionButton: GestureDetector(
      //   onLongPress: () => _showDeleteConfirmation(context),
      //   child: FloatingActionButton(
      //     onPressed: () {
      //       // Memberi tahu user bahwa harus ditekan lama
      //       ScaffoldMessenger.of(context).showSnackBar(
      //         const SnackBar(
      //           content: Text('Tekan dan tahan untuk menghapus produk'),
      //           duration: Duration(seconds: 1),
      //         ),
      //       );
      //     },
      //     backgroundColor: Colors.red.shade700,
      //     foregroundColor: Colors.white,
      //     tooltip: 'Hapus Produk (Tahan)',
      //     child: const Icon(Icons.delete_forever),
      //   ),
      // ),
      appBar: AppBar(
        title: const Text('Detail Produk'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.arrow_downward), text: 'Barang Masuk'),
            Tab(icon: Icon(Icons.arrow_upward), text: 'Barang Keluar'),
            Tab(icon: Icon(Icons.history), text: 'Riwayat'),
          ],
        ),
      ),
      body: Consumer<InventoryProvider>(
        builder: (context, provider, _) {
          final product = provider.getProductById(widget.productId);

          if (product == null) {
            return const Center(child: Text('Produk tidak ditemukan'));
          }

          return Column(
            children: [
              // Product Info Header
              Container(
                color: Colors.orange.shade50,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Stok Saat Ini:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              '${product.stock} Roll',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: product.stock <= 30
                                    ? Colors.red
                                    : Colors.green,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lokasi:',
                              style: TextStyle(fontSize: 12),
                            ),
                            Text(
                              product.location,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Tab Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildIncomingTab(context, provider, product),
                    _buildOutgoingTab(context, provider, product),
                    _buildHistoryTab(product),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDeleteButton(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: GestureDetector(
          onLongPress: () => _showDeleteConfirmation(context),
          child: TextButton.icon(
            icon: Icon(
              Icons.delete_outline,
              color: Colors.red.shade700,
              size: 20,
            ),
            label: Text(
              'Hapus Produk',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tekan dan tahan untuk menghapus produk'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: const Text(
          'Apakah anda yakin ingin menghapus produk ini?\n\nSemua riwayat transaksi akan ikut terhapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          // Tombol Ya dengan Long Press
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: GestureDetector(
              onLongPress: () async {
                Navigator.pop(context); // Tutup Dialog
                try {
                  await context.read<InventoryProvider>().deleteProduct(
                    widget.productId,
                  );

                  if (mounted) {
                    _showSuccessSnackBar(context, 'Produk berhasil dihapus');
                    Navigator.pop(context); // Kembali ke InventoryPage
                  }
                } catch (e) {
                  _showErrorSnackBar(context, 'Gagal menghapus produk: $e');
                }
              },
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  // Feedback jika hanya ditekan biasa
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Tahan tombol "Ya" selama 2 detik untuk mengonfirmasi',
                      ),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: const Text('Ya (Tahan)'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingTab(
    BuildContext context,
    InventoryProvider provider,
    Product product,
  ) {
    final docNumberController = TextEditingController();
    final quantityController = TextEditingController();
    final notesController = TextEditingController();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📥 Barang Masuk',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: docNumberController,
            decoration: InputDecoration(
              labelText: 'Nomor Surat Jalan',
              hintText: 'Contoh: DO/0001/SHM/VI/2026',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.description),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quantityController,
            decoration: InputDecoration(
              labelText: 'Jumlah (Roll)',
              hintText: 'Contoh: 10',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesController,
            decoration: InputDecoration(
              labelText: 'Catatan (opsional)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.note),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('Simpan & Update Stok'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                try {
                  final docNumber = docNumberController.text.trim();
                  final quantity = int.tryParse(quantityController.text);
                  final notes = notesController.text.trim();

                  if (docNumber.isEmpty) {
                    _showErrorSnackBar(
                      context,
                      'Nomor surat jalan tidak boleh kosong',
                    );
                    return;
                  }

                  if (quantity == null || quantity <= 0) {
                    _showErrorSnackBar(
                      context,
                      'Jumlah harus lebih besar dari 0',
                    );
                    return;
                  }

                  await provider.addIncoming(
                    productId: widget.productId,
                    quantity: quantity,
                    documentNumber: docNumber,
                    notes: notes.isNotEmpty ? notes : null,
                  );

                  if (context.mounted) {
                    docNumberController.clear();
                    quantityController.clear();
                    notesController.clear();
                    _showSuccessSnackBar(
                      context,
                      '$quantity unit berhasil masuk dari $docNumber',
                    );
                  }
                } catch (e) {
                  _showErrorSnackBar(context, e.toString());
                }
              },
            ),
          ),
          _buildDeleteButton(context),
        ],
      ),
    );
  }

  Widget _buildOutgoingTab(
    BuildContext context,
    InventoryProvider provider,
    Product product,
  ) {
    final docNumberController = TextEditingController();
    final quantityController = TextEditingController();
    final notesController = TextEditingController();
    final expeditionController = TextEditingController();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '📤 Barang Keluar',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.info, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Stok tersedia: ${product.stock} Roll',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: docNumberController,
            decoration: InputDecoration(
              labelText: 'Nomor Resi / Invoice',
              hintText: 'Contoh: INV-2026-001',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.receipt),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => _openScanner(context, docNumberController),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Autocomplete<String>(
            optionsBuilder: (textValue) {
              if (textValue.text.isEmpty) return _expeditions;
              return _expeditions.where(
                (opt) =>
                    opt.toLowerCase().contains(textValue.text.toLowerCase()),
              );
            },
            onSelected: (val) => expeditionController.text = val,
            fieldViewBuilder: (ctx, ctrl, focus, onComplete) {
              if (expeditionController.text != ctrl.text) {
                ctrl.text = expeditionController.text;
              }
              ctrl.addListener(() => expeditionController.text = ctrl.text);
              return TextField(
                controller: ctrl,
                focusNode: focus,
                decoration: const InputDecoration(
                  labelText: 'Jasa Ekspedisi',
                  hintText: 'Pilih atau ketik manual',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_shipping),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: quantityController,
            decoration: InputDecoration(
              labelText: 'Jumlah (Roll)',
              hintText: 'Contoh: 5',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.numbers),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesController,
            decoration: InputDecoration(
              labelText: 'Catatan (opsional)',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.note),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle),
              label: const Text('Simpan & Update Stok'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () async {
                try {
                  final docNumber = docNumberController.text.trim();
                  final quantity = int.tryParse(quantityController.text);
                  final notes = notesController.text.trim();
                  final expedition = expeditionController.text.trim();

                  if (docNumber.isEmpty) {
                    _showErrorSnackBar(
                      context,
                      'Nomor invoice/resi tidak boleh kosong',
                    );
                    return;
                  }

                  if (quantity == null || quantity <= 0) {
                    _showErrorSnackBar(
                      context,
                      'Jumlah harus lebih besar dari 0',
                    );
                    return;
                  }

                  await provider.addOutgoing(
                    productId: widget.productId,
                    quantity: quantity,
                    documentNumber: docNumber,
                    expedition: expedition.isNotEmpty ? expedition : null,
                    notes: notes.isNotEmpty ? notes : null,
                  );

                  if (context.mounted) {
                    docNumberController.clear();
                    quantityController.clear();
                    notesController.clear();
                    _showSuccessSnackBar(
                      context,
                      '$quantity unit berhasil keluar untuk $docNumber',
                    );
                  }
                } catch (e) {
                  _showErrorSnackBar(context, e.toString());
                }
              },
            ),
          ),
          _buildDeleteButton(context),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(Product product) {
    if (product.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Belum ada transaksi',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    final history = product.history.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: history.length,
      itemBuilder: (context, index) {
        final transaction = history[index];
        final isIncoming = transaction.isIncoming;

        return GestureDetector(
          onLongPress: () => _showEditTransactionDialog(context, transaction),
          onTap: () => _showTransactionDetails(context, transaction),
          child: Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isIncoming
                    ? Colors.green.shade600
                    : Colors.red.shade600,
                foregroundColor: Colors.white,
                child: Icon(
                  isIncoming ? Icons.arrow_downward : Icons.arrow_upward,
                ),
              ),
              title: Text(
                isIncoming ? 'Barang Masuk' : 'Barang Keluar',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Doc: ${transaction.documentNumber}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  Text(
                    DateFormat(
                      'dd MMM yyyy, HH:mm',
                    ).format(transaction.timestamp),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${transaction.quantity} Roll',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isIncoming ? Colors.green : Colors.red,
                    ),
                  ),
                  Text(
                    '${transaction.previousStock} → ${transaction.newStock}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTransactionDetails(BuildContext context, Transaction transaction) {
    final isIncoming = transaction.isIncoming;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isIncoming ? '📥 Detail Barang Masuk' : '📤 Detail Barang Keluar',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('Tipe:', isIncoming ? 'Masuk' : 'Keluar'),
            _buildDetailRow('Jumlah:', '${transaction.quantity} Roll'),
            _buildDetailRow('Nomor Dokumen:', transaction.documentNumber),
            if (transaction.expedition != null)
              _buildDetailRow('Ekspedisi:', transaction.expedition!),
            _buildDetailRow(
              'Tanggal/Jam:',
              DateFormat('dd MMM yyyy, HH:mm').format(transaction.timestamp),
            ),
            _buildDetailRow(
              'Stok Sebelum:',
              '${transaction.previousStock} Roll',
            ),
            _buildDetailRow('Stok Sesudah:', '${transaction.newStock} Roll'),
            if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Catatan:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(transaction.notes!),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
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
                  productId: widget.productId,
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
              icon: Icon(
                Icons.delete_outline,
                color: Colors.red.shade700,
                size: 20,
              ),
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
                            productId: widget.productId,
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

  Widget _buildDetailRow(String label, String value) {
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
    AudioPlayer().play(AssetSource('sounds/success.mp3'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(BuildContext context, String message) {
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
