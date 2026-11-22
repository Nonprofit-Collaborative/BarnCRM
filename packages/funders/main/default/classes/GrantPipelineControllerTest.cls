/**
 * The Grant Pipeline tab's server side (F-01): open grants by stage with exact totals, awarded this
 * fiscal year, the deadlines coming up, Mine and the card cap; and the writes the board makes
 * when it moves a grant (with the amount awarded) as the person, refused for a reader.
 */
@IsTest(testFor='ApexClass:GrantPipelineController')
private class GrantPipelineControllerTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.standardUserWith('Gpreader', new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' });
	}

	private static Grant__c reread(Id grantId) {
		return [
			SELECT Stage__c, Amount_Awarded__c, Decision_Date__c
			FROM Grant__c
			WHERE Id = :grantId
			WITH SYSTEM_MODE
		];
	}

	/** Two prospects (one due in 10 days, one 90), one applied, one awarded today, one declined. */
	private static Map<String, Grant__c> grants(Date today) {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		Map<String, Grant__c> byName = new Map<String, Grant__c>{
			'Soon' => GrantTestData.grant('Soon', funder.Id, GrantService.STAGE_PROSPECT),
			'Later' => GrantTestData.grant('Later', funder.Id, GrantService.STAGE_PROSPECT),
			'Applied' => GrantTestData.grant('Applied', funder.Id, GrantService.STAGE_APPLIED),
			'Won' => GrantTestData.grant('Won', funder.Id, GrantService.STAGE_AWARDED),
			'Lost' => GrantTestData.grant('Lost', funder.Id, GrantService.STAGE_DECLINED)
		};
		byName.get('Soon').Amount_Requested__c = 1000;
		byName.get('Soon').Application_Deadline__c = today.addDays(10);
		byName.get('Later').Amount_Requested__c = 2000;
		byName.get('Later').Application_Deadline__c = today.addDays(90);
		byName.get('Applied').Amount_Requested__c = 5000;
		byName.get('Applied').Application_Deadline__c = today.addDays(-5);
		byName.get('Won').Amount_Awarded__c = 7000;
		byName.get('Won').Decision_Date__c = today;
		insert byName.values();
		return byName;
	}

	@IsTest
	static void theBoardCountsOpenGrantsByStageAndListsTheDeadlines() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Map<String, Grant__c> byName = grants(today);

			Test.startTest();
			GrantPipelineController.Board board = GrantPipelineController.getBoard(false);
			Test.stopTest();

			Assert.areEqual(GrantService.OPEN_STAGES, board.stages, 'The open stages are columns');
			Assert.areEqual(GrantService.STAGES, board.allStages, 'Every stage is a move');
			Assert.areEqual(3, board.openCount, 'Two prospects and one applied');
			Assert.areEqual(8000, board.openAmount, 'Their amounts requested');
			Assert.areEqual(3, board.cards.size(), 'Each open grant is a card');
			Assert.isFalse(board.truncated, 'All cards are drawn');
			Assert.areEqual(1, board.awardedCount, 'The award this fiscal year');
			Assert.areEqual(7000, board.awardedAmount, 'Its amount awarded');
			Assert.isTrue(board.canEdit, 'The admin can move grants');
			Assert.areEqual(today, board.today, 'Today is sent');
			Assert.areEqual(1, board.deadlines.size(), 'Only the prospect due within 60 days');
			Assert.areEqual(byName.get('Soon').Id, board.deadlines[0].id, 'The one due soon');
			Assert.areEqual('Lakeside Foundation', board.deadlines[0].funderName, 'With its funder');
			Map<String, Integer> counts = new Map<String, Integer>();
			for (GrantPipelineController.Total total : board.stageTotals) {
				counts.put(total.stage, total.count);
			}
			Assert.areEqual(2, counts.get(GrantService.STAGE_PROSPECT), 'Prospects counted');
			Assert.areEqual(1, counts.get(GrantService.STAGE_APPLIED), 'Applied counted');
		}
	}

	@IsTest
	static void mineShowsOnlyTheGrantsThePersonOwnsAndTheCapKeepsTotalsExact() {
		User admin = TestUsers.adminWith(GrantTestData.ADMIN);
		System.runAs(admin) {
			grants(Date.today());

			Test.startTest();
			GrantPipelineController.maxCards = 1;
			GrantPipelineController.Board capped = GrantPipelineController.getBoard(true);
			Test.stopTest();

			Assert.areEqual(3, capped.openCount, 'The admin owns all three open grants');
			Assert.areEqual(1, capped.cards.size(), 'Only one card is drawn');
			Assert.isTrue(capped.truncated, 'And the board says so');
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Gpreader' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			GrantPipelineController.Board mine = GrantPipelineController.getBoard(true);
			Assert.areEqual(0, mine.openCount, 'The reader owns none');
			Assert.isFalse(mine.canEdit, 'And cannot move grants');
			Assert.areEqual(3, GrantPipelineController.getBoard(false).openCount, 'Everyone shows all');
		}
	}

	// The board's moves and Record the Award save through Lightning Data Service as the person
	// (ADR-0093 A2). The tests below make the same writes, so the grant rules still run.

	@IsTest
	static void movingToAwardedRecordsTheAmountAndTheDecisionDate() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Map<String, Grant__c> byName = grants(today);
			Id applied = byName.get('Applied').Id;

			Test.startTest();
			update as user new Grant__c(Id = applied, Stage__c = GrantService.STAGE_AWARDED, Amount_Awarded__c = 4500);
			update as user new Grant__c(Id = byName.get('Soon').Id, Stage__c = GrantService.STAGE_WITHDRAWN);
			Test.stopTest();

			Grant__c awarded = reread(applied);
			Assert.areEqual(GrantService.STAGE_AWARDED, awarded.Stage__c, 'Moved');
			Assert.areEqual(4500, awarded.Amount_Awarded__c, 'The amount awarded is recorded');
			Assert.areEqual(today, awarded.Decision_Date__c, 'The decision date is stamped');
			Assert.isNull(reread(byName.get('Soon').Id).Amount_Awarded__c, 'An amount is recorded only on Awarded');
		}
	}

	@IsTest
	static void recordTheAwardSavesThePeriodAndRestrictedInOneStep() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Map<String, Grant__c> byName = grants(today);
			Id applied = byName.get('Applied').Id;
			Id soon = byName.get('Soon').Id;
			Date start = Date.newInstance(2027, 1, 1);
			Date finish = Date.newInstance(2027, 12, 31);

			Test.startTest();
			GrantPipelineController.Board board = GrantPipelineController.getBoard(false);
			update as user new Grant__c(
				Id = applied,
				Stage__c = GrantService.STAGE_AWARDED,
				Amount_Awarded__c = 4500,
				Award_Start_Date__c = start,
				Award_End_Date__c = finish,
				Restricted__c = true
			);
			update as user new Grant__c(Id = soon, Stage__c = GrantService.STAGE_AWARDED);
			Test.stopTest();

			Grant__c awarded = [
				SELECT Stage__c, Amount_Awarded__c, Award_Start_Date__c, Award_End_Date__c, Restricted__c
				FROM Grant__c
				WHERE Id = :applied
				WITH SYSTEM_MODE
			];
			Assert.areEqual(GrantService.STAGE_AWARDED, awarded.Stage__c, 'Awarded');
			Assert.areEqual(4500, awarded.Amount_Awarded__c, 'With the amount');
			Assert.areEqual(start, awarded.Award_Start_Date__c, 'The start date');
			Assert.areEqual(finish, awarded.Award_End_Date__c, 'The end date');
			Assert.isTrue(awarded.Restricted__c, 'And restricted');
			Grant__c bare = reread(soon);
			Assert.areEqual(GrantService.STAGE_AWARDED, bare.Stage__c, 'Every field is optional');
			Assert.isNull(bare.Amount_Awarded__c, 'Nothing typed, nothing set');
			Boolean sawFields = false;
			for (GrantPipelineController.Card card : board.cards) {
				if (card.id == applied) {
					sawFields = card.restricted == false && card.awardStartDate == null;
				}
			}
			Assert.isTrue(sawFields, 'A card carries what the dialog starts from');
		}
	}

	@IsTest
	static void aBadStageAndAReaderAreRefused() {
		Id grantId;
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			grantId = grants(Date.today()).get('Soon').Id;
			try {
				update as user new Grant__c(Id = grantId, Stage__c = 'Nowhere');
				Assert.fail('An unknown stage is refused');
			} catch (DmlException e) {
				Assert.isNotNull(e.getDmlMessage(0), 'Stage is a restricted picklist, so the save says why');
			}
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Gpreader' WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Test.startTest();
			Boolean refused = false;
			try {
				update as user new Grant__c(Id = grantId, Stage__c = GrantService.STAGE_APPLIED);
			} catch (Exception e) {
				refused = true;
			}
			Test.stopTest();
			Assert.isTrue(refused, 'A reader cannot move a grant');
		}
		Assert.areEqual(GrantService.STAGE_PROSPECT, reread(grantId).Stage__c, 'Nothing moved');
	}
}
