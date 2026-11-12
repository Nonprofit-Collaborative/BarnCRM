/** Records the Scholarships tests share: a program, an open cycle, applicants and awards. */
@IsTest
public class ScholarshipsTestData {
	public static final String ADMIN_SET = 'Scholarships_Admin';

	public static User admin() {
		return TestUsers.adminWith(ADMIN_SET);
	}

	/** A Team Member-like user: Scholarships Staff only, no Manage Scholarships. */
	public static User staff(String lastName) {
		return TestUsers.standardUserWith(lastName, new List<String>{ 'Scholarships_Staff' });
	}

	public static Award_Cycle__c cycle(String rubric, String rules) {
		Award_Program__c program = new Award_Program__c(
			Name = 'Test Scholarship',
			Type__c = 'Scholarship'
		);
		insert program;
		Award_Cycle__c cycle = new Award_Cycle__c(
			Name = '2027',
			Program__c = program.Id,
			Status__c = 'Open',
			Open_Date__c = Date.today().addDays(-10),
			Close_Date__c = Date.today().addDays(10),
			Budget__c = 5000,
			Rubric__c = rubric,
			Eligibility_Rules__c = rules,
			Reviewers_Per_Application__c = 1
		);
		insert cycle;
		return cycle;
	}

	public static Contact person(String lastName) {
		Contact person = new Contact(
			LastName = lastName,
			Email = lastName.toLowerCase() + '@example.org'
		);
		insert person;
		return person;
	}

	public static Award_Application__c application(Id cycleId, Id contactId, String status) {
		Award_Application__c row = new Award_Application__c(
			Cycle__c = cycleId,
			Contact__c = contactId,
			Status__c = status,
			Amount_Requested__c = 1000
		);
		insert row;
		return row;
	}

	public static Award__c award(Id cycleId, Id applicationId, Id contactId, Decimal amount) {
		Award__c row = new Award__c(
			Cycle__c = cycleId,
			Application__c = applicationId,
			Contact__c = contactId,
			Amount__c = amount,
			Status__c = 'Accepted',
			Renewable__c = true
		);
		insert row;
		return row;
	}
}
