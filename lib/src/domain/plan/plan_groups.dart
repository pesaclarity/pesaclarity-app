import '../enums.dart';
import 'month_plan.dart';

/// The seeded category key for school fees, shown as its own group.
const schoolFeesKey = 'school_fees';

/// How Plan groups planned outgoings under the income bar.
enum PlanGroup {
  debt('Debt'),
  tax('Tax reserve'),
  living('Living'),
  school('School'),
  savings('Savings');

  const PlanGroup(this.label);

  final String label;
}

/// One group's planned total.
class PlanGroupTotal {
  const PlanGroupTotal(this.group, this.amountMinor);

  final PlanGroup group;
  final int amountMinor;
}

/// Planned outgoings in [plan] by group, in [PlanGroup] order, leaving out
/// empty groups. Uncategorised and transfer lines count as Living.
List<PlanGroupTotal> plannedGroups(MonthPlan plan) {
  final totals = <PlanGroup, int>{};
  for (final line in plan.outgoingLines) {
    final group = groupOf(plan, line.categoryId);
    totals[group] = (totals[group] ?? 0) + line.amountMinor;
  }
  return [
    for (final group in PlanGroup.values)
      if ((totals[group] ?? 0) > 0) PlanGroupTotal(group, totals[group]!),
  ];
}

/// The group a line in [categoryId] belongs to.
PlanGroup groupOf(MonthPlan plan, int? categoryId) {
  final category = plan.categories[categoryId];
  if (category == null) return PlanGroup.living;
  return switch (category.type) {
    CategoryType.debt => PlanGroup.debt,
    CategoryType.tax => PlanGroup.tax,
    CategoryType.savings => PlanGroup.savings,
    CategoryType.expense when category.key == schoolFeesKey => PlanGroup.school,
    CategoryType.expense ||
    CategoryType.income ||
    CategoryType.transfer => PlanGroup.living,
  };
}
