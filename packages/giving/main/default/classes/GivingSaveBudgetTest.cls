/**
 * Whole-save budgets for gifts (performance review P3, QA review Q8, D-200): a gift insert was
 * estimated at 35 to 45 SOQL queries with every Giving trigger (allocations, soft credits,
 * household credits, acknowledgments, matching gifts, rollups), the costliest save BarnCRM
 * has. These tests fix the budget for 1 gift and for 200, so a new query per save or per row
 * fails here instead of in a donor import. Async work runs after Test.stopTest() and is not
 * counted.
 */
@IsTest(testFor='ApexTrigger:GiftTrigger, ApexTrigger:SoftCreditTrigger')
private class GivingSaveBudgetTest {
	/** Half the 100-query synchronous limit, left for the organization's own automation. */
	private static final Integer SOQL_CEILING = 50;
	/** 200 gifts may cost this many queries more than the ceiling for 1, and no more. */
	private static final Integer BULK_SLACK = 10;
	/** Half the 10-second synchronous CPU limit. */
	private static final Integer CPU_CEILING_MS = 5000;

	@TestSetup
	static void makeData() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			GivingTestDataFactory.insertDefaultFund();
			GivingTestDataFactory.insertHouseholdContact('The Budget Family', 'Ana', 'Budget');
		}
	}

	private static Id donor() {
		return [SELECT Id FROM Contact WHERE LastName = 'Budget' LIMIT 1].Id;
	}

	private static List<Gift__c> gifts(Id donorId, Integer count) {
		List<Gift__c> rows = new List<Gift__c>();
		for (Integer i = 0; i < count; i++) {
			rows.add(GivingTestDataFactory.buildGift(donorId, 10 + i));
		}
		return rows;
	}

	private static void assertSave(List<SObject> rows, Integer soqlCeiling, String what) {
		Test.startTest();
		insert rows;
		Integer soql = Limits.getQueries();
		Integer cpu = Limits.getCpuTime();
		Integer dml = Limits.getDmlStatements();
		Test.stopTest();

		Assert.isTrue(
			soql <= soqlCeiling,
			what + ' used ' + soql + ' SOQL queries; the budget is ' + soqlCeiling
		);
		Assert.isTrue(
			cpu <= CPU_CEILING_MS,
			what + ' used ' + cpu + ' ms of CPU; the budget is ' + CPU_CEILING_MS
		);
		Assert.isTrue(dml <= 75, what + ' used ' + dml + ' DML statements');
	}

	@IsTest
	static void savingOneGiftStaysWithinBudget() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			assertSave(gifts(donor(), 1), SOQL_CEILING, 'One gift');
		}
	}

	@IsTest
	static void savingTwoHundredGiftsCostsAboutWhatOneDoes() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			assertSave(gifts(donor(), 200), SOQL_CEILING + BULK_SLACK, 'Two hundred gifts');
		}
	}

	@IsTest
	static void savingTwoHundredSoftCreditsStaysWithinBudget() {
		System.runAs(TestUsers.adminWith('Giving_Admin')) {
			Id donorId = donor();
			List<Gift__c> saved = gifts(donorId, 200);
			insert saved;
			Contact credited = TestDataFactory.person(
				new Contact(FirstName = 'Sam', LastName = 'Credited')
			);
			insert credited;
			List<Soft_Credit__c> rows = new List<Soft_Credit__c>();
			for (Gift__c gift : saved) {
				rows.add(
					new Soft_Credit__c(
						Gift__c = gift.Id,
						Contact__c = credited.Id,
						Role__c = 'Solicitor',
						Amount__c = 5
					)
				);
			}
			assertSave(rows, SOQL_CEILING + BULK_SLACK, 'Two hundred soft credits');
		}
	}
}
