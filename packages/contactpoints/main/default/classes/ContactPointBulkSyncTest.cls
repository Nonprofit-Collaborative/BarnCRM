/**
 * Large saves (ADR-0176 decision 16): a save of more than `QUEUE_ABOVE` people has its sync
 * queued, and every person is still synced when the job runs; a smaller save is synced inside
 * it; the Automation page's switch still stops both. The sync's CPU is budgeted where it runs
 * inside the save (a background job's large save, an import chunk): 200 people, and an import
 * chunk of 200 couples within the import's own budget.
 *
 * Later: budget only Contact Point Sync's share, by timing the same insert with sync off.
 */
@IsTest(testFor='ApexClass:ContactPointSyncService')
private class ContactPointBulkSyncTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static Boolean ready() {
		return ContactPointSyncService.activeKinds().size() == 3;
	}

	private static List<Contact> people(Integer count, String prefix) {
		List<Contact> result = new List<Contact>();
		for (Integer i = 0; i < count; i++) {
			result.add(
				(Contact) TestDataFactory.pastDuplicateRules(
					new Contact(
						FirstName = 'Ana',
						LastName = prefix + i,
						Email = prefix.toLowerCase() + i + '@example.invalid',
						HomePhone = '555010' + i,
						MailingStreet = i + ' Main St',
						MailingCity = 'Springfield'
					)
				)
			);
		}
		return result;
	}

	private static Integer links() {
		return [SELECT COUNT() FROM Contact_Point_Link__c WITH SYSTEM_MODE];
	}

	@IsTest
	static void aLargeSaveIsQueuedAndEveryoneIsSynced() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			List<Contact> rows = people(ContactPointSyncService.QUEUE_ABOVE + 1, 'Large');

			Test.startTest();
			insert rows;
			Integer duringSave = links();
			Test.stopTest();

			Assert.areEqual(0, duringSave, 'Nothing copied inside the save');
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE],
				'Nothing failed'
			);
			Assert.areEqual(
				(ContactPointSyncService.QUEUE_ABOVE + 1) * 2,
				[
					SELECT COUNT()
					FROM Contact_Point_Link__c
					WHERE Kind__c IN ('Email', 'Phone')
					WITH SYSTEM_MODE
				],
				'The queued job copied every email and phone'
			);
			Assert.areEqual(
				ContactPointSyncService.QUEUE_ABOVE + 1,
				Database.countQuery(
					'SELECT COUNT() FROM Contact WHERE IndividualId != null AND LastName LIKE \'Large%\'',
					AccessLevel.SYSTEM_MODE
				),
				'Each has one Individual'
			);
		}
	}

	@IsTest
	static void aSmallSaveIsSyncedInsideIt() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			List<Contact> rows = people(ContactPointSyncService.QUEUE_ABOVE, 'Small');

			Test.startTest();
			insert rows;
			Integer duringSave = [
				SELECT COUNT()
				FROM Contact_Point_Link__c
				WHERE Kind__c IN ('Email', 'Phone')
				WITH SYSTEM_MODE
			];
			Test.stopTest();

			Assert.areEqual(
				ContactPointSyncService.QUEUE_ABOVE * 2,
				duringSave,
				'Copied in the same save, before any job runs'
			);
		}
	}

	@IsTest
	static void theAutomationSwitchStopsALargeSave() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			List<Contact> rows = people(ContactPointSyncService.QUEUE_ABOVE + 1, 'Off');
			AutomationControl.bypass('Contact_Point_Sync_Person');

			Test.startTest();
			insert rows;
			Test.stopTest();

			Assert.areEqual(
				0,
				[
					SELECT COUNT()
					FROM Contact_Point_Link__c
					WHERE Kind__c IN ('Email', 'Phone')
					WITH SYSTEM_MODE
				],
				'Switched off: nothing queued, nothing copied'
			);
		}
	}

	@IsTest
	static void twoHundredPeopleSyncedInsideTheSaveStayWithinBudget() {
		System.runAs(TestUsers.admin()) {
			if (!ready()) {
				return;
			}
			TestDataFactory.defaultSettings();
			// One person first, so the measured save is not charged for compiling the classes.
			insert people(1, 'Warm');
			List<Contact> rows = people(200, 'Budget');
			// Inside the save, as in a background job (an import's batch), which has no job to give.
			ContactPointSyncService.inlineForTest = true;

			Test.startTest();
			Integer before = Limits.getCpuTime();
			insert rows;
			Integer cpu = Limits.getCpuTime() - before;
			Integer copied = links();
			Test.stopTest();

			Assert.areEqual(1 * 3 + 200 * 3, copied, 'An email, phone and address each');
			// About 550 ms on an idle scratch org; 1,900 before decision 16 (a global describe
			// for every copy made). A quarter of the synchronous limit. An org with person
			// accounts gets 3,000: it runs the Account handlers and the person checks on every
			// household save. Measured 2026-11-09, Contact Point Sync's copy stages cost the same
			// on both shapes (address copies 316 ms on oi-test, 312 on barn-sales); the extra
			// was the person-account Account update and checks (2.6 to 2.7 s in all).
			Integer budget = HouseholdService.isPersonAccountOrg() ? 3000 : 2500;
			Assert.isTrue(cpu <= budget, 'CPU within budget (ms): ' + cpu + ' of ' + budget);
		}
	}

	@IsTest
	static void anImportChunkWithTheSyncInsideStaysWithinBudget() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.defaultSettings();
			ImportMapping mapping = new ImportMapping();
			List<ImportMapping.Column> columns = mapping.getColumns();
			columns.add(new ImportMapping.Column('Household', 'Household.Name'));
			columns.add(new ImportMapping.Column('First 1', 'Contact1.FirstName'));
			columns.add(new ImportMapping.Column('Last 1', 'Contact1.LastName'));
			columns.add(new ImportMapping.Column('Email 1', 'Contact1.Email'));
			columns.add(new ImportMapping.Column('First 2', 'Contact2.FirstName'));
			columns.add(new ImportMapping.Column('Last 2', 'Contact2.LastName'));
			columns.add(new ImportMapping.Column('Email 2', 'Contact2.Email'));
			columns.add(new ImportMapping.Column('Employer', 'Organization.Name'));
			Import_Template__c template = ImportTestDataFactory.template(
				mapping.serialize(),
				ImportTemplateService.RULE_EMAIL
			);
			Import_Batch__c batch = ImportTestDataFactory.batch(template);
			List<Map<String, String>> values = new List<Map<String, String>>();
			for (Integer i = 0; i < 200; i++) {
				values.add(
					new Map<String, String>{
						'Household' => 'The Family ' + i,
						'First 1' => 'Ana' + i,
						'Last 1' => 'Family' + i,
						'Email 1' => 'ana' +
						i +
						'@example.org',
						'First 2' => 'Ben' + i,
						'Last 2' => 'Family' + i,
						'Email 2' => 'ben' +
						i +
						'@example.org',
						'Employer' => 'Employer ' + Math.mod(i, 20)
					}
				);
			}
			ImportTestDataFactory.rows(batch, values);
			// An import runs as a batch job, whose one queueable job is not the sync's.
			ContactPointSyncService.inlineForTest = true;

			Test.startTest();
			ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
				batch,
				template,
				ImportMapping.parse(template.Column_Mapping_JSON__c),
				ImportTestDataFactory.reload(batch.Id),
				false
			);
			Integer queries = Limits.getQueries();
			Integer statements = Limits.getDmlStatements();
			Integer cpu = Limits.getCpuTime();
			Test.stopTest();

			Assert.areEqual(200, outcome.created, 'Every row loaded: ' + outcome.notes);
			if (ready()) {
				Assert.areEqual(
					400,
					[
						SELECT COUNT()
						FROM Contact_Point_Link__c
						WHERE Kind__c = 'Email'
						WITH SYSTEM_MODE
					],
					'Each new person\'s email copied inside the chunk'
				);
			}
			// The import's own budgets (ImportRowProcessorTest), with the sync inside.
			Assert.isTrue(queries <= 60, 'Queries within budget: ' + queries);
			Assert.isTrue(statements <= 60, 'DML statements within budget: ' + statements);
			Assert.isTrue(cpu <= 8000, 'CPU within budget (ms): ' + cpu);
		}
	}
}
