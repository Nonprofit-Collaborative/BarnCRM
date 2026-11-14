/**
 * The nightly donor level pass re-places every donor only when something no save announces can
 * have moved them, and otherwise rescores only the donors crossing a recency cutoff (D-200 P1).
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:DonorLevelSchedulable')
private class DonorLevelSchedulableTest {
	@TestSetup
	static void createTestUser() {
		TestUsers.adminWith('Giving_Admin');
	}

	/** A time after every record the test made, so only what the test changes later counts. */
	private static Datetime afterSetup() {
		return Datetime.now().addSeconds(2);
	}

	@IsTest
	static void noRecordedRecalculationOrAWeekGoneByMeansEveryDonor() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Assert.isTrue(DonorLevelSchedulable.needsFullPass(null), 'Never recalculated');
			Assert.isTrue(
				DonorLevelSchedulable.needsFullPass(Datetime.now().addDays(-8)),
				'Older than a week'
			);
		}
	}

	@IsTest
	static void aQuietNightNeedsNoFullPassAndALadderChangeDoes() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			insert new Donor_Level__c(Name = 'Friend', Minimum_Amount__c = 100);
			// Recalculated after every save the test made, today: nothing has moved since.
			Datetime last = afterSetup();
			Assert.isFalse(DonorLevelSchedulable.needsFullPass(last), 'Nothing changed');

			Donor_Level__c rung = [SELECT Id FROM Donor_Level__c LIMIT 1];
			rung.Minimum_Amount__c = 150;
			update rung;
			Assert.isTrue(
				DonorLevelSchedulable.needsFullPass(Datetime.now().addSeconds(-5)),
				'A ladder change re-places everyone'
			);
		}
	}

	@IsTest
	static void aDonorSettingChangeMeansEveryDonor() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Datetime last = Datetime.now().addSeconds(-5);
			Database.insert(
				new Setting_Change__c(
					Setting_Name__c = 'Giving_Settings__c.Donor_Score_Recency_Days__c',
					New_Value__c = '60,120,365,730',
					Changed_At__c = Datetime.now()
				),
				AccessLevel.SYSTEM_MODE
			);
			Assert.isTrue(DonorLevelSchedulable.needsFullPass(last), 'Recency cutoffs changed');
		}
	}

	@IsTest
	static void aNewFiscalYearMeansEveryDonor() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Integer month = FiscalYearSelector.fiscalYearStartMonth();
			Date today = Date.today();
			Date fiscalStart = Date.newInstance(
				today.month() >= month ? today.year() : today.year() - 1,
				month,
				1
			);
			DonorLevelSchedulable.todayOverride = fiscalStart.addYears(1);
			Assert.isTrue(
				DonorLevelSchedulable.needsFullPass(Datetime.now().addSeconds(-5)),
				'The last recalculation was in the fiscal year before'
			);
		}
	}

	/** Bulk: of 400 donors, only the 200 whose last gift crossed the 90 day cutoff are read. */
	@IsTest
	static void aQuietNightReadsOnlyTheDonorsCrossingARecencyCutoff() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Id organizationType = AccountKindsTestData.organizationRecordTypeId();
			List<Account> crossing = new List<Account>();
			List<Account> steady = new List<Account>();
			for (Integer i = 0; i < 200; i++) {
				crossing.add(
					TestDataFactory.organization(
						new Account(
							Name = 'Crossing ' + i,
							RecordTypeId = organizationType,
							Last_Gift_Date__c = Date.today().addDays(-91)
						)
					)
				);
				steady.add(
					TestDataFactory.organization(
						new Account(
							Name = 'Steady ' + i,
							RecordTypeId = organizationType,
							Last_Gift_Date__c = Date.today().addDays(-50)
						)
					)
				);
			}
			List<Account> all = new List<Account>(crossing);
			all.addAll(steady);
			insert all;

			List<Date> edges = DonorLevelSchedulable.recencyEdges(Date.today().addDays(-1));
			Set<Id> read = new Set<Id>();
			Database.QueryLocatorIterator rows = DonorLevelSelector.recencyEdgeLocator(
					'Account',
					edges
				)
				.iterator();
			while (rows.hasNext()) {
				read.add(rows.next().Id);
			}

			Assert.isTrue(read.containsAll(new Map<Id, Account>(crossing).keySet()), 'Crossing');
			for (Account donor : steady) {
				Assert.isFalse(read.contains(donor.Id), 'Fifty days crosses no default cutoff');
			}

			Test.startTest();
			Id job = Database.executeBatch(DonorLevelBatch.recencyEdges(edges), 200);
			Test.stopTest();
			Assert.isNotNull(job, 'The rescoring pass ran');
			Assert.isNull(
				Giving_Settings__c.getOrgDefaults().Donor_Levels_Last_Recalculated__c,
				'A rescoring pass records no recalculation'
			);
		}
	}
}
