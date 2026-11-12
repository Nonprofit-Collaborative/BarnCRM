/**
 * The Answer Library card on a grant's page (F-14, canonical model 29ZN): the organization's
 * reusable application answers, and stamping an answer's Last Used Date when it is copied
 * (R-GA3).
 *
 * Thin by design (plan Section 9.9): plain shapes out; the search, topics and word counts run in
 * the framework-free module `grantAnswerModel`. Everything runs as the person.
 */
public with sharing class GrantAnswerController {
	private static final String CONTEXT = 'GrantAnswerController';
	@TestVisible
	private static final Integer ANSWER_LIMIT = 500;

	/** One answer, as the card draws it. */
	public class Answer {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String title;
		@AuraEnabled
		public String topics;
		@AuraEnabled
		public String text;
		@AuraEnabled
		public Date lastUsed;
	}

	/** What the card draws. */
	public class Library {
		@AuraEnabled
		public List<Answer> answers = new List<Answer>();
		/** Whether the person can add answers (the card links to the Grant Answers tab). */
		@AuraEnabled
		public Boolean canCreate = false;
	}

	/** The answers with text (R-GA1), by title, up to 500. */
	@AuraEnabled
	public static Library getLibrary() {
		try {
			Library library = new Library();
			library.canCreate = Schema.SObjectType.Grant_Answer__c.isCreateable();
			for (Grant_Answer__c row : [
				SELECT Id, Name, Topics__c, Answer__c, Last_Used_Date__c
				FROM Grant_Answer__c
				WITH USER_MODE
				ORDER BY Name
				LIMIT :ANSWER_LIMIT
			]) {
				if (String.isBlank(row.Answer__c)) {
					continue;
				}
				Answer answer = new Answer();
				answer.id = row.Id;
				answer.title = row.Name;
				answer.topics = row.Topics__c;
				answer.text = row.Answer__c;
				answer.lastUsed = row.Last_Used_Date__c;
				library.answers.add(answer);
			}
			return library;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getLibrary');
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Answers_LoadFailed'));
		}
	}

	/**
	 * R-GA3: sets the answer's Last Used Date to today, when the person can edit it.
	 *
	 * @param answerId the answer copied
	 * @return the date stamped, or null when the person cannot edit answers
	 */
	@AuraEnabled
	public static Date markUsed(Id answerId) {
		if (!Schema.SObjectType.Grant_Answer__c.fields.Last_Used_Date__c.isUpdateable()) {
			return null;
		}
		try {
			Date today = Date.today();
			update as user new Grant_Answer__c(Id = answerId, Last_Used_Date__c = today);
			return today;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.markUsed', answerId);
			throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Answers_ErrorStamp'));
		}
	}
}
