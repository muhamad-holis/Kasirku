import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:excel/excel.dart' hide Border;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/responsive.dart';
import '../../providers/products_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/database/app_database.dart';

class StokScreen extends ConsumerStatefulWidget {
  const StokScreen({super.key});

  @override
  ConsumerState<StokScreen> createState() => _StokScreenState();
}

class _StokScreenState extends ConsumerState<StokScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() {
      if (_tab.indexIsChanging || _tab.index != _currentTab) {
        setState(() => _currentTab = _tab.index);
      }
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Stok',
          style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import Excel',
            onPressed: () => _importExcel(context, ref),
          ),
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export Excel',
            onPressed: () => _exportExcel(context, ref),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Semua'),
            Tab(text: 'Hampir'),
            Tab(text: 'Habis'),
            Tab(text: 'Kategori'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _ProductListTab(),
          _LowStockTab(),
          _OutStockTab(),
          _CategoryTab(),
        ],
      ),
      floatingActionButton: _currentTab == 3
          ? null
          // BUG #2 FIX: FAB Tambah Produk hanya tampil untuk Admin.
          // Kasir bisa lihat stok tapi tidak bisa tambah/edit/hapus produk.
          : ref.watch(isAdminProvider)
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddProduct(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah Produk'),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                )
              : null,
    );
  }

  // ─── Import Excel ──────────────────────────────────────────────────────────

  Future<void> _importExcel(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );
      if (result == null || result.files.single.path == null) return;

      final bytes = File(result.files.single.path!).readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables[excel.tables.keys.first];
      if (sheet == null) return;

      int imported = 0;
      final db = ref.read(databaseProvider);

      // Skip header row (row 0)
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.row(i);
        if (row.isEmpty) continue;

        final name = row[0]?.value?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        final barcode  = row[1]?.value?.toString().trim();
        final sku      = row[2]?.value?.toString().trim();
        final buyPrice = double.tryParse(row[3]?.value?.toString() ?? '') ?? 0;
        final sellPrice= double.tryParse(row[4]?.value?.toString() ?? '') ?? 0;
        final stock    = int.tryParse(row[5]?.value?.toString() ?? '')    ?? 0;
        final minStock = int.tryParse(row[6]?.value?.toString() ?? '')    ?? 5;
        final unit     = row[7]?.value?.toString().trim() ?? 'pcs';

        // Jika nama sama persis sudah ada → tambah stok (jangan insert baru)
        final existing = await db.productsDao.getProductByName(name);
        if (existing != null) {
          if (stock > 0) {
            final stockBefore = existing.stock;
            final stockAfter  = stockBefore + stock;
            await db.stockMovementsDao.adjustStock(
              db: db,
              productId: existing.id,
              newStock:  stockAfter,
              oldStock:  stockBefore,
              type: 'masuk',
              notes: 'Import CSV - penambahan stok',
            );
          }
          imported++;
          continue;
        }

        await db.productsDao.insertProduct(
          ProductsCompanion.insert(
            name: name,
            barcode: Value(barcode?.isEmpty ?? true ? null : barcode),
            sku:     Value(sku?.isEmpty ?? true ? null : sku),
            buyPrice:  Value(buyPrice),
            sellPrice: Value(sellPrice),
            stock:     Value(stock),
            minStock:  Value(minStock),
            unit:      Value(unit),
          ),
        );
        imported++;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$imported produk berhasil diimport'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal import: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  // ─── Export Excel ──────────────────────────────────────────────────────────

  Future<void> _exportExcel(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(databaseProvider);
      final products = await db.productsDao.getAllProducts();

      final excel = Excel.createExcel();
      final sheet = excel['Produk'];

      // Header
      final headers = [
        'Nama Produk', 'Barcode', 'SKU',
        'Harga Beli', 'Harga Jual', 'Stok',
        'Stok Min', 'Satuan',
      ];
      for (int i = 0; i < headers.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
        cell.value = TextCellValue(headers[i]);
        cell.cellStyle = CellStyle(bold: true);
      }

      // Data
      for (int i = 0; i < products.length; i++) {
        final p = products[i];
        final row = i + 1;
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row))
            .value = TextCellValue(p.name);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row))
            .value = TextCellValue(p.barcode ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row))
            .value = TextCellValue(p.sku ?? '');
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row))
            .value = DoubleCellValue(p.buyPrice);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row))
            .value = DoubleCellValue(p.sellPrice);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row))
            .value = IntCellValue(p.stock);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row))
            .value = IntCellValue(p.minStock);
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: row))
            .value = TextCellValue(p.unit);
      }

      // Delete default sheet
      excel.delete('Sheet1');

      final bytes = excel.encode();
      if (bytes == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now();
      final filename =
          'produk_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}.xlsx';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Data Produk KasirKu',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal export: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  void _showAddProduct(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const _AddProductSheet(),
      ),
    );
  }
}

