import '../database/app_database.dart';

/// A random UUID (version 4), worked out in SQL.
const sqlUuid =
    "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' "
    "|| substr(lower(hex(randomblob(2))), 2) || '-' "
    "|| substr('89ab', 1 + (abs(random()) % 4), 1) "
    "|| substr(lower(hex(randomblob(2))), 2) || '-' "
    '|| lower(hex(randomblob(6)))';

/// The tables a shared space keeps in step, by the entity name the log
/// uses.
const shareTables = {
  'account': 'accounts',
  'category': 'categories',
  'transaction': 'transactions',
  'budget': 'budget_items',
};

/// Gives every shareable row a stable id, now and as rows are added, and
/// keeps `share_dirty` while the space is shared (decision 0031). A seeded
/// category's id comes from its key, so the same category matches on every
/// phone. Safe to run again: rows that have an id keep it.
Future<void> createShareTriggers(AppDatabase db) async {
  const shared = 'EXISTS (SELECT 1 FROM share_state)';
  const now = "CAST((julianday('now') - 2440587.5) * 86400000 AS INTEGER)";
  for (final MapEntry(key: entity, value: table) in shareTables.entries) {
    final id = table == 'categories'
        ? "COALESCE('key:' || key, $sqlUuid)"
        : sqlUuid;
    await db.customStatement(
      'UPDATE $table SET share_uid = $id WHERE share_uid IS NULL',
    );
    // Ids are kept apart by the trigger below, not by a unique index: code
    // that copies a row keeps working, and the copy gets an id of its own.
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS ${table}_share_uid ON $table (share_uid)',
    );
    String mark(String row) =>
        'DELETE FROM share_dirty WHERE entity = '
        "'$entity' AND row_id = $row; "
        'INSERT INTO share_dirty (entity, row_id, at) '
        "VALUES ('$entity', $row, $now);";
    final triggers = {
      '${table}_share_uid_insert':
          // A row copied from another, with its id, gets an id of its own.
          'AFTER INSERT ON $table WHEN NEW.share_uid IS NULL OR EXISTS '
          '(SELECT 1 FROM $table o WHERE o.share_uid = NEW.share_uid '
          'AND o.id <> NEW.id) BEGIN '
          'UPDATE $table SET share_uid = '
          '${table == 'categories' ? "COALESCE('key:' || NEW.key, $sqlUuid)" : sqlUuid} '
          'WHERE id = NEW.id; END',
      '${table}_share_insert':
          'AFTER INSERT ON $table WHEN $shared BEGIN ${mark('NEW.id')} END',
      '${table}_share_update':
          'AFTER UPDATE ON $table WHEN $shared BEGIN ${mark('NEW.id')} END',
      '${table}_share_delete':
          'AFTER DELETE ON $table WHEN $shared AND OLD.share_uid IS NOT NULL '
          "BEGIN DELETE FROM share_dirty WHERE entity = '$entity' "
          'AND row_id = OLD.id; '
          'INSERT INTO share_dirty (entity, row_id, at, removed_uid) '
          "VALUES ('$entity', OLD.id, $now, OLD.share_uid); END",
    };
    for (final MapEntry(key: name, value: body) in triggers.entries) {
      await db.customStatement('CREATE TRIGGER IF NOT EXISTS $name $body');
    }
  }
}
