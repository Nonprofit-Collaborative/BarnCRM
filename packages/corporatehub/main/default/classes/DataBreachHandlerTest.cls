/**
 * Maria logs a personal data breach and its owner is told at once, not at the next 6:45 AM run,
 * and the nightly run sends no second bell for it (CH-22, D-196; R-DB1).
 */
@IsTest(testFor='ApexClass:DataBreachHandler, ApexClass:HubReminders')
private class DataBreachHandlerTest {
	private static final String ADMIN_SET = 'Corporate_Hub_Admin';

	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith(ADMIN_SET);
	}

	private static Data_Breach__c breach(String name, String risk) {
		return new Data_Breach__c(
			Name = name,
			Status__c = 'Open',
			Risk__c = risk,
			Discovered_At__c = Datetime.now()
		);
	}

	private static Map<Id, Data_Breach__c> reload(List<Data_Breach__c> rows) {
		return new Map<Id, Data_Breach__c>(
			[
				SELECT Id, Reminded_For__c
				FROM Data_Breach__c
				WHERE Id IN :rows
				WITH USER_MODE
			]
		);
	}

	@IsTest
	static void aLoggedBreachSendsOneBellAndTheNightlyRunSendsNone() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Data_Breach__c row = breach('Lost laptop', 'Not Yet Assessed');
			insert as user row;

			Assert.areEqual(1, HubReminders.sentTitles.size(), 'One bell on insert');
			Assert.isTrue(HubReminders.sentTitles[0].contains('Lost laptop'), 'Names the breach');
			Date deadline = Date.today().addDays(3);
			Assert.isTrue(
				HubReminders.sentTitles[0].contains(deadline.format()),
				'Carries the deadline date'
			);
			Assert.areEqual(
				deadline,
				reload(new List<Data_Breach__c>{ row }).get(row.Id).Reminded_For__c,
				'The deadline date is stored'
			);

			new HubReminders().execute(null);

			Assert.areEqual(1, HubReminders.sentTitles.size(), 'No second bell the same day');
		}
	}

	@IsTest
	static void aBreachNobodyNeedsRemindedOfGetsNoBell() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			Data_Breach__c unlikely = breach('Misdirected email', 'Unlikely');
			Data_Breach__c reported = breach('Stolen phone', 'Risk');
			reported.Authority_Notified_At__c = Datetime.now();
			insert as user new List<Data_Breach__c>{ unlikely, reported };

			Assert.isTrue(HubReminders.sentTitles.isEmpty(), 'Nothing to report, nothing sent');
			Assert.isNull(
				reload(new List<Data_Breach__c>{ unlikely, reported })
					.get(unlikely.Id)
					.Reminded_For__c,
				'Not stamped'
			);
		}
	}

	@IsTest
	static void theBellFollowsTheRemindersSwitch() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			insert new Corporate_Hub_Settings__c(
				SetupOwnerId = UserInfo.getOrganizationId(),
				Reminders_Enabled__c = false
			);
			Data_Breach__c row = breach('Lost laptop', 'Risk');
			insert as user row;
			Assert.isTrue(HubReminders.sentTitles.isEmpty(), 'Reminders off: no bell');
			Assert.isNull(
				reload(new List<Data_Breach__c>{ row }).get(row.Id).Reminded_For__c,
				'Not stamped, so the nightly run still reminds once reminders are on'
			);
		}
	}

	@IsTest
	static void twoHundredBreachesStayWithinLimitsAndTheNightlyRunSendsTheRest() {
		System.runAs(TestUsers.adminWith(ADMIN_SET)) {
			List<Data_Breach__c> rows = new List<Data_Breach__c>();
			for (Integer i = 0; i < 200; i++) {
				rows.add(breach('Breach ' + i, 'Risk'));
			}
			insert as user rows;

			Assert.areEqual(
				HubReminders.MAX_LOGGED_BELLS,
				HubReminders.sentTitles.size(),
				'Bells on insert stop at the cap'
			);
			Integer stamped = 0;
			for (Data_Breach__c row : reload(rows).values()) {
				stamped += row.Reminded_For__c == null ? 0 : 1;
			}
			Assert.areEqual(HubReminders.MAX_LOGGED_BELLS, stamped, 'Only those told are stamped');

			HubReminders.maxReminders = 25;
			new HubReminders().execute(null);

			Assert.areEqual(
				HubReminders.MAX_LOGGED_BELLS + 25,
				HubReminders.sentTitles.size(),
				'The nightly run tells others, never the same breach twice'
			);
		}
	}
}