// ─── Tab: Semua Produk ────────────────────────────────────────────────────────

class _ProductListTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredStokProvider);
    final categories = ref.watch(categoriesProvider);
    final selectedCat = ref.watch(selectedCategoryProvider);

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            onChanged: (v) =>
                ref.read(productSearchProvider.notifier).state = v,
            decoration: const InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),

        // Category filter chips
        categories.when(
          data: (cats) => cats.isEmpty
              ? const SizedBox()
              : SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: const Text('Semua'),
                          selected: selectedCat == null,
                          onSelected: (_) => ref
                              .read(selectedCategoryProvider.notifier)
                              .state = null,
                          selectedColor: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkPrimaryLight
                              : AppColors.primaryLight,
                          checkmarkColor: AppColors.primary,
                        ),
                      ),
                      ...cats.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(c.name),
                          selected: selectedCat == c.id,
                          onSelected: (_) => ref
                              .read(selectedCategoryProvider.notifier)
                              .state = selectedCat == c.id ? null : c.id,
                          selectedColor: Theme.of(context).brightness == Brightness.dark
                              ? AppColors.darkPrimaryLight
                              : AppColors.primaryLight,
                          checkmarkColor: AppColors.primary,
                        ),
                      )),
                    ],
                  ),
                ),
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),

        // Stats
        filtered.when(
          data: (list) => _StatsBar(products: list),
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),

        // Product list
        Expanded(
          child: filtered.when(
            data: (list) {
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined,
                        size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Belum ada produk',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                // FITUR TABLET: jumlah kolom menyesuaikan lebar layar
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.gridColumns(context),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.62,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => _ProductGridCard(product: list[i]),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}

// ─── Tab: Hampir Habis ────────────────────────────────────────────────────────

class _LowStockTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final low = ref.watch(lowStockProvider);
    return low.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                  size: 64, color: AppColors.success),
                const SizedBox(height: 12),
                const Text('Semua stok aman!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success)),
                const SizedBox(height: 6),
                Text('Tidak ada produk yang hampir habis',
                  style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_outlined,
                  color: AppColors.warning, size: 18),
                const SizedBox(width: 8),
                Text('${list.length} produk perlu restock',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.warning)),
              ]),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                // FITUR TABLET: jumlah kolom menyesuaikan lebar layar
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.gridColumns(context),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.62,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => _ProductGridCard(product: list[i]),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─── Tab: Stok Habis ─────────────────────────────────────────────────────────

class _OutStockTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final out = ref.watch(outStockProvider);
    return out.when(
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                  size: 64, color: AppColors.success),
                const SizedBox(height: 12),
                const Text('Tidak ada stok habis!',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.success)),
                const SizedBox(height: 6),
                Text('Semua produk masih tersedia',
                  style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.remove_circle_outline,
                  color: AppColors.danger, size: 18),
                const SizedBox(width: 8),
                Text('${list.length} produk stoknya habis',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger)),
              ]),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                // FITUR TABLET: jumlah kolom menyesuaikan lebar layar
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.gridColumns(context),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.62,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) => _ProductGridCard(product: list[i]),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─── Tab: Kategori (versi lengkap) ───────────────────────────────────────────

class _CategoryTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(categoriesProvider);
    final productsAsync = ref.watch(productsStreamProvider);

    return Stack(
      children: [
        catsAsync.when(
          data: (cats) {
            if (cats.isEmpty) {
              return _KategoriEmptyState(
                onAdd: () => _showAddSheet(context, ref),
              );
            }
            return productsAsync.when(
              data: (products) => ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: cats.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _CategoryCard(
                  category: cats[i],
                  productCount: products
                      .where((p) => p.categoryId == cats[i].id)
                      .length,
                ),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
        // FAB Tambah Kategori
        Positioned(
          bottom: 24,
          right: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_kategori',
            onPressed: () => _showAddSheet(context, ref),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Tambah Kategori'),
          ),
        ),
      ],
    );
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const _CategoryFormSheet(),
      ),
    );
  }
}

class _CategoryCard extends ConsumerWidget {
  final Category category;
  final int productCount;

