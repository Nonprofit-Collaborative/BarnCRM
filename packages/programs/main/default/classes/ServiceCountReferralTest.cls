/**
 * Anonymous service counts (P-12, canonical model 29ZB1) and referrals (P-13, 29ZA2): counts kept
 * apart from named deliveries on the log and the dashboard, a referral that names exactly one
 * person, referrals out of reach of Read Only and deleted when their person is erased.
 */
@IsTest(testFor='ApexClass:ServiceCountSelector, ApexClass:ReferralSelector')
private class ServiceCountReferralTest {
	private static final String ADMIN = 'Programs_Admin';
	private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
		TestUsers.standardUserWith('Writer', STAFF);
		TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
		);
	}

	private static Contact person(String lastName) {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
		Contact record = HouseholdTestDataFactory.newContact('Pat', lastName);
		insert record;
		return record;
	}

	private static Service__c dropIn() {
		Program__c program = new Program__c(Name = 'Pantry', Status__c = 'Active');
		insert program;
		Service__c service = new Service__c(Program__c = program.Id, Name = 'Walk-in Meal');
		insert service;
		return service;
	}

	@IsTest
	static void theLogAddsCountsAndTotalsThemForTheDay() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Service__c service = dropIn();
			Date today = Date.today();

			ServiceDeliveryLogController.Log first = ServiceDeliveryLogController.addCount(
				service.Program__c,
				service.Id,
				today,
				12
			);
			ServiceDeliveryLogController.Log second = ServiceDeliveryLogController.addCount(
				service.Program__c,
				service.Id,
				today,
				8
			);
			ServiceDeliveryLogController.Log otherDay = ServiceDeliveryLogController.getLog(
				service.Program__c,
				service.Id,
				today.addDays(-1)
			);

			Assert.areEqual(12, first.peopleCounted, 'The first count.');
			Assert.areEqual(20, second.peopleCounted, 'Two counts in a day add up.');
			Assert.areEqual(0, otherDay.peopleCounted, 'Another day has none.');
			Assert.isTrue(second.canCount && second.canSeeCounts, 'An admin may count.');
			Assert.areEqual(2, [SELECT COUNT() FROM Service_Count__c], 'One row per count.');
		}
	}

	@IsTest
	static void aBadCountIsRefused() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Service__c service = dropIn();
			try {
				ServiceDeliveryLogController.addCount(
					service.Program__c,
					service.Id,
					Date.today(),
					-1
				);
				Assert.fail('A negative count must be refused.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Programs', 'Programs_Fail_Log'),
					refused.getMessage(),
					'Plain words.'
				);
			}
			try {
				ServiceDeliveryLogController.addCount(service.Program__c, null, Date.today(), 3);
				Assert.fail('A count needs a service.');
			} catch (AuraHandledException refused) {
				Assert.areEqual(
					BarnHelp.text('Programs', 'Programs_Fail_Log'),
					refused.getMessage(),
					'Plain words.'
				);
			}
		}
	}

	@IsTest
	static void aReaderSeesCountsButCannotAddThem() {
		Service__c service;
		System.runAs(TestUsers.adminWith(ADMIN)) {
			service = dropIn();
			insert new Service_Count__c(Service__c = service.Id, People_Served__c = 5);
		}
		System.runAs(TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
		)) {
			ServiceDeliveryLogController.Log log = ServiceDeliveryLogController.getLog(
				service.Program__c,
				service.Id,
				Date.today()
			);
			Assert.isTrue(log.canSeeCounts, 'A reader sees counts.');
			Assert.isFalse(log.canCount, 'But cannot add one.');
			Assert.areEqual(5, log.peopleCounted, 'The day total.');
		}
	}

	@IsTest
	static void theDashboardKeepsCountedPeopleApartFromNamedOnes() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Contact named = person('Dashboard');
			Service__c service = dropIn();
			Date today = Date.today();
			insert new Enrollment__c(Program__c = service.Program__c, Contact__c = named.Id);
			insert new Service_Delivery__c(
				Service__c = service.Id,
				Contact__c = named.Id,
				Delivery_Date__c = today,
				Attendance__c = 'Present'
			);
			insert new List<Service_Count__c>{
				new Service_Count__c(
					Service__c = service.Id,
					Count_Date__c = today,
					People_Served__c = 30
				),
				new Service_Count__c(
					Service__c = service.Id,
					Count_Date__c = today,
					People_Served__c = 4
				),
				new Service_Count__c(
					Service__c = service.Id,
					Count_Date__c = today.addYears(-2),
					People_Served__c = 99
				)
			};

			ProgramDashboardController.Dashboard result = ProgramDashboardController.getDashboard(
				today.toStartOfMonth(),
				today.toStartOfMonth().addMonths(1).addDays(-1)
			);

			Assert.areEqual(34, result.totals.peopleCounted, 'Counts in the period only.');
			Assert.areEqual(1, result.totals.peopleServed, 'Named people stay separate.');
			Assert.areEqual(34, result.programs[0].peopleCounted, 'Per program too.');
		}
	}

	@IsTest
	static void aCountCannotBeNegativeAndItsServiceIsKept() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Service__c service = dropIn();
			Database.SaveResult refused = Database.insert(
				new Service_Count__c(Service__c = service.Id, People_Served__c = -2),
				false
			);
			Assert.isFalse(refused.isSuccess(), 'R-SC1: never negative.');
			insert new Service_Count__c(Service__c = service.Id, People_Served__c = 2);
			Database.DeleteResult kept = Database.delete(service, false);
			Assert.isFalse(kept.isSuccess(), 'A service with counts cannot be deleted.');
		}
	}

	@IsTest
	static void aReferralNamesExactlyOnePerson() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Contact who = person('Referred');
			Account org = new Account(Name = 'Partner Org');
			insert org;

			Database.SaveResult neither = Database.insert(new Referral__c(), false);
			Database.SaveResult both = Database.insert(
				new Referral__c(Contact__c = who.Id, Account__c = org.Id),
				false
			);
			Referral__c fine = new Referral__c(
				Contact__c = who.Id,
				Other_Organization__c = 'Legal Aid',
				Direction__c = 'Out'
			);
			insert fine;

			Assert.isFalse(neither.isSuccess(), 'A person is needed.');
			Assert.isFalse(both.isSuccess(), 'Not both.');
			Referral__c stored = [
				SELECT Status__c, Direction__c, Referral_Date__c
				FROM Referral__c
				WHERE Id = :fine.Id
			];
			Assert.areEqual('Open', stored.Status__c, 'Open by default.');
			Assert.areEqual(Date.today(), stored.Referral_Date__c, 'Dated today by default.');
		}
	}

	@IsTest
	static void aReferralIsPrivateAndOutOfReachOfReadOnly() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Contact who = person('Private');
			Enrollment__c enrolled = new Enrollment__c(
				Program__c = dropIn().Program__c,
				Contact__c = who.Id
			);
			insert enrolled;
			insert new Referral__c(Contact__c = who.Id, Enrollment__c = enrolled.Id);
		}
		System.runAs(TestUsers.standardUserWith('Writer', STAFF)) {
			Assert.areEqual(
				0,
				[SELECT COUNT() FROM Referral__c WITH USER_MODE],
				'Staff do not see the admin referral.'
			);
		}
		System.runAs(TestUsers.standardUserWith(
			'Reader',
			new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
		)) {
			Assert.isFalse(
				Schema.SObjectType.Referral__c.isAccessible(),
				'Read Only has no access to referrals.'
			);
		}
	}

	@IsTest
	static void erasingAPersonDeletesTheirReferrals() {
		System.runAs(TestUsers.adminWith(ADMIN)) {
			Contact who = person('Erased');
			Contact other = person('Kept');
			insert new List<Referral__c>{
				new Referral__c(Contact__c = who.Id),
				new Referral__c(Contact__c = other.Id)
			};

			List<PersonErasure.Change> changes = new ProgramsErasureExtension().erase(who.Id);

			Assert.areEqual(1, changes.size(), 'One change: the referrals deleted.');
			Assert.areEqual(
				1,
				[SELECT COUNT() FROM Referral__c],
				'Only the other person referral is left.'
			);
		}
	}
}
