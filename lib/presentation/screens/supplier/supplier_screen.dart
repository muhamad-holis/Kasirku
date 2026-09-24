import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../providers/suppliers_provider.dart';
import '../../providers/database_provider.dart';
import '../../../data/database/app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Screen Utama
// ─────────────────────────────────────────────────────────────────────────────

class SupplierScreen extends ConsumerStatefulWidget {
  const SupplierScreen({super.key});

  @override
  ConsumerState<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends ConsumerState<SupplierScreen> {
  final _searchCtrl = TextEditingController();
  Supplier? _selectedSupplier;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showDetail(BuildContext context, Supplier supplier) {
    final isTabletLandscape = Responsive.isTabletLandscape(context);
    if (isTabletLandscape) {
      setState(() => _selectedSupplier = supplier);
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ProviderScope(
          parent: ProviderScope.containerOf(context),
          child: _SupplierDetailSheet(
            supplier: supplier,
            onEdit: () {
              Navigator.pop(context);
              _showEditSheet(context, supplier);
            },
          ),
        ),
      );
    }
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _SupplierFormSheet(
          onSaved: () => Navigator.pop(context),
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context, Supplier supplier) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _SupplierFormSheet(
          supplier: supplier,
          onSaved: () => Navigator.pop(context),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Supplier supplier) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 22),
          SizedBox(width: 8),
          Text('Hapus Pemasok', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'Hapus "${supplier.name}"? Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await ref.read(databaseProvider).suppliersDao.deleteSupplier(supplier.id);
      if (_selectedSupplier?.id == supplier.id) {
        setState(() => _selectedSupplier = null);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${supplier.name} dihapus'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = ref.watch(filteredSuppliersProvider);
    final stats    = ref.watch(supplierStatsProvider);
    final isTabletLandscape = Responsive.isTabletLandscape(context);

    final listWidget = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) =>
                ref.read(supplierSearchProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Cari nama, perusahaan, produk...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        ref.read(supplierSearchProvider.notifier).state = '';
                      },
                    )
                  : null,
            ),
          ),
        ),
        stats.when(
          data: (s) => _StatsBar(stats: s),
          loading: () => const SizedBox(height: 36),
          error: (_, __) => const SizedBox(),
        ),
        Expanded(
          child: filtered.when(
            data: (list) {
              if (list.isEmpty) {
                return _EmptyState(
                  isSearching: _searchCtrl.text.isNotEmpty,
                  onAdd: () => _showAddSheet(context),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _SupplierCard(
                  supplier: list[i],
                  selected: isTabletLandscape &&
                      _selectedSupplier?.id == list[i].id,
                  onTap: () => _showDetail(context, list[i]),
                  onEdit: () => _showEditSheet(context, list[i]),
                  onDelete: () => _confirmDelete(context, list[i]),
                ),
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );

    if (isTabletLandscape) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Pemasok / Supplier',
              style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_outlined),
              tooltip: 'Tambah Pemasok',
              onPressed: () => _showAddSheet(context),
            ),
          ],
        ),
        body: Row(
          children: [
            Expanded(flex: 2, child: listWidget),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 3,
              child: _selectedSupplier == null
                  ? _NoSelectionPlaceholder(
                      icon: Icons.local_shipping_outlined,
                      label: 'Pilih pemasok untuk melihat detail',
                    )
                  : _SupplierDetailPanel(
                      key: ValueKey(_selectedSupplier!.id),
                      supplier: _selectedSupplier!,
                      onEdit: () =>
                          _showEditSheet(context, _selectedSupplier!),
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pemasok / Supplier',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Tambah Pemasok',
            onPressed: () => _showAddSheet(context),
          ),
        ],
      ),
      body: listWidget,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Bar