  const _CategoryCard({
    required this.category,
    required this.productCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconData = _iconFromName(category.icon ?? category.name);
    final colorData = _colorFromName(category.name);
    // FIX DARK MODE: Card sebelumnya hardcode Colors.white sebagai background,
    // sementara teks judul mengikuti warna default tema (putih di dark mode)
    // → teks putih di atas card putih = tidak terlihat / kontras buruk.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : Colors.grey.shade200;
    final titleColor = isDark ? Colors.white : AppColors.textPrimary;
    final subtitleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade500;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2)),
              ],
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorData.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(iconData, color: colorData, size: 22),
        ),
        title: Text(category.name,
            style: TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: titleColor)),
        subtitle: Text(
          '$productCount produk',
          style: TextStyle(fontSize: 12, color: subtitleColor),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.edit_outlined,
                  size: 18, color: Colors.grey.shade600),
              onPressed: () => _showEditSheet(context, ref),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: AppColors.danger),
              onPressed: productCount > 0
                  ? () => _showCannotDelete(context)
                  : () => _confirmDelete(context, ref),
              tooltip: productCount > 0 ? 'Ada produk' : 'Hapus',
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFromName(String name) {
    final n = name.toLowerCase();
    if (n.contains('makanan') || n.contains('food')) return Icons.fastfood_outlined;
    if (n.contains('minum') || n.contains('drink') || n.contains('beverage')) return Icons.local_drink_outlined;
    if (n.contains('snack') || n.contains('camilan')) return Icons.cookie_outlined;
    if (n.contains('rokok') || n.contains('tembakau')) return Icons.smoking_rooms_outlined;
    if (n.contains('sembako') || n.contains('bahan pokok')) return Icons.shopping_basket_outlined;
    if (n.contains('bersih') || n.contains('sabun') || n.contains('deterjen')) return Icons.cleaning_services_outlined;
    if (n.contains('sehat') || n.contains('obat') || n.contains('vitamin')) return Icons.medical_services_outlined;
    if (n.contains('elektronik') || n.contains('gadget')) return Icons.devices_outlined;
    if (n.contains('pakaian') || n.contains('baju')) return Icons.checkroom_outlined;
    return Icons.category_outlined;
  }

  Color _colorFromName(String name) {
    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.info,
      AppColors.danger,
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
      const Color(0xFFFF5722),
    ];
    return colors[name.codeUnits.first % colors.length];
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _CategoryFormSheet(category: category),
      ),
    );
  }

  void _showCannotDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tidak Bisa Dihapus'),
        content: Text(
          'Kategori "${category.name}" masih memiliki $productCount produk. '
          'Pindahkan atau hapus semua produk terlebih dahulu.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Mengerti')),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Kategori?'),
        content: Text('Kategori "${category.name}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              await ref
                  .read(databaseProvider)
                  .categoriesDao
                  .deleteCategory(category.id);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

// ─── Category Form Sheet (Tambah & Edit) ──────────────────────────────────────

class _CategoryFormSheet extends ConsumerStatefulWidget {
  final Category? category;
  const _CategoryFormSheet({this.category});

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  late final TextEditingController _nameCtrl;
  String _selectedIcon = 'category';
  bool _loading = false;

  bool get _isEdit => widget.category != null;

  final _icons = <String, IconData>{
    'category': Icons.category_outlined,
    'fastfood': Icons.fastfood_outlined,
    'drink': Icons.local_drink_outlined,
    'snack': Icons.cookie_outlined,
    'smoke': Icons.smoking_rooms_outlined,
    'basket': Icons.shopping_basket_outlined,
    'clean': Icons.cleaning_services_outlined,
    'health': Icons.medical_services_outlined,
    'devices': Icons.devices_outlined,
    'clothes': Icons.checkroom_outlined,
    'home': Icons.home_outlined,
    'star': Icons.star_outline_rounded,
  };

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.category?.name ?? '');
    _selectedIcon = widget.category?.icon ?? 'category';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nama kategori wajib diisi')));
      return;
    }

    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      if (_isEdit) {
        await db.categoriesDao.updateCategory(
          CategoriesCompanion(
            id: Value(widget.category!.id),
            name: Value(name),
            icon: Value(_selectedIcon),
          ),
        );
      } else {
        await db.categoriesDao.insertCategory(
          CategoriesCompanion.insert(
            name: name,
            icon: Value(_selectedIcon),
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'Kategori diperbarui' : 'Kategori ditambahkan'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _isEdit ? 'Edit Kategori' : 'Tambah Kategori',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nama Kategori',
                hintText: 'cth: Minuman Dingin',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Pilih Ikon',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _icons.entries.map((e) {
                final isSelected = _selectedIcon == e.key;
                return GestureDetector(
                  onTap: () => setState(() => _selectedIcon = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.transparent),
                    ),
                    child: Icon(e.value,
                        size: 22,
                        color: isSelected ? Colors.white : Colors.grey.shade600),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        _isEdit ? 'Simpan Perubahan' : 'Tambah Kategori',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kategori Empty State ──────────────────────────────────────────────────────

class _KategoriEmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _KategoriEmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkPrimaryLight
                  : AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.category_outlined,
                size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          const Text('Belum ada kategori',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Buat kategori untuk mengelompokkan produk Anda',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Tambah Kategori'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Stats Bar ────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final List<Product> products;
  const _StatsBar({required this.products});

  @override
  Widget build(BuildContext context) {
    final total    = products.length;
    final lowStock = products.where((p) =>
        p.stock <= p.minStock && p.stock > 0).length;
    final outStock = products.where((p) => p.stock == 0).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Row(children: [
        _StatChip(
          label: '$total Produk',
          color: AppColors.primary,
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: '$lowStock Hampir Habis',
          color: AppColors.warning,
          icon: Icons.warning_amber_outlined,
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: '$outStock Habis',
          color: AppColors.danger,
          icon: Icons.remove_circle_outline,
        ),
      ]),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _StatChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color)),
      ]),
    );
  }
}

