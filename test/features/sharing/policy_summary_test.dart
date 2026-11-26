import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/sharing/share_rules.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/sharing/presentation/approval_screens.dart';

void main() {
  test('Household defaults read as in the mockup', () {
    expect(
      policySummary(SharePolicy.defaults(SpaceKind.household)),
      'Changes by others to the plan are free; deletions need approval',
    );
  });

  test('chama defaults: everything needs approval', () {
    expect(
      policySummary(SharePolicy.defaults(SpaceKind.savingsGroup)),
      'Changes by others need approval',
    );
  });

  test('accounts are named only when they differ from the plan', () {
    const p = SharePolicy(SpaceKind.household, {
      RuleArea.plan: ChangeLevel.approval,
      RuleArea.accounts: ChangeLevel.restricted,
      RuleArea.others: ChangeLevel.anyone,
    });
    expect(
      policySummary(p),
      'Changes by others to the plan need approval; accounts are Owner '
      'only; deletions are free',
    );
  });
}
