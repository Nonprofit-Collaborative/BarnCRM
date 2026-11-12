/**
 * The Memberships Essentials kit's computed columns (canonical model R-MEM9): a level's term in
 * months from Essentials' number and unit, and a membership's end and status.
 */
@IsTest(testFor='ApexClass:EssentialsMigrationKit')
private class EssentialsMigrationKitTest {
	// runs-as: deploying user (pure logic: converts text values, no DML or SOQL)

	@IsTest
	static void termsBecomeWholeMonths() {
		Assert.areEqual('12', EssentialsMigrationKit.months('1', 'Year'), 'a year');
		Assert.areEqual('6', EssentialsMigrationKit.months('6', 'Month'), 'months as they are');
		Assert.areEqual('6', EssentialsMigrationKit.months('6', null), 'no unit reads as months');
		Assert.areEqual('3', EssentialsMigrationKit.months('90', 'Day'), 'days, rounded');
		Assert.areEqual('1', EssentialsMigrationKit.months('1', 'Week'), 'at least one month');
		Assert.areEqual('0', EssentialsMigrationKit.months('', 'Year'), 'no term never ends');
		Assert.areEqual(
			'0',
			EssentialsMigrationKit.months('soon', 'Year'),
			'unreadable never ends'
		);
	}

	@IsTest
	static void membershipsAreCurrentUntilTheyEnd() {
		Date today = Date.newInstance(2026, 6, 1);
		Assert.areEqual('Current', EssentialsMigrationKit.statusOf('', today), 'never ends');
		Assert.areEqual(
			'Current',
			EssentialsMigrationKit.statusOf('2026-06-01', today),
			'ends today'
		);
		Assert.areEqual('Lapsed', EssentialsMigrationKit.statusOf('2026-05-31', today), 'ended');
		Assert.isNull(
			new EssentialsMigrationKit().rows('other', null),
			'other steps keep defaults'
		);
		Assert.isNull(new EssentialsMigrationKit().verify('levels'), 'no check of its own');
	}
}