// ─── Product Grid Card (3 kolom) ──────────────────────────────────────────────

class _ProductGridCard extends ConsumerWidget {
  final Product product;
  const _ProductGridCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = product.stock == 0;
    final isLow = product.stock <= product.minStock && !isOut;
    final statusColor = isOut
        ? AppColors.danger
        : isLow
            ? AppColors.warning
            : AppColors.success;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => _showDetail(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gambar / ikon produk
            Expanded(
              flex: 5,
              child: Container(
                color: isOut
                    ? (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.grey.shade100)
                    : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkPrimaryLight : AppColors.primaryLight),
                child: product.imagePath != null &&
                        product.imagePath!.isNotEmpty
                    ? Image.file(
                        File(product.imagePath!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.inventory_2_outlined,
                          size: 32,
                          color: isOut
                              ? Colors.grey.shade400
                              : AppColors.primary,
                        ),
                      )
                    : Icon(
                        Icons.inventory_2_outlined,
                        size: 32,
                        color: isOut
                            ? Colors.grey.shade400
                            : AppColors.primary,
                      ),
              ),
            ),

            // Info bawah
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    // Nama produk
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Harga
                    Text(
                      CurrencyFormatter.format(product.sellPrice),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Badge stok
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '${product.stock} ${product.unit}',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _EditProductSheet(product: product),
      ),
    );
  }
}

// ─── Product Card ─────────────────────────────────────────────────────────────

class _ProductCard extends ConsumerWidget {
  final Product product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOut = product.stock == 0;
    final isLow = product.stock <= product.minStock && !isOut;

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showDetail(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
          child: Row(children: [
            // Foto / Icon
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: isOut
                    ? (Theme.of(context).brightness == Brightness.dark ? AppColors.darkSurface : Colors.grey.shade100)
                    : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkPrimaryLight : AppColors.primaryLight),
                borderRadius: BorderRadius.circular(12),
                image: product.imagePath != null && product.imagePath!.isNotEmpty
                    ? DecorationImage(
                        image: FileImage(File(product.imagePath!)),
                        fit: BoxFit.cover,
                        onError: (_, __) {},
                      )
                    : null,
              ),
              child: product.imagePath == null || product.imagePath!.isEmpty
                  ? Icon(
                      Icons.inventory_2_outlined,
                      size: 22,
                      color: isOut ? Colors.grey.shade400 : AppColors.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(CurrencyFormatter.format(product.sellPrice),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
                  if (product.barcode != null &&
                      product.barcode!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(product.barcode!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400)),
                  ],
                ],
              ),
            ),

            // Stock badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isOut
                        ? AppColors.danger.withOpacity(0.1)
                        : isLow
                            ? AppColors.warning.withOpacity(0.1)
                            : AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${product.stock} ${product.unit}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isOut
                          ? AppColors.danger
                          : isLow
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isOut ? 'Habis' : isLow ? 'Hampir habis' : 'Aman',
                  style: TextStyle(
                    fontSize: 10,
                    color: isOut
                        ? AppColors.danger
                        : isLow
                            ? AppColors.warning
                            : Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    // BUG #2 FIX: Kasir hanya bisa lihat detail produk, tidak bisa edit/hapus.
    final isAdmin = ref.read(isAdminProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _EditProductSheet(product: product, readOnly: !isAdmin),
      ),
    );
  }
}

// ─── Add Product Sheet ────────────────────────────────────────────────────────

class _AddProductSheet extends ConsumerStatefulWidget {
  const _AddProductSheet();

