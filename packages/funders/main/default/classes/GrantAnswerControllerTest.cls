/**
 * The Answer Library's server side (F-14, canonical model 29ZN): answers with text by title
 * (R-GA1), copying stamps the last used date for a person who can edit answers (R-GA3), and a
 * read-only person can read and copy without stamping.
 */
@IsTest(testFor='ApexClass:GrantAnswerController')
private class GrantAnswerControllerTest {
	private static final String STAFF = 'Funders_Staff';
	private static final String READER = 'Gaareader';

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(STAFF);
		TestUsers.standardUserWith(
			READER,
			new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
		);
	}

	private static List<Grant_Answer__c> answers() {
		List<Grant_Answer__c> rows = new List<Grant_Answer__c>{
			new Grant_Answer__c(
				Name = 'Need statement',
				Topics__c = 'Need',
				Answer__c = 'Half read below grade level.'
			),
			new Grant_Answer__c(
				Name = 'Mission',
				Topics__c = 'Mission, Organization',
				Answer__c = 'We teach reading.'
			),
			new Grant_Answer__c(Name = 'Blank draft', Topics__c = 'Budget')
		};
		insert as user rows;
		return rows;
	}

	private static Date lastUsed(Id answerId) {
		return [SELECT Last_Used_Date__c FROM Grant_Answer__c WHERE Id = :answerId WITH SYSTEM_MODE]
		.Last_Used_Date__c;
	}

	@IsTest
	static void staffSeeAnswersByTitleAndCopyingStampsToday() {
		System.runAs(TestUsers.adminWith(STAFF)) {
			List<Grant_Answer__c> rows = answers();
			Date today = Date.today();

			Test.startTest();
			GrantAnswerController.Library library = GrantAnswerController.getLibrary();
			Date stamped = GrantAnswerController.markUsed(rows[1].Id);
			Test.stopTest();

			Assert.isTrue(library.canCreate, 'Staff add answers');
			Assert.areEqual(2, library.answers.size(), 'The blank draft is left out');
			Assert.areEqual('Mission', library.answers[0].title, 'By title');
			Assert.areEqual('Mission, Organization', library.answers[0].topics, 'Topics as typed');
			Assert.areEqual('We teach reading.', library.answers[0].text, 'The text');
			Assert.isNull(library.answers[0].lastUsed, 'Never used yet');
			Assert.areEqual(today, stamped, 'Stamped today');
			Assert.areEqual(today, lastUsed(rows[1].Id), 'Saved');
		}
	}

	@IsTest
	static void aReadOnlyPersonCopiesWithoutStamping() {
		List<Grant_Answer__c> rows;
		System.runAs(TestUsers.adminWith(STAFF)) {
			rows = answers();
		}
		User reader = [SELECT Id FROM User WHERE LastName = :READER WITH SYSTEM_MODE LIMIT 1];
		System.runAs(reader) {
			Test.startTest();
			GrantAnswerController.Library library = GrantAnswerController.getLibrary();
			Date stamped = GrantAnswerController.markUsed(rows[0].Id);
			Test.stopTest();

			Assert.isFalse(library.canCreate, 'Read only adds nothing');
			Assert.areEqual(2, library.answers.size(), 'But reads the answers');
			Assert.isNull(stamped, 'Nothing stamped');
		}
		Assert.isNull(lastUsed(rows[0].Id), 'The date is unchanged');
	}

	@IsTest
	static void aFailedStampIsReported() {
		System.runAs(TestUsers.adminWith(STAFF)) {
			Grant_Answer__c gone = answers()[0];
			delete as user gone;

			Test.startTest();
			String message;
			try {
				GrantAnswerController.markUsed(gone.Id);
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(
				BarnHelp.text('Funders', 'Funders_Answers_ErrorStamp'),
				message,
				'Reported plainly'
			);
		}
	}
}