// ─────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final Map<String, int> stats;
  const _StatsBar({required this.stats});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.local_shipping_rounded,
            label: '${stats['total'] ?? 0} Pemasok',
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.phone_rounded,
            label: '${stats['withPhone'] ?? 0} Ada No. HP',
            color: AppColors.success,
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.business_rounded,
            label: '${stats['withCompany'] ?? 0} Perusahaan',
            color: AppColors.info,
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Supplier Card
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierCard extends StatelessWidget {
  final Supplier supplier;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupplierCard({
    required this.supplier,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = selected
        ? AppColors.primary.withOpacity(0.08)
        : (isDark ? AppColors.darkCard : Colors.white);
    final borderColor = selected
        ? AppColors.primary
        : (isDark ? AppColors.darkBorder : AppColors.border);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: selected ? 1.5 : 0.5),
          ),
          child: Row(
            children: [
              // Avatar inisial
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  supplier.name.isNotEmpty
                      ? supplier.name[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.name,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (supplier.company != null &&
                        supplier.company!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.business_rounded,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(supplier.company!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                    if (supplier.products != null &&
                        supplier.products!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.inventory_2_outlined,
                            size: 11, color: AppColors.textSecondary),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(supplier.products!,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                    if (supplier.phone != null &&
                        supplier.phone!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Row(children: [
                        const Icon(Icons.phone_rounded,
                            size: 11, color: AppColors.success),
                        const SizedBox(width: 3),
                        Text(supplier.phone!,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.success)),
                      ]),
                    ],
                  ],
                ),
              ),
              // Action buttons
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 18, color: AppColors.textSecondary),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(children: [
                      Icon(Icons.edit_outlined,
                          size: 16, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete_outline_rounded,
                          size: 16, color: AppColors.danger),
                      SizedBox(width: 8),
                      Text('Hapus',
                          style: TextStyle(color: AppColors.danger)),
                    ]),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail Sheet (Mobile)
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierDetailSheet extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onEdit;

  const _SupplierDetailSheet({
    required this.supplier,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, ctrl) => _SupplierDetailContent(
        supplier: supplier,
        scrollController: ctrl,
        onEdit: onEdit,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail Panel (Tablet)
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierDetailPanel extends StatelessWidget {
  final Supplier supplier;
  final VoidCallback onEdit;

  const _SupplierDetailPanel({
    super.key,
    required this.supplier,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return _SupplierDetailContent(
      supplier: supplier,
      scrollController: null,
      onEdit: onEdit,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail Content (shared)
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierDetailContent extends StatelessWidget {
  final Supplier supplier;
  final ScrollController? scrollController;
  final VoidCallback onEdit;

  const _SupplierDetailContent({
    required this.supplier,
    required this.scrollController,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.darkSurface : Colors.white;

    Widget body = ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        // Handle bar (hanya untuk sheet mobile)
        if (scrollController != null) ...[
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],

        // Avatar + Nama
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  supplier.name.isNotEmpty
                      ? supplier.name[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(supplier.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center),
              if (supplier.company != null &&
                  supplier.company!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(supplier.company!,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Info rows
        _DetailCard(
          children: [
            if (supplier.products != null && supplier.products!.isNotEmpty)
              _InfoRow(
                icon: Icons.inventory_2_outlined,
                label: 'Produk Disuplai',
                value: supplier.products!,
              ),
            if (supplier.phone != null && supplier.phone!.isNotEmpty)
              _InfoRow(
                icon: Icons.phone_rounded,
                label: 'No. HP / Telepon',
                value: supplier.phone!,
                valueColor: AppColors.primary,
              ),
            if (supplier.address != null && supplier.address!.isNotEmpty)
              _InfoRow(
                icon: Icons.location_on_outlined,
                label: 'Alamat',
                value: supplier.address!,
              ),
            if (supplier.notes != null && supplier.notes!.isNotEmpty)
              _InfoRow(
                icon: Icons.sticky_note_2_outlined,
                label: 'Catatan',
                value: supplier.notes!,
              ),
          ],
        ),
        const SizedBox(height: 16),

        // Tombol Edit
        ElevatedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: const Text('Edit Pemasok'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );

    // Untuk sheet mobile, bungkus dengan Container rounded
    if (scrollController != null) {
      return Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: body,
      );
    }
    return body;
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = children.whereType<_InfoRow>().toList();
    if (filtered.isEmpty) return const SizedBox();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 0.5),
      ),
      child: Column(
        children: [
          for (int i = 0; i < filtered.length; i++) ...[
            filtered[i],
            if (i < filtered.length - 1)
              Divider(
                  height: 1,
                  color: isDark ? AppColors.darkBorder : AppColors.border),
          ]
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: valueColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Form Sheet (Tambah / Edit)
// ─────────────────────────────────────────────────────────────────────────────

class _SupplierFormSheet extends ConsumerStatefulWidget {
  final Supplier? supplier; // null = tambah baru
  final VoidCallback onSaved;

  const _SupplierFormSheet({this.supplier, required this.onSaved});

  @override
  ConsumerState<_SupplierFormSheet> createState() =>
      _SupplierFormSheetState();
}

class _SupplierFormSheetState extends ConsumerState<_SupplierFormSheet> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _productsCtrl= TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl   = TextEditingController();
  bool _saving = false;

  bool get _isEdit => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text    = widget.supplier!.name;
      _companyCtrl.text = widget.supplier!.company ?? '';
      _productsCtrl.text= widget.supplier!.products ?? '';
      _phoneCtrl.text   = widget.supplier!.phone ?? '';
      _addressCtrl.text = widget.supplier!.address ?? '';
      _notesCtrl.text   = widget.supplier!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _companyCtrl.dispose();
    _productsCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final companion = SuppliersCompanion(
      id:      _isEdit ? Value(widget.supplier!.id) : const Value.absent(),
      name:    Value(_nameCtrl.text.trim()),
      company: Value(_companyCtrl.text.trim().isEmpty
          ? null
          : _companyCtrl.text.trim()),
      products: Value(_productsCtrl.text.trim().isEmpty
          ? null
          : _productsCtrl.text.trim()),
      phone:   Value(_phoneCtrl.text.trim().isEmpty
          ? null
          : _phoneCtrl.text.trim()),
      address: Value(_addressCtrl.text.trim().isEmpty
          ? null
          : _addressCtrl.text.trim()),
      notes:   Value(_notesCtrl.text.trim().isEmpty
          ? null
          : _notesCtrl.text.trim()),
    );

    final db = ref.read(databaseProvider);
    if (_isEdit) {
      await db.suppliersDao.updateSupplier(companion);
    } else {
      await db.suppliersDao.insertSupplier(companion);
    }

    setState(() => _saving = false);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final sheetBg  = isDark ? AppColors.darkSurface : Colors.white;
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Judul
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isEdit ? 'Edit Pemasok' : 'Tambah Pemasok',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Nama Pemasok / Sales (wajib)
              _FormLabel(label: 'Nama Pemasok / Sales', isRequired: true),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'cth: Pak Budi, Bu Sari',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 14),

              // ── Perusahaan / Distributor
              const _FormLabel(label: 'Perusahaan / Distributor'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _companyCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'cth: PT. Sayap Mas Utama',
                ),
              ),
              const SizedBox(height: 14),

              // ── Produk yang Disuplai
              const _FormLabel(label: 'Produk yang Disuplai'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _productsCtrl,
                decoration: const InputDecoration(
                  hintText: 'cth: Mie Sedap, Indomie, Sarimi',
                ),
              ),
              const SizedBox(height: 14),

              // ── No. HP / Telepon
              const _FormLabel(label: 'No. HP / Telepon'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  hintText: 'cth: 0838-xxxx-xxxx',
                  prefixIcon: Icon(Icons.phone_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 14),

              // ── Alamat
              const _FormLabel(label: 'Alamat'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _addressCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Alamat pemasok',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),

              // ── Catatan
              const _FormLabel(label: 'Catatan'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'cth: Kirim tiap Senin pagi',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),

              // Tombol aksi
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Simpan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  final String label;
  final bool isRequired;
  const _FormLabel({required this.label, this.isRequired = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        if (isRequired)
          const Text(' *',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isSearching;
  final VoidCallback onAdd;
  const _EmptyState({required this.isSearching, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off_rounded : Icons.local_shipping_outlined,
            size: 60,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            isSearching ? 'Pemasok tidak ditemukan' : '0 pemasok terdaftar',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            isSearching
                ? 'Coba kata kunci yang berbeda'
                : 'Tambah pemasok pertama Anda',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textHint),
          ),
          if (!isSearching) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah Pemasok'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoSelectionPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  const _NoSelectionPlaceholder(
      {required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppColors.textHint),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
