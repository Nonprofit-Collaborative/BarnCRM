/**
 * Grant requirement rules (F-02, R-GQ1, R-GQ2): the submitted date fills itself in and a typed
 * date is kept; the dates automation has its switch row; Mark Submitted from the Grant Pipeline
 * and its deadline rows; a reader cannot mark one submitted; requirements go with their grant.
 */
@IsTest(
	testFor='ApexClass:GrantRequirementService, ApexClass:GrantRequirementDatesHandler, ApexClass:GrantPipelineController'
)
private class GrantRequirementTest {
	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(GrantTestData.ADMIN);
		TestUsers.standardUserWith(
			'Grqreader',
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
		);
	}

	private static Grant_Requirement__c reread(Id requirementId) {
		return [
			SELECT Status__c, Submitted_Date__c
			FROM Grant_Requirement__c
			WHERE Id = :requirementId
			WITH SYSTEM_MODE
		];
	}

	private static Grant__c grant() {
		Account funder = GrantTestData.funder('Lakeside Foundation');
		Grant__c grant = GrantTestData.grant('Literacy', funder.Id, GrantService.STAGE_AWARDED);
		insert grant;
		return grant;
	}

	@IsTest
	static void theSubmittedDateIsFilledInAndATypedOneKept() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Grant__c grant = grant();
			Grant_Requirement__c open = GrantTestData.requirement('Open', grant.Id, today);
			Grant_Requirement__c accepted = GrantTestData.requirement('Accepted', grant.Id, today);
			accepted.Status__c = GrantRequirementService.STATUS_ACCEPTED;
			Grant_Requirement__c typed = GrantTestData.requirement('Typed', grant.Id, today);
			typed.Status__c = GrantRequirementService.STATUS_SUBMITTED;
			typed.Submitted_Date__c = today.addDays(-3);

			Test.startTest();
			insert new List<Grant_Requirement__c>{ open, accepted, typed };
			Date beforeSubmitting = reread(open.Id).Submitted_Date__c;
			update new Grant_Requirement__c(
				Id = open.Id,
				Status__c = GrantRequirementService.STATUS_IN_PROGRESS
			);
			Date inProgress = reread(open.Id).Submitted_Date__c;
			update new Grant_Requirement__c(
				Id = open.Id,
				Status__c = GrantRequirementService.STATUS_SUBMITTED
			);
			Test.stopTest();

			Assert.isNull(beforeSubmitting, 'Nothing while open');
			Assert.isNull(inProgress, 'Nothing while in progress');
			Assert.areEqual(today, reread(open.Id).Submitted_Date__c, 'Stamped on Submitted');
			Assert.areEqual(today, reread(accepted.Id).Submitted_Date__c, 'Stamped on Accepted');
			Assert.areEqual(today.addDays(-3), reread(typed.Id).Submitted_Date__c, 'Kept');
			Assert.isTrue(GrantRequirementService.isOpen('In Progress'), 'In Progress is open');
			Assert.isFalse(GrantRequirementService.isOpen('Waived'), 'Waived is done');
		}
	}

	@IsTest
	static void theDatesAutomationHasItsSwitchRow() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			List<Automation_Registry__mdt> rows = [
				SELECT Handler_Class__c, Always_Runs__c, Module__c
				FROM Automation_Registry__mdt
				WHERE DeveloperName = 'Grant_Requirement_Dates'
				WITH SYSTEM_MODE
			];
			Assert.areEqual(1, rows.size(), 'The row ships');
			Assert.areEqual('GrantRequirementDatesHandler', rows[0].Handler_Class__c, 'Named');
			Assert.isFalse(rows[0].Always_Runs__c, 'Switchable');
			Assert.areEqual('Funders', rows[0].Module__c, 'The module owns it');
		}
	}

	@IsTest
	static void undoPutsASubmittedRequirementBack() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Grant__c grant = grant();
			Grant_Requirement__c report = GrantTestData.requirement(
				'Report',
				grant.Id,
				Date.today().addDays(5)
			);
			report.Status__c = GrantRequirementService.STATUS_IN_PROGRESS;
			insert report;

			Test.startTest();
			FundersUndoState previous = GrantPipelineController.markSubmitted(report.Id);
			GrantPipelineController.undoSubmitted(previous.id, previous.status, previous.dateValue);
			String again;
			try {
				GrantPipelineController.undoSubmitted(
					previous.id,
					previous.status,
					previous.dateValue
				);
			} catch (AuraHandledException e) {
				again = e.getMessage();
			}
			Test.stopTest();

			Grant_Requirement__c after = reread(report.Id);
			Assert.areEqual(GrantRequirementService.STATUS_IN_PROGRESS, previous.status, 'Was');
			Assert.areEqual(GrantRequirementService.STATUS_IN_PROGRESS, after.Status__c, 'Undone');
			Assert.isNull(after.Submitted_Date__c, 'Its date cleared');
			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Undo_Changed'),
				again,
				'A requirement no longer Submitted is left alone'
			);
			Assert.isFalse(
				GrantRequirementService.undoSubmitted(report.Id, 'Accepted', null),
				'Only back to an open status'
			);
		}
	}

	@IsTest
	static void thePipelineListsRequirementsComingDueAndMarksOneSubmitted() {
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			Date today = Date.today();
			Grant__c grant = grant();
			Grant_Requirement__c soon = GrantTestData.requirement(
				'Soon',
				grant.Id,
				today.addDays(5)
			);
			Grant_Requirement__c late = GrantTestData.requirement(
				'Late',
				grant.Id,
				today.addDays(-2)
			);
			Grant_Requirement__c far = GrantTestData.requirement(
				'Far',
				grant.Id,
				today.addDays(90)
			);
			insert new List<Grant_Requirement__c>{ soon, late, far };

			Test.startTest();
			GrantPipelineController.Board board = GrantPipelineController.getBoard(true);
			GrantPipelineController.markSubmitted(soon.Id);
			Test.stopTest();

			List<String> names = new List<String>();
			for (GrantPipelineController.Card row : board.deadlines) {
				Assert.areEqual(GrantPipelineController.KIND_REQUIREMENT, row.kind, 'Requirement');
				names.add(row.name);
			}
			Assert.areEqual(new List<String>{ 'Late', 'Soon' }, names, 'Due soonest first');
			Assert.areEqual('Literacy', board.deadlines[0].grantName, 'With its grant');
			Assert.areEqual('Narrative Report', board.deadlines[0].requirementType, 'And type');
			Assert.isTrue(board.canMarkSubmitted, 'The admin can mark them');
			Grant_Requirement__c marked = reread(soon.Id);
			Assert.areEqual(GrantRequirementService.STATUS_SUBMITTED, marked.Status__c, 'Marked');
			Assert.areEqual(today, marked.Submitted_Date__c, 'Dated today');
		}
	}

	@IsTest
	static void aReaderCannotMarkOneSubmittedAndRequirementsGoWithTheirGrant() {
		Grant__c grant;
		Grant_Requirement__c report;
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			grant = grant();
			report = GrantTestData.requirement('Report', grant.Id, Date.today());
			insert report;
		}
		User reader = [SELECT Id FROM User WHERE LastName = 'Grqreader' WITH SYSTEM_MODE LIMIT 1];
		String refusal;
		System.runAs(reader) {
			Test.startTest();
			try {
				GrantPipelineController.markSubmitted(report.Id);
			} catch (AuraHandledException e) {
				refusal = e.getMessage();
			}
			Test.stopTest();
			Assert.isFalse(
				GrantPipelineController.getBoard(false).canMarkSubmitted,
				'Not offered to a reader'
			);
		}
		Assert.areEqual(Label.Funders_Pipeline_ErrorNoPermission, refusal, 'Refused');
		System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
			delete grant;
		}
		Assert.areEqual(
			0,
			[SELECT COUNT() FROM Grant_Requirement__c WITH SYSTEM_MODE],
			'Deleted with the grant'
		);
	}
}