  @override
  ConsumerState<_AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends ConsumerState<_AddProductSheet> {
  final _nameCtrl     = TextEditingController();
  final _barcodeCtrl  = TextEditingController();
  final _skuCtrl      = TextEditingController();
  final _buyCtrl      = TextEditingController();
  final _sellCtrl     = TextEditingController();
  final _stockCtrl    = TextEditingController(text: '0');
  final _minStockCtrl = TextEditingController(text: '5');
  final _unitCtrl     = TextEditingController(text: 'pcs');
  int? _selectedCategoryId;
  bool _loading = false;
  bool _isScanning = false;
  String? _imagePath;

  @override
  void dispose() {
    for (final c in [_nameCtrl, _barcodeCtrl, _skuCtrl,
        _buyCtrl, _sellCtrl, _stockCtrl, _minStockCtrl, _unitCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 20, left: 20, right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SheetHandle(),
          const Text('Tambah Produk Baru',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),

          // ── Foto produk ──────────────────────────────────────────────────
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.darkPrimaryLight
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.3),
                    width: 1.5,
                  ),
                  image: _imagePath != null
                      ? DecorationImage(
                          image: FileImage(File(_imagePath!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _imagePath == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_outlined,
                            color: AppColors.primary, size: 28),
                          const SizedBox(height: 4),
                          Text('Foto Produk',
                            style: TextStyle(
                              fontSize: 11, color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                        ],
                      )
                    : Align(
                        alignment: Alignment.topRight,
                        child: GestureDetector(
                          onTap: () => setState(() => _imagePath = null),
                          child: Container(
                            margin: const EdgeInsets.all(4),
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                              color: Colors.white, size: 14),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(_imagePath != null ? 'Ketuk foto untuk ganti' : '',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Nama Produk *',
              prefixIcon: Icon(Icons.label_outline)),
          ),
          const SizedBox(height: 10),

          // ── Barcode: Scan Button atau Preview Hasil ──────────────
          StatefulBuilder(
            builder: (ctx, setSt) => _barcodeCtrl.text.isEmpty
                ? OutlinedButton.icon(
                    icon: const Icon(Icons.qr_code_scanner,
                        color: AppColors.primary),
                    label: const Text('Scan Barcode',
                        style: TextStyle(color: AppColors.primary)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await _scanBarcode();
                      setSt(() {});
                    },
                  )
                : Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkPrimaryLight
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.qr_code,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Barcode terscan',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary)),
                            Text(
                              _barcodeCtrl.text,
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() => _barcodeCtrl.clear());
                          setSt(() {});
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                              color: AppColors.danger,
                              shape: BoxShape.circle),
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
          ),
          const SizedBox(height: 10),

          // SKU (tetap manual)
          TextField(
            controller: _skuCtrl,
            decoration: const InputDecoration(
              labelText: 'SKU (opsional)',
              prefixIcon: Icon(Icons.tag)),
          ),
          const SizedBox(height: 10),

          // Category dropdown
          categories.when(
            data: (cats) => DropdownButtonFormField<int>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(
                labelText: 'Kategori',
                prefixIcon: Icon(Icons.category_outlined)),
              items: [
                const DropdownMenuItem(
                  value: null, child: Text('-- Tanpa Kategori --')),
                ...cats.map((c) => DropdownMenuItem(
                  value: c.id, child: Text(c.name))),
              ],
              onChanged: (v) =>
                  setState(() => _selectedCategoryId = v),
            ),
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(
              child: TextField(
                controller: _buyCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Harga Beli',
                  prefixText: 'Rp '),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _sellCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Harga Jual *',
                  prefixText: 'Rp '),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          Row(children: [
            Expanded(
              child: TextField(
                controller: _stockCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Stok Awal'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _minStockCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Stok Min'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _unitCtrl,
                decoration: const InputDecoration(labelText: 'Satuan'),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_loading ? 'Menyimpan...' : 'Simpan Produk'),
              onPressed: _loading ? null : _save,
            ),
          ),
        ],
      ),
    );
  }

  // ── Barcode Scanner ───────────────────────────────────────────────────────
  Future<void> _scanBarcode() async {
    final MobileScannerController scanCtrl = MobileScannerController();
    String? result;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.65,
        child: Stack(children: [
          // Kamera scanner
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            child: MobileScanner(
              controller: scanCtrl,
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull;
                if (barcode?.rawValue != null) {
                  result = barcode!.rawValue!;
                  scanCtrl.stop();
                  Navigator.pop(ctx);
                }
              },
            ),
          ),
          // Overlay UI
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Colors.black54,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Scan Barcode Produk',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  GestureDetector(
                    onTap: () {
                      scanCtrl.stop();
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Garis pemandu scan
          Center(
            child: Container(
              width: 240,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Arahkan kamera ke barcode',
                      style: TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Tombol flash
          Positioned(
            bottom: 24,
            right: 24,
            child: StatefulBuilder(
              builder: (ctx2, setSt) => GestureDetector(
                onTap: () {
                  scanCtrl.toggleTorch();
                  setSt(() {});
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.flashlight_on,
                      color: Colors.white, size: 24),
                ),
              ),
            ),
          ),
        ]),
      ),
    );

    await scanCtrl.dispose();

