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
	static void rowsGetMonthsOrEndsAndStatus() {
		Date today = Date.newInstance(2026, 6, 1);
		List<Map<String, Object>> levels = new List<Map<String, Object>>{
			new Map<String, Object>{ 'Term__c' => '2', 'Term_Unit__c' => 'Year' }
		};
		EssentialsMigrationKit.shapeRows(EssentialsMigrationKit.LEVELS, levels, today);
		Assert.areEqual('24', levels[0].get('Months'), 'two years');

		List<Map<String, Object>> terms = new List<Map<String, Object>>{
			new Map<String, Object>{
				'Does_Not_Expire__c' => 'true',
				'End_Date__c' => '2020-01-01'
			},
			new Map<String, Object>{
				'Does_Not_Expire__c' => 'false',
				'End_Date__c' => '2026-05-31'
			},
			new Map<String, Object>{
				'Does_Not_Expire__c' => 'false',
				'End_Date__c' => '2026-06-30'
			}
		};
		EssentialsMigrationKit.shapeRows(EssentialsMigrationKit.TERMS, terms, today);
		Assert.areEqual('', terms[0].get('Ends'), 'does not expire');
		Assert.areEqual('Current', terms[0].get('Status'), 'never ends');
		Assert.areEqual('2026-05-31', terms[1].get('Ends'), 'its end date');
		Assert.areEqual('Lapsed', terms[1].get('Status'), 'ended');
		Assert.areEqual('Current', terms[2].get('Status'), 'not yet ended');
	}

	@IsTest
	static void levelAndTermStepsAreRefusedWithoutEssentials() {
		for (String key : new List<String>{ 'levels', 'terms' }) {
			try {
				Assert.isNotNull(new EssentialsMigrationKit().rows(key, new List<SObject>()), key);
			} catch (Exception refused) {
				Assert.isTrue(
					refused.getMessage().contains('this org does not have'),
					key + ' names what is missing: ' + refused.getMessage()
				);
			}
		}
		Assert.areEqual('2', EssentialsMigrationKit.months('60', 'Day'), 'sixty days');
		Assert.areEqual('1', EssentialsMigrationKit.months('1', 'Day'), 'at least one month');
		Assert.areEqual('0', EssentialsMigrationKit.months('-3', 'Month'), 'negative never ends');
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
