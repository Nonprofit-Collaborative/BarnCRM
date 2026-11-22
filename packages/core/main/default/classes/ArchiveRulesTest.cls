/**
 * Archive rules (canonical model R-SQ16): the `archive` key, its checks, its schedule, and the
 * destination seam's lookup.
 */
@IsTest
private class ArchiveRulesTest {
	// The one method that reads records runs as a user it creates; the rest need no user:
	// runs-as: deploying user (pure logic: a JSON document, dates and the packaged help catalog, no DML)
	private static final String QUERY = '{"version":1,"object":"Contact","fields":["Name"],"grid":{"version":1}}';

	private static ArchiveRules.Rule rule(String destination, String frequency, Integer weekday, Integer monthDay) {
		ArchiveRules.Rule result = new ArchiveRules.Rule();
		result.destination = destination;
		result.frequency = frequency;
		result.weekday = weekday;
		result.monthDay = monthDay;
		return result;
	}

	@IsTest
	static void writesAndReadsTheKeyKeepingTheRestOfTheDocument() {
		String saved = ArchiveRules.withRule(QUERY, rule(ArchiveRules.BIG_OBJECT, ArchiveRules.WEEKLY, 3, null));
		Map<String, Object> document = (Map<String, Object>) JSON.deserializeUntyped(saved);
		System.Assert.areEqual('Contact', document.get('object'), 'The query is kept');
		System.Assert.isTrue(document.containsKey('grid'), 'Other keys are kept');

		ArchiveRules.Rule read = ArchiveRules.of(saved);
		System.Assert.areEqual(ArchiveRules.BIG_OBJECT, read.destination, 'Destination read back');
		System.Assert.areEqual(ArchiveRules.WEEKLY, read.frequency, 'Frequency read back');
		System.Assert.areEqual(3, read.weekday, 'Weekday read back');
		System.Assert.isNull(read.monthDay, 'A weekly rule keeps no month day');
		System.Assert.isTrue(read.active, 'Active by default');
		System.Assert.isTrue(ArchiveRules.isRule(saved), 'It is a rule');

		String removed = ArchiveRules.withRule(saved, null);
		System.Assert.isFalse(ArchiveRules.isRule(removed), 'A null rule takes the key off');
		System.Assert.isTrue(
			((Map<String, Object>) JSON.deserializeUntyped(removed)).containsKey('grid'),
			'Removing keeps other keys'
		);
	}

	@IsTest
	static void readsUnknownValuesSafely() {
		System.Assert.isNull(ArchiveRules.of(null), 'No document, no rule');
		System.Assert.isNull(ArchiveRules.of('not json'), 'Not JSON, no rule');
		System.Assert.isNull(ArchiveRules.of(QUERY), 'No key, no rule');
		ArchiveRules.Rule read = ArchiveRules.of(
			'{"object":"Contact","archive":{"destination":"Moon","frequency":"hourly","active":false,"monthDay":4.0}}'
		);
		System.Assert.areEqual(ArchiveRules.FILES, read.destination, 'An unknown destination reads as Files');
		System.Assert.areEqual(ArchiveRules.OFF, read.frequency, 'An unknown frequency reads as off');
		System.Assert.isFalse(read.active, 'Active false is kept');
		System.Assert.areEqual(4, read.monthDay, 'A decimal day is read as a whole number');
		System.Assert.isFalse(read.scheduled(), 'Off and inactive is not scheduled');
	}

	@IsTest
	static void refusesRulesItCannotHold() {
		List<ArchiveRules.Rule> refused = new List<ArchiveRules.Rule>{
			rule('Moon', ArchiveRules.OFF, null, null),
			rule(ArchiveRules.FILES, 'hourly', null, null),
			rule(ArchiveRules.FILES, ArchiveRules.WEEKLY, 8, null),
			rule(ArchiveRules.FILES, ArchiveRules.WEEKLY, null, null),
			rule(ArchiveRules.FILES, ArchiveRules.MONTHLY, null, 29),
			rule(ArchiveRules.FILES, ArchiveRules.MONTHLY, null, 0)
		};
		for (ArchiveRules.Rule candidate : refused) {
			try {
				ArchiveRules.withRule(QUERY, candidate);
				System.Assert.fail('Should refuse ' + JSON.serialize(candidate));
			} catch (ArchiveRules.ArchiveRuleException expected) {
				System.Assert.isTrue(String.isNotBlank(expected.getMessage()), 'The refusal says why');
			}
		}
		try {
			ArchiveRules.withRule('nope', rule(ArchiveRules.FILES, ArchiveRules.OFF, null, null));
			System.Assert.fail('A document that is not JSON is refused');
		} catch (ArchiveRules.ArchiveRuleException expected) {
			System.Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Refused');
		}
	}

