part of '../app_database.dart';

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Future<List<Category>> getAllCategories() => select(categories).get();
  Stream<List<Category>> watchCategories() => select(categories).watch();
  Future<int> insertCategory(CategoriesCompanion c) => into(categories).insert(c);
  Future<bool> updateCategory(CategoriesCompanion c) => update(categories).replace(c);
  Future<int> deleteCategory(int id) =>
      (delete(categories)..where((t) => t.id.equals(id))).go();
}
