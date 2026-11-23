/**
 * Archive rules (canonical model R-SQ18): the rule panel through its controller, the typed count
 * that turns a schedule on, the permission refusal, and the nightly step that starts due rules.
 *
 * The big object is replaced by `ArchiveStoreMemory`, and each link is run in turn by the test,
 * since an Apex test can neither write a big object nor chain queueables.
 */
@IsTest(testFor='ApexClass:ArchiveRuleService, ApexClass:ArchiveController, ApexClass:ArchiveRulesStep')
private class ArchiveRuleServiceTest {
	@TestSetup
	// runs-as: deploying user (creates the test users themselves)
	static void createUsers() {
		TestUsers.admin();
		archivist();
	}

	private static final String VOLUNTEERS = JSON.serialize(
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
						'value' => 'Volunteer'
					}
				}
			}
		}
	);

	private static User archivist() {
		return TestUsers.withPermissionSets(new List<String>{ TestUsers.CORE_ADMIN, 'BarnCRM_Bulk_Delete' });
	}

	/** Runs start without the backup before them (AR-15): these tests drive the archive alone. */
	private static void skipBackups() {
		BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
		settings.Skip_Backup_Before_Archive__c = true;
		TestDataFactory.saveSettings(settings);
	}

	private static void makePeople(Integer howMany) {
		DataProtectedFields.targetsOverride = new Map<String, Set<String>>();
		List<Contact> people = new List<Contact>{
			TestDataFactory.person(new Contact(LastName = 'Staff Person', Title = 'Staff'))
		};
		for (Integer index = 0; index < howMany; index++) {
			people.add(TestDataFactory.person(new Contact(LastName = 'Archived ' + index, Title = 'Volunteer')));
		}
		insert people;
	}

	/** Runs every queued link until the chain ends. */
	private static void drain() {
		Integer ran = 0;
		while (!BigObjectArchiveJob.queuedForTest.isEmpty()) {
			Queueable next = (Queueable) BigObjectArchiveJob.queuedForTest.remove(0);
			next.execute(null);
			ran++;
			System.Assert.isTrue(ran < 50, 'The chain ends');
		}
	}

	@IsTest
	static void rulePanelSavesPreviewsAndRuns() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
			skipBackups();
		}
		ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		System.runAs(archivist()) {
			Saved_Query__c query = new Saved_Query__c(
				Name = 'Volunteers',
				Object_Name__c = 'Contact',
				Query_JSON__c = VOLUNTEERS
			);
			insert as user query;
			ArchiveRuleService.Panel panel = ArchiveController.getRules();
			System.Assert.areEqual(1, panel.candidates.size(), 'The person own query is a candidate');
			System.Assert.areEqual(0, panel.rules.size(), 'No rule yet');
			System.Assert.areEqual(3, panel.destinations.size(), 'Three destinations');

			ArchiveRules.Rule weekly = new ArchiveRules.Rule();
			weekly.destination = ArchiveRules.BIG_OBJECT;
			weekly.frequency = ArchiveRules.WEEKLY;
			weekly.weekday = 2;
			try {
				ArchiveController.saveRule(query.Id, JSON.serialize(weekly), 5);
				System.Assert.fail('Turning a schedule on needs the current count');
			} catch (AuraHandledException expected) {
				System.Assert.isTrue(expected.getMessage().contains('2'), 'Names the count: ' + expected.getMessage());
			}
			panel = ArchiveController.saveRule(query.Id, JSON.serialize(weekly), 2);
			System.Assert.areEqual(1, panel.rules.size(), 'Now a rule');
			System.Assert.areEqual(ArchiveRules.WEEKLY, panel.rules[0].rule.frequency, 'Weekly');
			System.Assert.isNotNull(panel.rules[0].nextRun, 'A next run day');

			BulkDeleteService.Preview preview = ArchiveController.previewRule(query.Id);
			System.Assert.areEqual(2, preview.count, 'The preview counts');

			// The run and what follows get their own limits, as a person's later clicks would.
			Test.startTest();
			panel = ArchiveController.runRule(query.Id, 2);
			drain();
			panel = ArchiveController.getRules();
			System.Assert.areEqual(1, panel.runs.size(), 'The run is listed');
			System.Assert.areEqual(2, panel.runs[0].moved, 'Two moved');
			System.Assert.areEqual(2, panel.archivedCount, 'Counted');

			panel = ArchiveController.saveRule(query.Id, null, null);
			System.Assert.areEqual(0, panel.rules.size(), 'Taken off');
			try {
				ArchiveController.runRule(query.Id, 1);
				System.Assert.fail('Not a rule any more');
			} catch (AuraHandledException expected) {
				System.Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Refused');
			}
			Test.stopTest();
		}
	}

	@IsTest
	static void aRuleStillRunningIsNotStartedAgain() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
			skipBackups();
		}
		ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		String running = BarnHelp.text('Core', 'Core_ArchiveRules_ErrorRunning');
		System.runAs(archivist()) {
			ArchiveRules.Rule settings = new ArchiveRules.Rule();
			settings.destination = ArchiveRules.BIG_OBJECT;
			Saved_Query__c query = new Saved_Query__c(
				Name = 'Old Volunteers',
				Object_Name__c = 'Contact',
				Query_JSON__c = ArchiveRules.withRule(VOLUNTEERS, settings)
			);
			insert as user query;
			Test.startTest();
			ArchiveRuleService.Panel panel = ArchiveController.runRule(query.Id, 2);
			System.Assert.isTrue(panel.rules[0].running, 'The panel knows the rule is running');
			try {
				ArchiveController.runRule(query.Id, 2);
				System.Assert.fail('A second Run Now waits for the first');
			} catch (AuraHandledException expected) {
				System.Assert.isTrue(expected.getMessage().contains(running), expected.getMessage());
			}
			System.Assert.isFalse(ArchiveRuleService.runDueRule(query.Id), 'The nightly run does not start it either');
			try {
				new ArchiveToBigObject().start(new ArchiveRun(query.Id, query.Name, query.Query_JSON__c, 'Contact', 2));
				System.Assert.fail('Nor the destination itself');
			} catch (ArchiveRules.ArchiveRuleException expected) {
				System.Assert.areEqual(running, expected.getMessage(), 'In plain words');
			}
			drain();
			System.Assert.isFalse(ArchiveController.getRules().rules[0].running, 'Free once the run ends');
			Test.stopTest();
		}
	}

	@IsTest
	static void refusesPeopleWithoutThePermissions() {
		System.runAs(TestUsers.standardUserWith('Staff', new List<String>{ 'BarnCRM_Staff' })) {
			try {
				ArchiveController.getRules();
				System.Assert.fail('Staff may not use archive rules');
			} catch (AuraHandledException expected) {
				System.Assert.isTrue(String.isNotBlank(expected.getMessage()), 'Refused with a reason');
			}
		}
	}

	@IsTest
	static void nightlyStepStartsDueRules() {
		System.runAs(TestUsers.admin()) {
			makePeople(2);
			skipBackups();
		}
		ArchiveStoreMemory store = ArchiveStoreMemory.install();
		BigObjectArchiveJob.queuedForTest = new List<Object>();
		System.runAs(archivist()) {
			ArchiveRules.Rule settings = new ArchiveRules.Rule();
			settings.destination = ArchiveRules.BIG_OBJECT;
			settings.frequency = ArchiveRules.DAILY;
			Saved_Query__c query = new Saved_Query__c(
				Name = 'Old Volunteers',
				Object_Name__c = 'Contact',
				Query_JSON__c = ArchiveRules.withRule(VOLUNTEERS, settings)
			);
			insert as user query;
			System.Assert.areEqual(
				new Set<Id>{ query.Id },
				ArchiveRuleService.dueRuleIds(OrgDate.today()),
				'Due daily'
			);
			NightlyStep step = ArchiveRulesStep.step();
			System.Assert.areEqual(ArchiveRulesStep.JOB_NAME, step.key, 'The step key');
			System.Assert.isTrue(step.hasSwitch(), 'The step has a switch');
			// The step starts a batch of the due rules; each chunk starts one rule's run.
			Test.startTest();
			step.run();
			Test.stopTest();
			drain();
		}
		System.Assert.areEqual(2, store.rowsByKey.size(), 'The daily rule ran');
		System.Assert.areEqual(1, [SELECT COUNT() FROM Contact WITH SYSTEM_MODE], 'Its records went');
		System.runAs(archivist()) {
			Id ruleId = [SELECT Id FROM Saved_Query__c WITH SYSTEM_MODE LIMIT 1].Id;
			System.Assert.isFalse(ArchiveRuleService.runDueRule(ruleId), 'Nothing matches now');
		}
	}
}