    if (result != null && mounted) {
      setState(() => _barcodeCtrl.text = result!);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Text('Pilih Sumber Foto',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                color: AppColors.primary),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.primary),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_imagePath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                  color: AppColors.danger),
                title: const Text('Hapus Foto',
                  style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  setState(() => _imagePath = null);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _imagePath = picked.path);
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _sellCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nama dan harga jual wajib diisi'),
          backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final inputName = _nameCtrl.text.trim();
      final inputStock = int.tryParse(_stockCtrl.text) ?? 0;

      // ── Cek nama persis sama (case-insensitive) ──────────────────────────
      final exact = await db.productsDao.getProductByName(inputName);
      if (exact != null) {
        // Nama sama persis → timpa: tambah stok saja
        final stockBefore = exact.stock;
        final stockAfter  = stockBefore + inputStock;
        await db.stockMovementsDao.adjustStock(
          db: db,
          productId: exact.id,
          newStock:  stockAfter,
          oldStock:  stockBefore,
          type: 'masuk',
          notes: 'Penambahan stok dari form tambah produk',
        );
        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Stok "${exact.name}" diperbarui: '
                '$stockBefore → $stockAfter ${exact.unit}'),
              backgroundColor: AppColors.success));
        }
        return;
      }

      // ── Cek nama mirip (tapi tidak sama persis) ──────────────────────────
      final similar = await db.productsDao.findSimilarByName(inputName);
      // Filter: buang exact match (sudah ditangani atas), ambil yang benar-benar mirip
      final notExact = similar
          .where((p) => p.name.toLowerCase() != inputName.toLowerCase())
          .toList();

      if (notExact.isNotEmpty && context.mounted) {
        setState(() => _loading = false);
        final existing = notExact.first;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Nama Produk Serupa'),
            content: Text(
              'Produk dengan nama mirip sudah ada:\n\n'
              '"${existing.name}"\n\n'
              'Apakah ini produk yang sama?\n'
              '• Tekan "Tambah Stok" untuk menambah ke produk yang ada\n'
              '• Tekan "Produk Baru" jika memang berbeda',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Batal'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Produk Baru'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('Tambah Stok'),
              ),
            ],
          ),
        );
        if (confirm == null) return; // Batal
        if (confirm == true) {
          // Tambah stok ke produk yang mirip
          final stockBefore = existing.stock;
          final stockAfter  = stockBefore + inputStock;
          await db.stockMovementsDao.adjustStock(
            db: db,
            productId: existing.id,
            newStock:  stockAfter,
            oldStock:  stockBefore,
            type: 'masuk',
            notes: 'Penambahan stok (nama mirip: $inputName)',
          );
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Stok "${existing.name}" diperbarui: '
                  '$stockBefore → $stockAfter ${existing.unit}'),
                backgroundColor: AppColors.success));
          }
          return;
        }
        // confirm == false → lanjut insert produk baru
        setState(() => _loading = true);
      }
      // ────────────────────────────────────────────────────────────────────

      final stock = int.tryParse(_stockCtrl.text) ?? 0;
      final productId = await db.productsDao.insertProduct(
        ProductsCompanion.insert(
          name: _nameCtrl.text.trim(),
          barcode: Value(_barcodeCtrl.text.isEmpty
              ? null : _barcodeCtrl.text),
          sku: Value(_skuCtrl.text.isEmpty ? null : _skuCtrl.text),
          categoryId: Value(_selectedCategoryId),
          buyPrice:  Value(double.tryParse(_buyCtrl.text) ?? 0),
          sellPrice: Value(double.tryParse(_sellCtrl.text) ?? 0),
          stock:    Value(stock),
          minStock: Value(int.tryParse(_minStockCtrl.text) ?? 5),
          unit: Value(_unitCtrl.text.isEmpty ? 'pcs' : _unitCtrl.text),
          imagePath: Value(_imagePath),
        ),
      );
      // Record initial stock movement
      if (stock > 0) {
        await db.stockMovementsDao.addMovement(
          productId: productId,
          type: 'masuk',
          quantity: stock,
          stockBefore: 0,
          stockAfter: stock,
          notes: 'Stok awal',
        );
      }
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk berhasil ditambahkan'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ─── Edit Product Sheet ───────────────────────────────────────────────────────

class _EditProductSheet extends ConsumerStatefulWidget {
  final Product product;
  final bool readOnly;
  const _EditProductSheet({required this.product, this.readOnly = false});

  @override
  ConsumerState<_EditProductSheet> createState() =>
      _EditProductSheetState();
}

