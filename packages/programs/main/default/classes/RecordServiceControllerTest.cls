/**
 * The Record Service action's server side (modules-14): the form filled in from a person or an
 * enrollment, a delivery recorded for the one person chosen, and refusals passed on in their own
 * words.
 */
@IsTest(testFor='ApexClass:RecordServiceController')
private class RecordServiceControllerTest {
	private static final String ADMIN = 'Programs_Admin';

	private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };

	private static final List<String> READ_ONLY = new List<String>{
		'BarnCRM_Read_Only',
		'Programs_Read_Only'
	};

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
		TestUsers.standardUserWith('Writer', STAFF);
		TestUsers.standardUserWith('Reader', READ_ONLY);
	}

	private static void contactMode() {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
	}

	private static Service__c serviceIn(Program__c program, String name) {
		Service__c service = new Service__c(
			Program__c = program.Id,
			Name = name,
			Unit_Of_Measure__c = 'meals'
		);
		insert service;
		return service;
	}

	@IsTest
	static void anEnrollmentFillsInThePersonTheEnrollmentAndItsServices() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			contactMode();
			Program__c pantry = new Program__c(Name = 'Pantry');
			Program__c tutoring = new Program__c(Name = 'Tutoring');
			insert new List<Program__c>{ pantry, tutoring };
			Service__c meal = serviceIn(pantry, 'Hot meal');
			serviceIn(tutoring, 'Tutoring hour');
			Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
			insert ana;
			Enrollment__c enrolled = new Enrollment__c(Program__c = pantry.Id, Contact__c = ana.Id);
			insert enrolled;

			Test.startTest();
			RecordServiceController.Form fromEnrollment = RecordServiceController.getForm(
				enrolled.Id
			);
			RecordServiceController.Form fromPerson = RecordServiceController.getForm(ana.Id);
			Test.stopTest();

			Assert.areEqual(ana.Id, fromEnrollment.personId, 'The enrollment\'s person.');
			Assert.areEqual(enrolled.Id, fromEnrollment.enrollmentId, 'And the enrollment.');
			Assert.areEqual('Contact', fromEnrollment.personObjectApiName, 'A contact.');
			Assert.areEqual(1, fromEnrollment.services.size(), 'Only the program\'s services.');
			Assert.areEqual(meal.Id, fromEnrollment.serviceId, 'One service is chosen for you.');
			Assert.isTrue(fromEnrollment.canCreate, 'Admin records services.');
			Assert.isFalse(fromEnrollment.attendance.isEmpty(), 'The attendance choices.');
			Assert.isNotNull(fromEnrollment.dateLabel, 'The field labels.');

			Assert.areEqual(ana.Id, fromPerson.personId, 'The person it was opened from.');
			Assert.isNull(fromPerson.enrollmentId, 'No enrollment from a person.');
			Assert.areEqual(2, fromPerson.services.size(), 'Every active service.');
			Assert.areEqual('Pantry: Hot meal', fromPerson.services[0].label, 'Named by program.');
			Assert.isNull(fromPerson.serviceId, 'Two services: none chosen for you.');
		}
	}

	@IsTest
	static void recordsOneDeliveryForThePersonChosen() {
		Contact ana;
		Service__c meal;
		Enrollment__c enrolled;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			contactMode();
			Program__c pantry = new Program__c(Name = 'Pantry');
			insert pantry;
			meal = serviceIn(pantry, 'Hot meal');
		}
		Date day = Date.today().addDays(-2);
		Id presentId;
		Id absentId;
		System.runAs(TestUsers.standardUserWith('Writer', STAFF)) {
			// The staff member's own person: contacts are private in some orgs.
			ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
			insert ana;
			enrolled = new Enrollment__c(Program__c = meal.Program__c, Contact__c = ana.Id);
			insert enrolled;
			Test.startTest();
			presentId = RecordServiceController.record(ana.Id, meal.Id, day, 'Present', null, null);
			absentId = RecordServiceController.record(
				ana.Id,
				meal.Id,
				day.addDays(1),
				'Excused Absence',
				3,
				enrolled.Id
			);
			Test.stopTest();
		}

		Map<Id, Service_Delivery__c> saved = new Map<Id, Service_Delivery__c>(
			[
				SELECT Contact__c, Account__c, Enrollment__c, Delivery_Date__c, Quantity__c
				FROM Service_Delivery__c
			]
		);
		Assert.areEqual(2, saved.size(), 'Two deliveries.');
		Service_Delivery__c present = saved.get(presentId);
		Assert.areEqual(ana.Id, present.Contact__c, 'For Ana, as a contact.');
		Assert.isNull(present.Account__c, 'Never both.');
		Assert.areEqual(day, present.Delivery_Date__c, 'On the day chosen.');
		Assert.areEqual(1, present.Quantity__c, 'A blank quantity counts one.');
		Assert.areEqual(enrolled.Id, present.Enrollment__c, 'The enrollment fills itself in.');
		Assert.areEqual(0, saved.get(absentId).Quantity__c, 'An absence delivers nothing.');
	}

	@IsTest
	static void refusalsAreReportedPlainly() {
		Contact ana;
		Service__c meal;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			contactMode();
			Program__c pantry = new Program__c(Name = 'Pantry');
			insert pantry;
			meal = serviceIn(pantry, 'Hot meal');
			ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
			insert ana;
		}
		String failed = BarnHelp.text('Programs', 'Programs_Fail_RecordService');
		AuraHandledException missing;
		AuraHandledException readOnly;
		System.runAs(TestUsers.standardUserWith('Reader', READ_ONLY)) {
			Test.startTest();
			Assert.isFalse(RecordServiceController.getForm(ana.Id).canCreate, 'A reader cannot.');
			try {
				RecordServiceController.record(ana.Id, meal.Id, null, 'Present', 1, null);
			} catch (AuraHandledException refused) {
				missing = refused;
			}
			try {
				RecordServiceController.record(ana.Id, meal.Id, Date.today(), 'Present', 1, null);
			} catch (AuraHandledException refused) {
				readOnly = refused;
			}
			Test.stopTest();
		}
		Assert.areEqual(failed, missing.getMessage(), 'A missing date is refused plainly.');
		Assert.isNotNull(readOnly, 'A reader cannot record a service.');
		Assert.areEqual(0, [SELECT COUNT() FROM Service_Delivery__c], 'Nothing saved.');
	}
}
