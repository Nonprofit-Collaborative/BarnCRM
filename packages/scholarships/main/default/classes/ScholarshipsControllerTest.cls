/**
 * The Scholarships and Grants page, the review board, the review panel and the award panel return
 * what they draw, and a refusal reaches the screen in words.
 */
@IsTest(testFor='ApexClass:ScholarshipsController, ApexClass:Scholarships')
private class ScholarshipsControllerTest {
	@TestSetup
	static void setup() {
		TestUsers.adminWith(ScholarshipsTestData.ADMIN_SET);
	}

	@IsTest
	static void thePagesReturnWhatTheyDraw() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Award_Application__c application = ScholarshipsTestData.application(
				cycle.Id,
				ScholarshipsTestData.person('Lee').Id,
				'In Review'
			);
			insert new Application_Review__c(
				Application__c = application.Id,
				Reviewer__c = UserInfo.getUserId()
			);

			Test.startTest();
			ScholarshipsController.Home home = ScholarshipsController.getHome();
			ScholarshipsController.Review review = ScholarshipsController.getReview(application.Id);
			ScholarshipsController.saveReview(
				application.Id,
				'{"overall":7}',
				'Good',
				'submit',
				null
			);
			ScholarshipsController.Board board = ScholarshipsController.getBoard(cycle.Id);
			Id awardId = ScholarshipsController.decide(application.Id, true, 800);
			ScholarshipsController.respond(awardId, true);
			ScholarshipsController.buildSchedule(awardId, 2, Date.today().addDays(30), 6);
			ScholarshipsController.AwardPanel panel = ScholarshipsController.getAward(awardId);
			Test.stopTest();

			Assert.areEqual(1, home.reviews.size(), 'My review to do');
			Assert.areEqual(1, home.cycles.size(), 'The open cycle');
			Assert.isTrue(home.canManage, 'Admin manages');
			Assert.isTrue(review.open, 'Reviewable');
			Assert.areEqual('overall', review.criteria[0].key, 'Default rubric');
			Assert.areEqual(7, board.rows[0].average, 'Scored');
			Assert.areEqual(2, panel.payments.size(), 'Two payments');
			Assert.areEqual(0, panel.requirements.size(), 'No requirements');
			Assert.areEqual(
				1,
				ScholarshipsController.getHome().due.size(),
				'The first payment is due within 30 days'
			);
		}
	}

	@IsTest
	static void aRefusalIsShownInWords() {
		User staff = ScholarshipsTestData.staff('Staff');
		Award_Cycle__c cycle;
		System.runAs(ScholarshipsTestData.admin()) {
			cycle = ScholarshipsTestData.cycle(null, null);
		}
		System.runAs(staff) {
			try {
				ScholarshipsController.assignReviewers(cycle.Id);
				Assert.fail('Staff cannot assign');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Scholarships', 'Scholarships_Error_NoPermission'),
					expected.getMessage(),
					'In words'
				);
			}
			try {
				ScholarshipsController.exportDisbursements(Date.today(), Date.today());
				Assert.fail('Staff cannot export');
			} catch (AuraHandledException expected) {
				Assert.areEqual(
					BarnHelp.text('Scholarships', 'Scholarships_Error_NoPermission'),
					expected.getMessage(),
					'In words'
				);
			}
		}
	}
}
