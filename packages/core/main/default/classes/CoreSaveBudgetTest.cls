/**
 * Whole-save budgets for Core's busiest objects (performance review P3, QA review Q8, D-200):
 * what one save of 1 row and of 200 rows costs in SOQL queries, DML statements and CPU, with
 * every trigger and automation the org holds running, so a change that adds a query per save,
 * or a query per row, fails here instead of in a customer's import.
 *
 * Two limits each: an absolute ceiling that keeps half of the governor limit free for the
 * organization's own automation and for module triggers, and a bulk rule that 200 rows cost
 * no more than a few queries above 1 row (a query inside a loop shows as about 200 more).
 * Async work started by the save runs after Test.stopTest() and is not counted.
 */
@IsTest(
	testFor='ApexTrigger:ContactTrigger, ApexTrigger:AccountTrigger, ApexTrigger:AddressTrigger'
)
private class CoreSaveBudgetTest {
	/** Half the 100-query synchronous limit, left for everything that is not BarnCRM Core. */
	private static final Integer SOQL_CEILING = 50;
	/** 200 rows may cost this many queries more than 1 row, and no more. */
	private static final Integer BULK_SLACK = 10;
	/** Half the 10-second synchronous CPU limit. */
	private static final Integer CPU_CEILING_MS = 5000;

	@TestSetup
	static void createTestUser() {
		TestUsers.admin();
	}

	private class Cost {
		Integer soql;
		Integer dml;
		Integer cpu;
	}

	private static Cost measureInsert(List<SObject> rows) {
		Cost cost = new Cost();
		Test.startTest();
		insert rows;
		cost.soql = Limits.getQueries();
		cost.dml = Limits.getDmlStatements();
		cost.cpu = Limits.getCpuTime();
		Test.stopTest();
		return cost;
	}

	private static List<Contact> people(Integer count, String lastName) {
		List<Contact> rows = new List<Contact>();
		for (Integer i = 0; i < count; i++) {
			rows.add(
				TestDataFactory.person(
					new Contact(
						FirstName = 'Budget' + i,
						LastName = lastName,
						Email = 'budget' + i + '.' + lastName.toLowerCase() + '@example.org'
					)
				)
			);
		}
		return rows;
	}

	private static void assertWithin(Cost cost, String what) {
		Assert.isTrue(
			cost.soql <= SOQL_CEILING,
			what + ' used ' + cost.soql + ' SOQL queries; the budget is ' + SOQL_CEILING
		);
		Assert.isTrue(
			cost.cpu <= CPU_CEILING_MS,
			what + ' used ' + cost.cpu + ' ms of CPU; the budget is ' + CPU_CEILING_MS
		);
		Assert.isTrue(cost.dml <= 75, what + ' used ' + cost.dml + ' DML statements');
	}

	@IsTest
	static void savingOnePersonStaysWithinBudget() {
		System.runAs(TestUsers.admin()) {
			Cost one = measureInsert(people(1, 'Single'));
			assertWithin(one, 'One person');
		}
	}

	@IsTest
	static void savingTwoHundredPeopleCostsAboutWhatOneDoes() {
		System.runAs(TestUsers.admin()) {
			Cost many = measureInsert(people(200, 'Bulk'));
			assertWithin(many, 'Two hundred people');
			// The single-row figure is measured in its own test; a per-row query would put
			// 200 rows near the 100-query limit, far over the ceiling plus the slack.
			Assert.isTrue(
				many.soql <= SOQL_CEILING + BULK_SLACK,
				'Two hundred people cost ' + many.soql + ' queries: a query runs per row'
			);
		}
	}

	@IsTest
	static void savingTwoHundredOrganizationsStaysWithinBudget() {
		System.runAs(TestUsers.admin()) {
			List<Account> rows = new List<Account>();
			for (Integer i = 0; i < 200; i++) {
				rows.add(
					TestDataFactory.organization(new Account(Name = 'Budget Foundation ' + i))
				);
			}
			assertWithin(measureInsert(rows), 'Two hundred organizations');
		}
	}

	@IsTest
	static void savingTwoHundredAddressesStaysWithinBudget() {
		System.runAs(TestUsers.admin()) {
			List<Contact> owners = people(200, 'Address');
			insert owners;
			List<Address__c> rows = new List<Address__c>();
			for (Contact owner : owners) {
				rows.add(new Address__c(Contact__c = owner.Id, Street__c = '1 Main Street'));
			}
			assertWithin(measureInsert(rows), 'Two hundred addresses');
		}
	}
}
