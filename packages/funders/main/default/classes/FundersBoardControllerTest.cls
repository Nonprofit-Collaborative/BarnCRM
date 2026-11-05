/**
 * The Board Dashboard (F-07, canonical model 29ZH R-GN9): this fiscal year's awards by funding
 * source and funder, and Giving's gifts, organizations and restricted funds read by describe only
 * where the person can read them. Giving records are made through describe too, so Funders still
 * names no Giving object.
 */
@IsTest(testFor='ApexClass:FundersBoardController')
private class FundersBoardControllerTest {
	private static final String STAFF = 'Funders_Staff';
	private static final List<String> STAFF_WITH_GIVING = new List<String>{
		TestUsers.CORE_ADMIN,
		STAFF,
		'Giving_Read_Only'
	};

	@TestSetup
	static void createRecords() {
		TestUsers.withPermissionSets(STAFF_WITH_GIVING);
		TestUsers.adminWith(STAFF);
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Account lakeside = GrantTestData.funder('Lakeside Foundation');
			Account agency = GrantTestData.funder('State Agency');
			Date today = Date.today();
			List<Grant__c> grants = new List<Grant__c>{
				awarded('Federal award', lakeside.Id, 30000, today, 'Federal'),
				awarded('State award', agency.Id, 20000, today, null),
				awarded('Old award', lakeside.Id, 99000, today.addYears(-2), 'Federal')
			};
			Grant__c applied = GrantTestData.grant(
				'Open request',
				agency.Id,
				GrantService.STAGE_APPLIED
			);
			applied.Amount_Requested__c = 50000;
			grants.add(applied);
			insert as user grants;

			Schema.SObjectType fund = NamespaceUtil.packagedObjectType('Fund__c');
			Database.insert(
				new List<SObject>{
					fundRecord(fund, 'Scholarships', true, 12000),
					fundRecord(fund, 'General', false, 38000)
				},
				AccessLevel.SYSTEM_MODE
			);
			lakeside.put(NamespaceUtil.qualify('Giving_This_Year__c'), 5000);
			Database.update(lakeside, AccessLevel.SYSTEM_MODE);
		}
	}

	private static Grant__c awarded(
		String name,
		Id funderId,
		Decimal amount,
		Date decided,
		String source
	) {
		Grant__c grant = GrantTestData.grant(name, funderId, GrantService.STAGE_AWARDED);
		grant.Amount_Awarded__c = amount;
		grant.Decision_Date__c = decided;
		grant.Funding_Source__c = source;
		return grant;
	}

	private static SObject fundRecord(
		Schema.SObjectType type,
		String name,
		Boolean restricted,
		Decimal raised
	) {
		SObject record = type.newSObject();
		record.put('Name', name);
		record.put(NamespaceUtil.qualify('Active__c'), true);
		record.put(NamespaceUtil.qualify('Restricted__c'), restricted);
		record.put(NamespaceUtil.qualify('Total_Raised_This_Year__c'), raised);
		return record;
	}

	@IsTest
	static void withGivingTheBoardJoinsGrantsAndGifts() {
		System.runAs(TestUsers.withPermissionSets(STAFF_WITH_GIVING)) {
			Test.startTest();
			FundersBoardController.Board board = FundersBoardController.getBoard();
			Test.stopTest();

			Assert.areEqual(2, board.grantsBySource.size(), 'This year only, by source');
			Assert.areEqual('Federal', board.grantsBySource[0].name, 'Largest first, by label');
			Assert.areEqual(30000, board.grantsBySource[0].amount, 'Federal awarded');
			Assert.isNull(board.grantsBySource[1].key, 'A blank source');
			Assert.areEqual(2, board.grantsByFunder.size(), 'Each funder');
			Assert.areEqual(
				'Lakeside Foundation',
				board.grantsByFunder[0].name,
				'Largest funder first'
			);
			Assert.isTrue(board.givingAvailable, 'Giving read');
			Assert.areEqual(50000, board.giftsThisYear, 'Every fund this year');
			Assert.areEqual(1, board.givingByAccount.size(), 'Organizations that gave');
			Assert.areEqual(5000, board.givingByAccount[0].amount, 'Giving This Year');
			Assert.areEqual(1, board.restrictedFunds.size(), 'Restricted funds only');
			Assert.areEqual('Scholarships', board.restrictedFunds[0].name, 'The restricted fund');
			Assert.areEqual(12000, board.restrictedFunds[0].amount, 'Raised this year');
			Assert.isTrue(board.restrictedGrants.isEmpty(), 'No restricted grant');
			Assert.isNotNull(board.currencyCode, 'A currency');
		}
	}

	@IsTest
	static void withoutGivingAccessTheBoardShowsGrantsAlone() {
		System.runAs(TestUsers.adminWith(STAFF)) {
			Test.startTest();
			FundersBoardController.Board board = FundersBoardController.getBoard();
			Test.stopTest();

			Assert.areEqual(2, board.grantsByFunder.size(), 'The grants');
			Assert.isFalse(board.givingAvailable, 'No Giving access');
			Assert.areEqual(0, board.giftsThisYear, 'No gifts');
			Assert.isTrue(board.givingByAccount.isEmpty(), 'No giving by organization');
			Assert.isTrue(board.restrictedFunds.isEmpty(), 'No funds');
		}
	}
}