	@IsTest
	static void computesDueDays() {
		// 2026-11-23 is a Monday.
		Date monday = Date.newInstance(2026, 11, 23);
		System.Assert.areEqual(1, ArchiveRules.weekdayOf(monday), 'Monday is 1');
		System.Assert.areEqual(7, ArchiveRules.weekdayOf(monday.addDays(6)), 'Sunday is 7');

		ArchiveRules.Rule daily = rule(ArchiveRules.BIG_OBJECT, ArchiveRules.DAILY, null, null);
		System.Assert.isTrue(ArchiveRules.isDue(daily, monday), 'Daily is due every day');

		ArchiveRules.Rule weekly = rule(ArchiveRules.BIG_OBJECT, ArchiveRules.WEEKLY, 3, null);
		System.Assert.isFalse(ArchiveRules.isDue(weekly, monday), 'Weekly Wednesday is not due Monday');
		System.Assert.isTrue(ArchiveRules.isDue(weekly, monday.addDays(2)), 'Weekly Wednesday is due Wednesday');
		System.Assert.areEqual(monday.addDays(2), ArchiveRules.nextDue(weekly, monday), 'Next Wednesday');

		ArchiveRules.Rule monthly = rule(ArchiveRules.FILES, ArchiveRules.MONTHLY, null, 1);
		System.Assert.areEqual(Date.newInstance(2026, 12, 1), ArchiveRules.nextDue(monthly, monday), 'Next first');

		monthly.active = false;
		System.Assert.isFalse(ArchiveRules.isDue(monthly, Date.newInstance(2026, 12, 1)), 'Inactive is never due');
		System.Assert.isNull(ArchiveRules.nextDue(monthly, monday), 'Inactive has no next day');
		System.Assert.isFalse(
			ArchiveRules.isDue(rule(ArchiveRules.FILES, ArchiveRules.OFF, null, null), monday),
			'Off is never due'
		);
		System.Assert.isFalse(ArchiveRules.isDue(null, monday), 'No rule is never due');
	}

	@IsTest
	static void filesDestinationStartsArchiveByQuery() {
		String nobody = JSON.serialize(
			new Map<String, Object>{
				'version' => 1,
				'object' => 'Contact',
				'fields' => new List<Object>{ 'LastName' },
				'filter' => new Map<String, Object>{
					'version' => 1,
					'conditions' => new List<Object>{
						new Map<String, Object>{
							'id' => 1,
							'field' => 'Title',
							'operator' => 'equals',
							'value' => 'No Such Title Anywhere'
						}
					}
				}
			}
		);
		System.runAs(TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' })) {
			try {
				ArchiveDestinations.forKey(ArchiveRules.FILES).start(new ArchiveRun(null, 'Rule', nobody, 'Contact', 5));
				System.Assert.fail('Nothing matches, so Archive by Query refuses');
			} catch (BulkDeleteService.BulkDeleteException expected) {
				System.Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Its own refusal');
			}
		}
	}

	@IsTest
	static void resolvesDestinations() {
		System.Assert.areEqual(ArchiveRules.FILES, ArchiveDestinations.forKey(null).key(), 'Empty reads as Files');
		System.Assert.isNull(ArchiveDestinations.forKey(ArchiveRules.FILES).unavailableReason(), 'Files is usable');
		ArchiveDestination offPlatform = ArchiveDestinations.forKey(ArchiveRules.OFF_PLATFORM);
		System.Assert.areEqual(ArchiveRules.OFF_PLATFORM, offPlatform.key(), 'Off Platform is offered');
		if (Type.forName(ArchiveDestinations.OFF_PLATFORM_CLASS) == null) {
			System.Assert.isNotNull(offPlatform.unavailableReason(), 'Refused with a reason while none is installed');
			try {
				offPlatform.start(new ArchiveRun(null, 'Rule', QUERY, 'Contact', 1));
				System.Assert.fail('Starting a missing destination is refused');
			} catch (ArchiveRules.ArchiveRuleException expected) {
				System.Assert.areEqual(offPlatform.unavailableReason(), expected.getMessage(), 'Same reason');
			}
		}
		List<ArchiveDestinations.Choice> choices = ArchiveDestinations.choices();
		System.Assert.areEqual(ArchiveRules.DESTINATIONS.size(), choices.size(), 'One choice per destination');
		System.Assert.areEqual(ArchiveRules.FILES, choices[0].key, 'Files first');
		System.Assert.isTrue(String.isNotBlank(choices[0].label), 'Each has a label');
	}
}
