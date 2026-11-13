/**
 * The BarnCRM Automation Control setting (ADR-0165 dispatcher errors and Automation Control):
 * Pause All or Bypass for the person saving stops every BarnCRM automation that can be paused,
 * on a real Contact trigger, while an always-run rule still runs; the Check BarnCRM Automation
 * action gives an organization's own flow the same answer; and catching up never throws.
 */
@IsTest(testFor='ApexClass:AutomationControl')
private class AutomationControlSettingTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private static void registerCountingHandler(Boolean alwaysRuns) {
		Automation_Registry__mdt entry = TestDataFactory.registryEntry('Counting_Test', true);
		entry.Handler_Class__c = 'TestFailingHandler';
		entry.Object_Name__c = 'Contact';
		entry.Always_Runs__c = alwaysRuns;
		AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{ entry };
		TestFailingHandler.attempts = 0;
		TestFailingHandler.failIn = 'never';
	}

	private static void control(Id ownerId, Boolean pauseAll, Boolean bypass) {
		Database.insert(
			new BarnCRM_Automation_Control__c(
				SetupOwnerId = ownerId,
				Pause_All__c = pauseAll,
				Bypass__c = bypass
			),
			AccessLevel.SYSTEM_MODE
		);
	}

	private static void saveOnePerson() {
		Database.insert(
			TestDataFactory.person(new Contact(FirstName = 'Test', LastName = 'Avery')),
			true
		);
	}

	@IsTest
	static void bypassForThePersonSavingStopsBarnCrmAutomation() {
		User admin = TestUsers.admin();
		control(admin.Id, false, true);
		System.runAs(admin) {
			registerCountingHandler(false);

			Test.startTest();
			saveOnePerson();
			Test.stopTest();

			Assert.isTrue(AutomationControl.isOffForRunningUser(), 'Bypass applies to them.');
			Assert.areEqual(0, TestFailingHandler.attempts, 'A bypassed save runs no automation.');
		}
	}

	@IsTest
	static void pauseAllForEveryoneStopsBarnCrmAutomation() {
		control(UserInfo.getOrganizationId(), true, false);
		System.runAs(TestUsers.admin()) {
			registerCountingHandler(false);

			Test.startTest();
			saveOnePerson();
			Test.stopTest();

			Assert.isTrue(AutomationControl.isPausedForEveryone(), 'Paused for everyone.');
			Assert.areEqual(0, TestFailingHandler.attempts, 'A paused save runs no automation.');
		}
	}

	@IsTest
	static void anAlwaysRunsRuleStillRunsForABypassedPerson() {
		User admin = TestUsers.admin();
		control(admin.Id, true, true);
		System.runAs(admin) {
			registerCountingHandler(true);

			Test.startTest();
			saveOnePerson();
			Test.stopTest();

			Assert.areEqual(
				2,
				TestFailingHandler.attempts,
				'A rule that always runs runs before and after the save whatever the setting says.'
			);
		}
	}

	@IsTest
	static void withNoSettingAutomationRuns() {
		System.runAs(TestUsers.admin()) {
			registerCountingHandler(false);

			Test.startTest();
			saveOnePerson();
			Test.stopTest();

			Assert.isFalse(AutomationControl.isOffForRunningUser(), 'Nothing is set.');
			Assert.isFalse(AutomationControl.isPausedForEveryone(), 'Nothing is paused.');
			Assert.areEqual(2, TestFailingHandler.attempts, 'Automation runs before and after.');
		}
	}

	@IsTest
	static void theActionAnswersAFlowTheSameWay() {
		User admin = TestUsers.admin();
		System.runAs(admin) {
			TestDataFactory.insertAutomationSettings(
				new Map<String, Boolean>{ 'Flow:Test_Flow' => false }
			);
			CheckAutomationAction.Request listedOff = new CheckAutomationAction.Request();
			listedOff.automationName = 'Flow:Test_Flow';
			CheckAutomationAction.Request unnamed = new CheckAutomationAction.Request();

			Test.startTest();
			List<CheckAutomationAction.Result> answers = CheckAutomationAction.check(
				new List<CheckAutomationAction.Request>{ listedOff, unnamed }
			);
			Test.stopTest();

			Assert.isFalse(answers[0].run, 'A listed flow switched off does not run.');
			Assert.areEqual(CheckAutomationAction.REASON_SWITCHED_OFF, answers[0].reason, 'Why.');
			Assert.isTrue(answers[1].run, 'A flow with no name runs while nothing is paused.');
		}
	}

	@IsTest
	static void theActionSaysNoWhileBypassedOrPaused() {
		User admin = TestUsers.admin();
		control(admin.Id, false, true);
		System.runAs(admin) {
			Test.startTest();
			List<CheckAutomationAction.Result> bypassed = CheckAutomationAction.check(
				new List<CheckAutomationAction.Request>{ new CheckAutomationAction.Request() }
			);
			Test.stopTest();

			Assert.isFalse(bypassed[0].run, 'A bypassed person runs nothing.');
			Assert.areEqual(CheckAutomationAction.REASON_SETTING, bypassed[0].reason, 'Why.');
		}
	}

	@IsTest
	static void theActionSaysNoDuringTheTimedPause() {
		System.runAs(TestUsers.admin()) {
			TestDataFactory.pausedSettings(2);

			Test.startTest();
			List<CheckAutomationAction.Result> paused = CheckAutomationAction.check(
				new List<CheckAutomationAction.Request>{ new CheckAutomationAction.Request() }
			);
			Test.stopTest();

			Assert.isFalse(paused[0].run, 'Nothing runs during the timed pause.');
			Assert.areEqual(CheckAutomationAction.REASON_PAUSED, paused[0].reason, 'Why.');
			Assert.areEqual(
				0,
				CheckAutomationAction.check(null).size(),
				'No questions, no answers.'
			);
		}
	}

	@IsTest
	static void catchingUpQueuesTheWorkAndNeverThrows() {
		System.runAs(TestUsers.admin()) {
			Test.startTest();
			AutomationControl.catchUp(true);
			Test.stopTest();

			// A test may start only one batch, so the names recompute is refused and logged
			// here; what matters is that the household catch-up was queued and nothing threw.
			// One job, or two in an org that stores people as accounts.
			Assert.isTrue(
				[
					SELECT COUNT()
					FROM AsyncApexJob
					WHERE JobType = 'BatchApex' AND ApexClass.Name = 'HouseholdCatchUpBatch'
					WITH SYSTEM_MODE
				] >= 1,
				'The household catch-up is queued.'
			);
		}
	}
}
