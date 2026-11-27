/// Subcategories: a category can sit under one other, such as Uber under
/// Transport. One level only. Totals add a subcategory's money into its
/// parent; only the drill-down, the picker and labels tell them apart.
library;

/// Between a parent's name and its subcategory's: "Transport › Uber".
const subcategorySeparator = ' › ';

/// How a category is named where it stands alone: "Transport › Uber" for a
/// subcategory, the name itself otherwise.
String categoryPath(String name, {String? parentName}) =>
    parentName == null ? name : '$parentName$subcategorySeparator$name';

/// The minimal shape the helpers below need from a category row.
typedef CategoryNode = ({int id, String name, int? parentId});

/// Full names by id: subcategories as "Parent › Child".
Map<int, String> categoryPaths(Iterable<CategoryNode> all) {
  final names = {for (final c in all) c.id: c.name};
  return {
    for (final c in all)
      c.id: categoryPath(
        c.name,
        parentName: c.parentId == null ? null : names[c.parentId],
      ),
  };
}

/// The top-level category [id] adds up into: its parent, or itself.
int topLevelCategoryId(int id, Map<int, int?> parentOf) => parentOf[id] ?? id;

/// Whether [parentId] can take a new subcategory: it must exist and be
/// top-level, since subcategories go one level deep.
bool canHoldSubcategories(int parentId, Map<int, int?> parentOf) =>
    parentOf.containsKey(parentId) && parentOf[parentId] == null;
