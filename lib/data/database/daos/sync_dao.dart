part of '../app_database.dart';

@DriftAccessor(tables: [SyncQueue, Transactions])
class SyncDao extends DatabaseAccessor<AppDatabase>
    with _$SyncDaoMixin {
  SyncDao(super.db);

  Future<List<SyncQueueData>> getUnsyncedItems() =>
      (select(syncQueue)..where((t) => t.isSynced.equals(false))).get();

  Future<int> addToQueue(SyncQueueCompanion item) =>
      into(syncQueue).insert(item);

  Future<void> markSynced(int id) =>
      (update(syncQueue)..where((t) => t.id.equals(id)))
          .write(const SyncQueueCompanion(isSynced: Value(true)));
}
