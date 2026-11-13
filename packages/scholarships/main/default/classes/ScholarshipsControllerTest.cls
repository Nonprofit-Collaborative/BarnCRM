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

	/** Stands in for Forms: every form has a public link for the record. */
	private class Catalog implements FormCatalogExtension {
		public List<FormCatalogEntry> publicForms() {
			return new List<FormCatalogEntry>();
		}

		public List<FormCatalogEntry> questions(Id formId) {
			return new List<FormCatalogEntry>();
		}

		public String publicLink(Id formId, Id contextRecordId) {
			return 'https://zzforms.example.org/FormsPublic?record=' + contextRecordId;
		}
	}

	@IsTest
	static void theAwardPanelActionsAllWork() {
		System.runAs(ScholarshipsTestData.admin()) {
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			Award_Application__c application = ScholarshipsTestData.application(
				cycle.Id,
				ScholarshipsTestData.person('Lee').Id,
				'In Review'
			);
			Id awardId = ScholarshipsController.decide(application.Id, true, 900);
			Award_Requirement__c condition = new Award_Requirement__c(
				Award__c = awardId,
				Name = 'Progress report',
				Type__c = 'Progress Report',
				Due_Date__c = Date.today().addDays(60)
			);
			Award_Requirement__c waivable = new Award_Requirement__c(
				Award__c = awardId,
				Name = 'Thank-you note',
				Type__c = 'Progress Report'
			);
			insert new List<Award_Requirement__c>{ condition, waivable };
			update new Award__c(Id = awardId, Renewable__c = true);

			Test.startTest();
			Id letter = ScholarshipsController.makeLetter(awardId);
			ScholarshipsController.buildSchedule(awardId, 1, Date.today().addDays(5), 1);
			Id paymentId = ScholarshipsController.getAward(awardId).payments[0].id;
			ScholarshipsController.markPaid(paymentId, Date.today(), 'Check', 'No. 12');
			List<ScholarshipAwards.Payment> exported = ScholarshipsController.exportDisbursements(
				Date.today().addDays(-1),
				Date.today().addDays(10)
			);
			ScholarshipsController.setRequirement(condition.Id, 'Met');
			ScholarshipsController.setRequirement(waivable.Id, 'Waived');
			String badStatus;
			try {
				ScholarshipsController.setRequirement(condition.Id, 'Nonsense');
			} catch (AuraHandledException expected) {
				badStatus = expected.getMessage();
			}
			String noCycle;
			try {
				ScholarshipsController.startRenewal(awardId);
			} catch (AuraHandledException expected) {
				noCycle = expected.getMessage();
			}
			insert new Award_Cycle__c(
				Name = '2028',
				Program__c = cycle.Program__c,
				Status__c = 'Planned'
			);
			Id renewal = ScholarshipsController.startRenewal(awardId);
			Test.stopTest();

			Assert.isNotNull(letter, 'The letter is filed on the award');
			Assert.areEqual(
				'Paid',
				[SELECT Status__c FROM Award_Payment__c WHERE Id = :paymentId].Status__c,
				'Marked paid'
			);
			Assert.areEqual(1, exported.size(), 'The payment is exported');
			Assert.areEqual(
				'Met',
				[SELECT Status__c FROM Award_Requirement__c WHERE Id = :condition.Id].Status__c,
				'Met'
			);
			Assert.areEqual(
				'Waived',
				[SELECT Status__c FROM Award_Requirement__c WHERE Id = :waivable.Id].Status__c,
				'Waived'
			);
			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Error_Generic'),
				badStatus,
				'An unknown status is refused'
			);
			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Renewal_NoCycle'),
				noCycle,
				'No next cycle yet'
			);
			Assert.areEqual(
				awardId,
				[SELECT Renewal_Of__c FROM Award_Application__c WHERE Id = :renewal].Renewal_Of__c,
				'The renewal is linked'
			);
		}
	}

	@IsTest
	static void theBoardLinksTheCyclesFormAndAReviewCanBeSavedWithoutScores() {
		System.runAs(ScholarshipsTestData.admin()) {
			FormCatalogTestSupport.install(new Catalog());
			Award_Cycle__c cycle = ScholarshipsTestData.cycle(null, null);
			update new Award_Cycle__c(
				Id = cycle.Id,
				Application_Form_Key__c = String.valueOf(cycle.Program__c)
			);
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
			ScholarshipsController.Board board = ScholarshipsController.getBoard(cycle.Id);
			ScholarshipsController.MyReview saved = ScholarshipsController.saveReview(
				application.Id,
				null,
				'Thoughtful essay',
				'save',
				null
			);
			String noPanel;
			try {
				ScholarshipsController.assignReviewers(cycle.Id);
			} catch (AuraHandledException expected) {
				noPanel = expected.getMessage();
			}
			Test.stopTest();

			Assert.isTrue(board.formLink.contains(String.valueOf(cycle.Id)), 'The form link');
			Assert.areEqual('Thoughtful essay', saved.comments, 'The comment is kept');
			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Assign_NoPanel'),
				noPanel,
				'No panel to assign to'
			);
		}
	}

	@IsTest
	static void anUnexpectedFailureIsShownAsOneMessage() {
		System.runAs(ScholarshipsTestData.admin()) {
			Contact notACycle = ScholarshipsTestData.person('Lee');

			Test.startTest();
			String message;
			try {
				ScholarshipsController.getBoard(notACycle.Id);
			} catch (AuraHandledException expected) {
				message = expected.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Scholarships', 'Scholarships_Error_Generic'),
				message,
				'One message for anything unexpected'
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
