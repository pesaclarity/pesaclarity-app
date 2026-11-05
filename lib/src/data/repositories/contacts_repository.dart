import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// A person's phone and how to remind them.
class Contact {
  const Contact({required this.name, this.phone, this.sendWith});

  final String name;

  /// In full international form, such as +254712345678.
  final String? phone;
  final SendWith? sendWith;
}

/// Phones and reminder choices for customers and suppliers, by name.
abstract interface class ContactsRepository {
  Future<Contact?> byName(String name);

  /// Saves [name]'s phone and how to remind them.
  Future<void> save(Contact contact);

  Future<List<Contact>> all();
}

String _key(String name) => name.trim().toLowerCase();

class DriftContactsRepository implements ContactsRepository {
  DriftContactsRepository(this._db);

  final AppDatabase _db;

  Contact _contact(ContactRecord r) =>
      Contact(name: r.name, phone: r.phone, sendWith: r.sendWith);

  @override
  Future<Contact?> byName(String name) async {
    final r = await (_db.select(
      _db.contacts,
    )..where((c) => c.nameKey.equals(_key(name)))).getSingleOrNull();
    return r == null ? null : _contact(r);
  }

  @override
  Future<void> save(Contact contact) => _db
      .into(_db.contacts)
      .insert(
        ContactsCompanion.insert(
          nameKey: _key(contact.name),
          name: contact.name.trim(),
          phone: Value(contact.phone),
          sendWith: Value(contact.sendWith),
        ),
        onConflict: DoUpdate(
          (_) => ContactsCompanion(
            phone: Value(contact.phone),
            sendWith: Value(contact.sendWith),
          ),
          target: [_db.contacts.nameKey],
        ),
      );

  @override
  Future<List<Contact>> all() async => [
    for (final r in await _db.select(_db.contacts).get()) _contact(r),
  ];
}

final contactsRepositoryProvider = Provider<ContactsRepository>(
  (ref) => DriftContactsRepository(ref.watch(appDatabaseProvider)),
);
