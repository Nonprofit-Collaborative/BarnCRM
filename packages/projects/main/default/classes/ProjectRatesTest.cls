/**
 * Rate cards (PM-06, R-PM9): a person's rate beats their role's, which beats the project's
 * Hourly Rate, bill and cost separately; the rate stays on the entry when a card changes; a
 * change of date re-prices an entry that is not yet approved; Apply Rates fills older entries;
 * and with rate cards off nothing is written.
 */
@IsTest(
	testFor='ApexClass:ProjectRates, ApexClass:ProjectEntryHandler, ApexTrigger:TimeEntryTrigger'
)
private class ProjectRatesTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ProjectsTestData.ADMIN_SET);
	}

	private static void turnOn(Map<String, Object> settings) {
		SettingsService.saveValues('Projects_Settings__c', settings);
	}

	private static Time_Entry__c entry(Id projectId, Id personId, Date day, Decimal hours) {
		return new Time_Entry__c(
			Project__c = projectId,
			User__c = personId,
			Date__c = day,
			Hours__c = hours,
			Billable__c = true
		);
	}

	private static Time_Entry__c read(Id id) {
		return [
			SELECT Bill_Rate__c, Cost_Rate__c, Amount__c, Status__c
			FROM Time_Entry__c
			WHERE Id = :id
			WITH SYSTEM_MODE
		];
	}

	/** A project at 100 an hour, a Developer role card (150, cost 80) and a person card (175, no cost). */
	private static Project__c cards(User developer) {
		Project__c project = ProjectsTestData.project('Active', null);
		insert new Project_Assignment__c(
			Project__c = project.Id,
			Resource__c = developer.Id,
			Role__c = 'Developer',
			Planned_Hours__c = 40
		);
		insert new List<Project_Rate__c>{
			new Project_Rate__c(
				Role__c = 'Developer',
				Bill_Rate__c = 150,
				Cost_Rate__c = 80,
				Effective_From__c = Date.today().addDays(-90)
			),
			new Project_Rate__c(
				User__c = developer.Id,
				Bill_Rate__c = 175,
				Effective_From__c = Date.today().addDays(-30),
				Effective_To__c = Date.today().addDays(30)
			)
		};
		return project;
	}

	@IsTest
	static void aPersonBeatsTheRoleWhichBeatsTheProjectAndCostIsResolvedSeparately() {
		User developer = ProjectsTestData.staff('Developer');
		System.runAs(ProjectsTestData.admin()) {
			turnOn(new Map<String, Object>{ 'Rates_Enabled__c' => true });
			Project__c project = cards(developer);
			Time_Entry__c now = entry(project.Id, developer.Id, Date.today(), 2);
			Time_Entry__c before = entry(project.Id, developer.Id, Date.today().addDays(-45), 2);
			Time_Entry__c other = entry(project.Id, UserInfo.getUserId(), Date.today(), 2);

			Test.startTest();
			insert new List<Time_Entry__c>{ now, before, other };
			Test.stopTest();

			Assert.areEqual(175, read(now.Id).Bill_Rate__c, 'The person card covers today');
			Assert.areEqual(
				80,
				read(now.Id).Cost_Rate__c,
				'No cost on the person card: the role cost'
			);
			Assert.areEqual(350, read(now.Id).Amount__c, 'Hours times bill rate');
			Assert.areEqual(150, read(before.Id).Bill_Rate__c, 'Before the person card: the role');
			Assert.areEqual(80, read(before.Id).Cost_Rate__c, 'The role cost');
			Assert.areEqual(100, read(other.Id).Bill_Rate__c, 'No card: the project Hourly Rate');
			Assert.isNull(read(other.Id).Cost_Rate__c, 'The project rate has no cost');
		}
	}

	@IsTest
	static void aCardChangeDoesNotRepriceButADateChangeDoesUntilApproved() {
		User developer = ProjectsTestData.staff('Developer');
		System.runAs(ProjectsTestData.admin()) {
			turnOn(new Map<String, Object>{ 'Rates_Enabled__c' => true });
			Project__c project = cards(developer);
			Time_Entry__c logged = entry(project.Id, developer.Id, Date.today(), 4);
			insert logged;
			update new Project_Rate__c(
				Id = [
					SELECT Id
					FROM Project_Rate__c
					WHERE User__c = :developer.Id
					WITH SYSTEM_MODE
				]
				.Id,
				Bill_Rate__c = 999
			);
			Assert.areEqual(175, read(logged.Id).Bill_Rate__c, 'A card change leaves the entry');

			update new Time_Entry__c(Id = logged.Id, Date__c = Date.today().addDays(-45));
			Assert.areEqual(150, read(logged.Id).Bill_Rate__c, 'A new date is priced again');

			update new Time_Entry__c(Id = logged.Id, Status__c = 'Approved');
			update new Time_Entry__c(Id = logged.Id, Date__c = Date.today());
			Assert.areEqual(150, read(logged.Id).Bill_Rate__c, 'Approved time keeps its rate');
		}
	}

	@IsTest
	static void nothingIsWrittenWhileRateCardsAreOff() {
		User developer = ProjectsTestData.staff('Developer');
		System.runAs(ProjectsTestData.admin()) {
			Project__c project = cards(developer);
			List<Time_Entry__c> entries = new List<Time_Entry__c>();
			for (Integer i = 0; i < 5; i++) {
				entries.add(entry(project.Id, developer.Id, Date.today(), 1));
			}
			insert entries;
			Time_Entry__c saved = read(entries[0].Id);
			Assert.isNull(saved.Bill_Rate__c, 'No rate with rate cards off');
			Assert.isNull(saved.Status__c, 'No status with approvals off');
			Assert.areEqual(
				5,
				[SELECT Actual_Hours__c FROM Project__c WHERE Id = :project.Id WITH SYSTEM_MODE]
				.Actual_Hours__c,
				'Hours count as before'
			);
		}
	}

	@IsTest
	static void twoHundredEntriesAreStampedTogether() {
		User developer = ProjectsTestData.staff('Developer');
		System.runAs(ProjectsTestData.admin()) {
			turnOn(new Map<String, Object>{ 'Rates_Enabled__c' => true });
			Project__c project = cards(developer);
			List<Time_Entry__c> entries = new List<Time_Entry__c>();
			for (Integer i = 0; i < 200; i++) {
				entries.add(
					entry(
						project.Id,
						i < 100 ? developer.Id : UserInfo.getUserId(),
						Date.today(),
						1
					)
				);
			}

			Test.startTest();
			insert entries;
			Test.stopTest();

			Assert.areEqual(
				100,
				[SELECT COUNT() FROM Time_Entry__c WHERE Bill_Rate__c = 175 WITH SYSTEM_MODE],
				'The developer\'s hundred at the person rate'
			);
			Assert.areEqual(
				100,
				[SELECT COUNT() FROM Time_Entry__c WHERE Bill_Rate__c = 100 WITH SYSTEM_MODE],
				'The others at the project rate'
			);
		}
	}

	@IsTest
	static void applyRatesFillsOlderEntriesIncludingApprovedOnesAndNeedsManageProjects() {
		User developer = ProjectsTestData.staff('Developer');
		Project__c project;
		List<Time_Entry__c> older = new List<Time_Entry__c>();
		System.runAs(ProjectsTestData.admin()) {
			project = cards(developer);
			for (Integer i = 0; i < 3; i++) {
				older.add(entry(project.Id, developer.Id, Date.today(), 1));
			}
			insert older;
			update new Time_Entry__c(Id = older[0].Id, Status__c = 'Approved');
			turnOn(new Map<String, Object>{ 'Rates_Enabled__c' => true });

			Integer filled = ProjectRates.applyRates();

			Assert.areEqual(3, filled, 'Every entry without a rate');
			Assert.areEqual(
				175,
				read(older[0].Id).Bill_Rate__c,
				'Approved time gets its first rate'
			);
			Assert.areEqual(175, read(older[2].Id).Bill_Rate__c, 'Open time too');
			Assert.areEqual(0, ProjectRates.applyRates(), 'A second run finds none');
		}
		System.runAs(developer) {
			try {
				ProjectRates.applyRates();
				Assert.fail('Staff cannot apply rates');
			} catch (Projects.ProjectsException refused) {
				Assert.isTrue(
					refused.getMessage().contains('Manage Projects'),
					refused.getMessage()
				);
			}
		}
	}
}
