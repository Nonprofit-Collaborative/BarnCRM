/**
 * The nightly rollup run that covers only what can have changed (D-200 P1). Core holds no giving
 * objects, so these count people onto their organization, which runs the same code the giving
 * totals run.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupNightlyBatch')
private class RollupNightlyBatchTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Rollup_Builder_Admin');
	}

	/** People per organization, Both, calculated before, optionally with a source filter. */
	private static Rollup_Definition__c peopleCount(String filter) {
		return new Rollup_Definition__c(
			Name = 'People per organization',
			Definition_Key__c = 'Test_Nightly_People',
			Source_Object__c = 'Contact',
			Relationship_Path__c = 'AccountId',
			Aggregate__c = 'COUNT',
			Target_Object__c = 'Account',
			Target_Field__c = 'NumberOfEmployees',
			Mode__c = RollupService.MODE_BOTH,
			Fiscal_Year_Aware__c = false,
			Filter_JSON__c = filter,
			Last_Calculated__c = Datetime.now().addDays(-1),
			Active__c = true
		);
	}

	private static String filter(String field, String operator, Object value) {
		return JSON.serialize(
			new Map<String, Object>{
				'version' => 1,
				'conditions' => new List<Object>{
					new Map<String, Object>{
						'id' => 1,
						'field' => field,
						'operator' => operator,
						'value' => value
					}
				}
			}
		);
	}

	/** Organizations of `people` people each, with what their saves queued cleared. */
	private static List<Account> organizations(Integer count, Integer people, Date birthdate) {
		Id organizationType = AccountKindsTestData.organizationRecordTypeId();
		List<Account> organizations = new List<Account>();
		for (Integer i = 0; i < count; i++) {
			organizations.add(
				TestDataFactory.organization(
					new Account(Name = 'Organization ' + i, RecordTypeId = organizationType)
				)
			);
		}
		insert organizations;
		List<Contact> contacts = new List<Contact>();
		for (Account organization : organizations) {
			for (Integer j = 0; j < people; j++) {
				contacts.add(
					TestDataFactory.person(
						new Contact(
							LastName = 'Person ' + j,
							AccountId = organization.Id,
							Birthdate = birthdate
						)
					)
				);
			}
		}
		insert contacts;
		clearQueue();
		return organizations;
	}

	private static void clearQueue() {
		Database.delete([SELECT Id FROM Rollup_Queue__c WITH SYSTEM_MODE], AccessLevel.SYSTEM_MODE);
	}

	/** Every record id the queue holds for an entity. */
	private static Set<Id> queued(String target) {
		Set<Id> ids = new Set<Id>();
		for (Rollup_Queue__c entry : [
			SELECT Record_Ids__c
			FROM Rollup_Queue__c
			WHERE Target_Object__c = :target
			WITH SYSTEM_MODE
		]) {
			ids.addAll(RollupQueue.idsOf(entry));
		}
		return ids;
	}

	private static Set<Id> idsOf(List<Account> organizations) {
		return new Map<Id, Account>(organizations).keySet();
	}

	private static RollupNightlyBatch.Plan runPlan(
		List<Rollup_Definition__c> definitions,
		Datetime since
	) {
		RollupNightlyBatch.Plan plan = RollupNightlyBatch.plan(definitions, since);
		if (!plan.passes.isEmpty()) {
			new RollupNightlyBatch(plan, 0).runInline();
		}
		return plan;
	}

	private static void storeSettings(String day, Datetime coveredFrom) {
		Rollup_Settings__c settings = Rollup_Settings__c.getOrgDefaults();
		settings.Full_Recalc_Day__c = day;
		settings.Nightly_Covered_From__c = coveredFrom;
		Database.upsert(settings, AccessLevel.SYSTEM_MODE);
		SettingsService.clearCaches();
	}

	/** Bulk: 200 organizations whose people changed since the last run are each queued once. */
	@IsTest
	static void theTargetsOfEveryRecordChangedSinceTheLastRunAreQueued() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Rollup_Definition__c definition = peopleCount(null);
			insert definition;
			List<Account> organizations = organizations(200, 2, null);

			Test.startTest();
			RollupNightlyBatch.Plan plan = runPlan(
				new List<Rollup_Definition__c>{ definition },
				Datetime.now().addHours(-1)
			);

			Assert.areEqual(1, plan.passes.size(), 'One pass, over the people');
			Assert.isTrue(plan.everywhere.isEmpty(), 'Nothing needs every record tonight');
			Assert.areEqual(idsOf(organizations), queued('Account'), 'Every organization queued');
			Assert.isNotNull(RollupNightlyBatch.coveredFrom(), 'The night is covered');
		}
	}

	/** Nothing saved since the last run: nothing is queued, and the night is still covered. */
	@IsTest
	static void aQuietNightQueuesNothing() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Rollup_Definition__c definition = peopleCount(null);
			insert definition;
			organizations(20, 2, null);
			Datetime since = Datetime.now().addMinutes(5);

			Test.startTest();
			RollupNightlyBatch.Plan plan = runPlan(
				new List<Rollup_Definition__c>{ definition },
				since
			);

			Assert.isTrue(queued('Account').isEmpty(), 'Nothing changed, nothing queued');
			Assert.isTrue(plan.passes[0].edges.isEmpty(), 'No window, no edges');
			Assert.isNotNull(RollupNightlyBatch.coveredFrom(), 'Covered');
		}
	}

	/** People deleted since the last run take their organization's total with them. */
	@IsTest
	static void aDeletedRecordQueuesItsTarget() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Rollup_Definition__c definition = peopleCount(null);
			insert definition;
			List<Account> organizations = organizations(3, 1, null);
			Datetime since = Datetime.now().addMinutes(-5);
			delete [SELECT Id FROM Contact WHERE AccountId = :organizations[0].Id];
			clearQueue();

			Test.startTest();
			runPlan(new List<Rollup_Definition__c>{ definition }, since);

			Assert.isTrue(queued('Account').contains(organizations[0].Id), 'Deleted counted');
		}
	}

	/**
	 * In the last 30 days: a person dated 30 days ago has just left the window, so their
	 * organization is queued though nobody saved them; one dated 100 days ago is not.
	 */
	@IsTest
	static void aRecordLeavingALastNDaysWindowQueuesItsTarget() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Rollup_Definition__c definition = peopleCount(filter('Birthdate', 'last n days', 30));
			insert definition;
			List<Account> leaving = organizations(2, 1, Date.today().addDays(-30));
			List<Account> farOut = organizations(2, 1, Date.today().addDays(-100));
			// Later than every save, so only the window brings anybody in.
			Datetime since = Datetime.now().addMinutes(5);

			Test.startTest();
			RollupNightlyBatch.Plan plan = runPlan(
				new List<Rollup_Definition__c>{ definition },
				since
			);

			Assert.areEqual(2, plan.passes[0].edges.size(), 'The leaving and arriving edges');
			Set<Id> ids = queued('Account');
			Assert.isTrue(ids.containsAll(idsOf(leaving)), 'Left the window: queued');
			Assert.isFalse(ids.contains(farOut[0].Id), 'Long out of the window: not queued');
		}
	}

	/** Which definitions need every record tonight. */
	@IsTest
	static void definitionsTheChangesCannotCoverRunEverywhere() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Integer month = RollupDateWindow.fiscalYearStartMonth();
			Date fiscalStart = Date.newInstance(2026, month, 1);
			RollupNightlyBatch.todayOverride = fiscalStart.addDays(40);
			Datetime since = Datetime.newInstance(
				fiscalStart.addDays(39),
				Time.newInstance(2, 0, 0, 0)
			);

			Rollup_Definition__c scheduled = peopleCount(null);
			scheduled.Mode__c = RollupService.MODE_SCHEDULED;
			Rollup_Definition__c neverRun = peopleCount(null);
			neverRun.Last_Calculated__c = null;
			Rollup_Definition__c deleted = peopleCount(null);
			deleted.Include_Deleted__c = true;
			Rollup_Definition__c targetFilter = peopleCount(null);
			targetFilter.Target_Filter_JSON__c = filter('CreatedDate', 'this year', null);
			Rollup_Definition__c notADate = peopleCount(filter('LastName', 'last n days', 30));
			Rollup_Definition__c fiscal = peopleCount(null);
			fiscal.Fiscal_Year_Aware__c = true;
			fiscal.Fiscal_Date_Field__c = 'Birthdate';
			Rollup_Definition__c thisYear = peopleCount(filter('Birthdate', 'this year', null));
			Rollup_Definition__c window = peopleCount(filter('Birthdate', 'last n days', 7));

			List<Rollup_Definition__c> all = new List<Rollup_Definition__c>{
				scheduled,
				neverRun,
				deleted,
				targetFilter,
				notADate,
				fiscal,
				thisYear,
				window
			};
			RollupNightlyBatch.Plan midYear = RollupNightlyBatch.plan(all, since);
			Assert.areEqual(5, midYear.everywhere.size(), 'The first five need every record');
			Assert.areEqual(3, midYear.passes[0].definitions.size(), 'Fiscal, year, window');

			// The first night of a fiscal year, which is also a new calendar year in January.
			RollupNightlyBatch.todayOverride = fiscalStart;
			Datetime lastYear = Datetime.newInstance(
				fiscalStart.addDays(-1),
				Time.newInstance(2, 0, 0, 0)
			);
			RollupNightlyBatch.Plan turnover = RollupNightlyBatch.plan(all, lastYear);
			Assert.isTrue(turnover.everywhere.contains(fiscal), 'A new fiscal year: everywhere');
			Assert.areEqual(
				month == 1,
				turnover.everywhere.contains(thisYear),
				'This year moves only with the calendar year'
			);
		}
	}

	/** The night of the full recalculation, from the setting; blank means Sunday. */
	@IsTest
	static void theFullNightFollowsTheSetting() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			// 2026-11-11 is a Wednesday, 2026-11-15 a Sunday.
			RollupNightlyBatch.todayOverride = Date.newInstance(2026, 11, 11);
			storeSettings('Wednesday', null);
			Assert.isTrue(RollupNightlyBatch.isFullNight(), 'Wednesday, set to Wednesday');
			storeSettings('Monday', null);
			Assert.isFalse(RollupNightlyBatch.isFullNight(), 'Wednesday, set to Monday');
			storeSettings(RollupNightlyBatch.EVERY_NIGHT, null);
			Assert.isTrue(RollupNightlyBatch.isFullNight(), 'Every night');
			storeSettings('Someday', null);
			Assert.areEqual('Sunday', RollupNightlyBatch.fullRecalcDay(), 'Unknown means Sunday');
			RollupNightlyBatch.todayOverride = Date.newInstance(2026, 11, 15);
			Assert.isTrue(RollupNightlyBatch.isFullNight(), 'Sunday by default');
		}
	}

	/** The first night, with nothing covered yet, recalculates everything and covers it. */
	@IsTest
	static void theFirstNightRecalculatesEverythingAndIsCovered() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Rollup_Definition__c definition = peopleCount(null);
			insert definition;
			List<Account> organizations = organizations(3, 2, null);
			storeSettings('Monday', null);

			Test.startTest();
			Id started = RollupNightlyBatch.begin(new List<Rollup_Definition__c>{ definition });
			Test.stopTest();

			Assert.isNotNull(started, 'The full run started');
			Assert.areEqual(
				2,
				[SELECT NumberOfEmployees FROM Account WHERE Id = :organizations[0].Id]
				.NumberOfEmployees,
				'Counted by the full run'
			);
			Assert.isNotNull(RollupNightlyBatch.coveredFrom(), 'The full run covered the night');
		}
	}

	/** A pass with a stopped chunk leaves the night uncovered, so tomorrow covers it again. */
	@IsTest
	static void aStoppedChunkLeavesTheNightUncovered() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			Rollup_Definition__c definition = peopleCount(null);
			insert definition;
			organizations(2, 1, null);
			RollupNightlyBatch.Plan plan = RollupNightlyBatch.plan(
				new List<Rollup_Definition__c>{ definition },
				Datetime.now().addHours(-1)
			);
			plan.stopped = 1;

			Test.startTest();
			new RollupNightlyBatch(plan, 0).runInline();

			Assert.isNull(RollupNightlyBatch.coveredFrom(), 'Not covered');
		}
	}

	/** Every night retries Failed entries and releases held ones. */
	@IsTest
	static void everyNightRetriesFailedAndReleasesHeldEntries() {
		System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
			storeSettings('Monday', Datetime.now().addDays(-1));
			RollupNightlyBatch.todayOverride = Date.newInstance(2026, 11, 11);
			List<Rollup_Queue__c> entries = new List<Rollup_Queue__c>{
				new Rollup_Queue__c(
					Target_Object__c = 'Account',
					Record_Ids__c = '001000000000001',
					Status__c = RollupQueue.STATUS_FAILED,
					Attempts__c = RollupQueue.MAX_ATTEMPTS
				),
				new Rollup_Queue__c(
					Target_Object__c = 'Account',
					Record_Ids__c = '001000000000002',
					Status__c = RollupQueue.STATUS_PENDING,
					Attempts__c = 1,
					Next_Attempt__c = Datetime.now().addHours(1)
				)
			};
			Database.insert(entries, AccessLevel.SYSTEM_MODE);

			// No Test.stopTest: the processor it asks for would work the entries away.
			RollupNightlyBatch.begin(new List<Rollup_Definition__c>());

			List<Rollup_Queue__c> after = [
				SELECT Status__c, Next_Attempt__c
				FROM Rollup_Queue__c
				WHERE Id IN :entries
				WITH SYSTEM_MODE
			];
			Assert.areEqual(2, after.size(), 'Both entries still queued');
			for (Rollup_Queue__c entry : after) {
				Assert.areEqual(RollupQueue.STATUS_PENDING, entry.Status__c, 'Pending again');
				Assert.isNull(entry.Next_Attempt__c, 'Due now');
			}
		}
	}
}