class _EditProductSheetState extends ConsumerState<_EditProductSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final _nameCtrl  = TextEditingController(text: widget.product.name);
  late final _sellCtrl  = TextEditingController(
      text: widget.product.sellPrice.toStringAsFixed(0));
  late final _buyCtrl   = TextEditingController(
      text: widget.product.buyPrice.toStringAsFixed(0));
  late final _stockCtrl = TextEditingController(
      text: '${widget.product.stock}');
  late final _minCtrl   = TextEditingController(
      text: '${widget.product.minStock}');
  late final _barcodeCtrl = TextEditingController(
      text: widget.product.barcode ?? '');
  late final _adjQtyCtrl  = TextEditingController();
  late final _adjNoteCtrl = TextEditingController();
  int? _selectedCategoryId;
  String _adjType = 'masuk';
  bool _loading = false;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _selectedCategoryId = widget.product.categoryId;
    _imagePath = widget.product.imagePath;
  }

  @override
  void dispose() {
    _tab.dispose();
    for (final c in [_nameCtrl, _sellCtrl, _buyCtrl,
        _stockCtrl, _minCtrl, _barcodeCtrl,
        _adjQtyCtrl, _adjNoteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final movements = ref.watch(
        stockMovementsProvider(widget.product.id));

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SheetHandle(),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.product.name,
                          style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                        Text(CurrencyFormatter.format(
                          widget.product.sellPrice),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: widget.product.stock == 0
                          ? AppColors.danger.withOpacity(0.1)
                          : widget.product.stock <= widget.product.minStock
                              ? AppColors.warning.withOpacity(0.1)
                              : AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Stok: ${widget.product.stock} ${widget.product.unit}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: widget.product.stock == 0
                            ? AppColors.danger
                            : widget.product.stock <= widget.product.minStock
                                ? AppColors.warning
                                : AppColors.success,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TabBar(
                  controller: _tab,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppColors.primary,
                  tabs: const [
                    Tab(text: 'Edit Produk'),
                    Tab(text: 'Riwayat Stok'),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // ── Edit form ──────────────────────────────────
                SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Foto produk ──────────────────────────
                      Center(
                        child: GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? AppColors.darkPrimaryLight
                                  : AppColors.primaryLight,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.3),
                                width: 1.5,
                              ),
                              image: _imagePath != null && _imagePath!.isNotEmpty
                                  ? DecorationImage(
                                      image: FileImage(File(_imagePath!)),
                                      fit: BoxFit.cover,
                                      onError: (_, __) {},
                                    )
                                  : null,
                            ),
                            child: _imagePath == null || _imagePath!.isEmpty
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.add_a_photo_outlined,
                                        color: AppColors.primary, size: 24),
                                      const SizedBox(height: 4),
                                      Text('Ganti Foto',
                                        style: TextStyle(
                                          fontSize: 10, color: AppColors.primary,
                                          fontWeight: FontWeight.w600)),
                                    ],
                                  )
                                : Align(
                                    alignment: Alignment.topRight,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _imagePath = null),
                                      child: Container(
                                        margin: const EdgeInsets.all(4),
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          color: AppColors.danger,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.close,
                                          color: Colors.white, size: 12),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama Produk'),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _barcodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Barcode',
                          prefixIcon: Icon(Icons.qr_code)),
                      ),
                      const SizedBox(height: 10),
                      categories.when(
                        data: (cats) =>
                            DropdownButtonFormField<int>(
                          value: _selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Kategori',
                            prefixIcon: Icon(Icons.category_outlined)),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('-- Tanpa Kategori --')),
                            ...cats.map((c) => DropdownMenuItem(
                              value: c.id, child: Text(c.name))),
                          ],
                          onChanged: (v) =>
                              setState(() => _selectedCategoryId = v),
                        ),
                        loading: () => const SizedBox(),
                        error: (_, __) => const SizedBox(),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _buyCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Harga Beli',
                              prefixText: 'Rp '),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _sellCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Harga Jual',
                              prefixText: 'Rp '),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: TextField(
                            controller: _minCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(
                              labelText: 'Stok Minimum'),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),

                      // Adjustment stok
                      const Text('Penyesuaian Stok',
                        style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: _buildAdjTypeChip('masuk', 'Masuk',
                            Icons.add_circle_outline, AppColors.success),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAdjTypeChip('keluar', 'Keluar',
                            Icons.remove_circle_outline, AppColors.danger),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAdjTypeChip('koreksi', 'Koreksi',
                            Icons.edit_outlined, AppColors.info),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _adjQtyCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: _adjType == 'koreksi'
                                  ? 'Stok Baru'
                                  : 'Jumlah',
                              prefixIcon: Icon(
                                _adjType == 'masuk'
                                    ? Icons.add
                                    : _adjType == 'keluar'
                                        ? Icons.remove
                                        : Icons.edit,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _adjNoteCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Keterangan',
                              prefixIcon: Icon(Icons.note_alt_outlined),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 20),

                      // BUG #2 FIX: Kasir tidak bisa hapus atau simpan perubahan produk
                      if (widget.readOnly)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.warning.withOpacity(0.3)),
                          ),
                          child: const Row(children: [
                            Icon(Icons.info_outline,
                                color: AppColors.warning, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Hanya Admin yang dapat mengubah data produk.',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.warning),
                              ),
                            ),
                          ]),
                        )
                      else
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.delete_outline,
                                color: AppColors.danger, size: 18),
                              label: const Text('Hapus',
                                style: TextStyle(color: AppColors.danger)),
                              onPressed: () => _delete(context)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: _loading
                                  ? const SizedBox(
                                      width: 16, height: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.save_outlined, size: 18),
                              label: Text(_loading ? 'Menyimpan...' : 'Simpan'),
                              onPressed: _loading ? null : _update),
                          ),
                        ]),
                    ],
                  ),
                ),

                // ── Riwayat stok ──────────────────────────────
                movements.when(
                  data: (list) => list.isEmpty
                      ? const Center(
                          child: Text('Belum ada riwayat stok'))
                      : ListView.separated(
                          controller: ctrl,
                          padding: const EdgeInsets.fromLTRB(
                            16, 12, 16, 20),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (_, i) =>
                              _MovementCard(movement: list[i]),
                        ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),
            const Text('Pilih Sumber Foto',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                color: AppColors.primary),
              title: const Text('Kamera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                color: AppColors.primary),
              title: const Text('Galeri'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (_imagePath != null && _imagePath!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                  color: AppColors.danger),
                title: const Text('Hapus Foto',
                  style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  setState(() => _imagePath = null);
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _imagePath = picked.path);
    }
  }

  Widget _buildAdjTypeChip(
      String value, String label, IconData icon, Color color) {
    final isSelected = _adjType == value;
    return GestureDetector(
      onTap: () => setState(() => _adjType = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300),
        ),
        child: Column(children: [
          Icon(icon, size: 16,
            color: isSelected ? color : Colors.grey.shade500),
          const SizedBox(height: 3),
          Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? color : Colors.grey.shade500,
            )),
        ]),
      ),
    );
  }

  Future<void> _update() async {
    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final adjQty = int.tryParse(_adjQtyCtrl.text) ?? 0;

      await db.productsDao.updateProduct(
        ProductsCompanion(
          id: Value(widget.product.id),
          name: Value(_nameCtrl.text.trim()),
          barcode: Value(_barcodeCtrl.text.isEmpty
              ? null : _barcodeCtrl.text),
          categoryId: Value(_selectedCategoryId),
          buyPrice:  Value(double.tryParse(_buyCtrl.text) ?? 0),
          sellPrice: Value(double.tryParse(_sellCtrl.text) ?? 0),
          minStock:  Value(int.tryParse(_minCtrl.text) ?? 5),
          imagePath: Value(_imagePath),
        ),
      );

      // Apply stock adjustment
      if (adjQty > 0) {
        final oldStock = widget.product.stock;
        int newStock;
        if (_adjType == 'masuk') {
          newStock = oldStock + adjQty;
        } else if (_adjType == 'keluar') {
          newStock = (oldStock - adjQty).clamp(0, 999999);
        } else {
          newStock = adjQty; // koreksi = set langsung
        }
        await db.stockMovementsDao.adjustStock(
          db: db,
          productId: widget.product.id,
          newStock: newStock,
          oldStock: oldStock,
          type: _adjType,
          notes: _adjNoteCtrl.text.isEmpty ? null : _adjNoteCtrl.text,
        );
      }

      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk diperbarui'),
            backgroundColor: AppColors.success));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Produk?'),
        content: Text('${widget.product.name} akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger),
            child: const Text('Hapus')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(databaseProvider)
          .productsDao.deleteProduct(widget.product.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

// ─── Movement Card ────────────────────────────────────────────────────────────

class _MovementCard extends StatelessWidget {
  final StockMovement movement;
  const _MovementCard({required this.movement});

  @override
  Widget build(BuildContext context) {
    final isMasuk   = movement.type == 'masuk';
    final isKeluar  = movement.type == 'keluar';
    final color = isMasuk
        ? AppColors.success
        : isKeluar
            ? AppColors.danger
            : AppColors.info;
    final icon = isMasuk
        ? Icons.add_circle_outline
        : isKeluar
            ? Icons.remove_circle_outline
            : Icons.edit_outlined;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${movement.type.toUpperCase()} ${movement.quantity} unit',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
                if (movement.notes != null) ...[
                  const SizedBox(height: 2),
                  Text(movement.notes!,
                    style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
                ],
                const SizedBox(height: 2),
                Text(
                  _formatDate(movement.createdAt),
                  style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade400)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${movement.stockBefore} → ${movement.stockAfter}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13)),
              Text('unit', style: TextStyle(
                fontSize: 10, color: Colors.grey.shade400)),
            ],
          ),
        ]),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Center(
        child: Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}
