/// How money usually comes to a person. Several can apply at once.
enum IncomeSource {
  salary('Salary', 'Monthly, every two weeks or weekly'),
  business('Business or hustle', 'Jua kali, a shop, a till, boda'),
  gigs('Gigs and casual work', 'Freelance, mjengo, delivery'),
  support('Family or sponsor support', 'Parents, relatives, a spouse'),
  allowance('Allowance, bursary or HELB', 'For students'),
  seasonal('Seasonal', 'Farming or harvest income'),
  nothingSteady('Nothing steady right now', 'Between jobs');

  const IncomeSource(this.label, this.hint);

  final String label;
  final String hint;
}

/// The sources a person picked. Empty until they answer.
class IncomeSources {
  const IncomeSources(this.picked);

  /// Reads what [toJson] wrote; unknown names are skipped.
  factory IncomeSources.fromJson(Map<String, Object?>? json) => IncomeSources({
    for (final name in (json?['sources'] as List? ?? const []))
      ...IncomeSource.values.where((s) => s.name == name),
  });

  final Set<IncomeSource> picked;

  bool get answered => picked.isNotEmpty;

  /// Only a salary: the monthly plan and payday fit.
  bool get salaryOnly =>
      picked.length == 1 && picked.contains(IncomeSource.salary);

  /// Money comes most days or at no fixed time: plan a week at a time.
  bool get irregular =>
      picked.contains(IncomeSource.business) ||
      picked.contains(IncomeSource.gigs);

  /// No money expected soon: show how long what is on hand lasts.
  bool get noDate =>
      !irregular &&
      picked.isNotEmpty &&
      picked.every(
        (s) => s == IncomeSource.seasonal || s == IncomeSource.nothingSteady,
      );

  Map<String, Object?> toJson() => {
    'sources': [
      for (final s in IncomeSource.values)
        if (picked.contains(s)) s.name,
    ],
  };
}
