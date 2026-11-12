/**
 * Cohorts (P-11, canonical model 29ZA5): the Cohort Members panel's server side, mass enrollment
 * where each person succeeds or fails alone (R-CO3), removing a member, the rule that an
 * enrollment's cohort is of its program (R-EN8) and the cohort's dates (R-CO2).
 */
@IsTest(testFor='ApexClass:CohortController, ApexClass:CohortService, ApexClass:CohortSelector')
private class CohortControllerTest {
	private static final String ADMIN = 'Programs_Admin';
	private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };
	private static final List<String> READER = new List<String>{
		'BarnCRM_Read_Only',
		'Programs_Read_Only'
	};

	@TestSetup
	static void createTestUsers() {
		TestUsers.adminWith(ADMIN);
	}

	private static User admin() {
		return TestUsers.adminWith(ADMIN);
	}

	private static void contactMode() {
		BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
			HouseholdTestDataFactory.MODE_CONTACT
		);
		settings.Auto_Create_Households__c = false;
		TestDataFactory.saveSettings(settings);
	}

	private static Contact person(String lastName) {
		Contact record = HouseholdTestDataFactory.newContact('Pat', lastName);
		insert record;
		return record;
	}

	private static Cohort__c springOf(Program__c program) {
		Cohort__c cohort = new Cohort__c(Name = 'Spring', Program__c = program.Id);
		insert cohort;
		return cohort;
	}

	private static Set<String> namesOf(List<CohortController.Member> members) {
		Set<String> names = new Set<String>();
		for (CohortController.Member member : members) {
			names.add(member.personName);
		}
		return names;
	}

	@IsTest
	static void addsManyPeopleEachAloneAndEnrollsThoseWithNoOpenEnrollment() {
		System.runAs(admin()) {
			contactMode();
			Program__c course = new Program__c(Name = 'Job Readiness');
			Program__c other = new Program__c(Name = 'Pantry');
			insert new List<Program__c>{ course, other };
			Cohort__c spring = springOf(course);
			Contact ana = person('Ana');
			Contact ben = person('Ben');
			Contact cara = person('Cara');
			Contact gone = person('Gone');
			Enrollment__c anaOpen = new Enrollment__c(Program__c = course.Id, Contact__c = ana.Id);
			Enrollment__c caraEnded = new Enrollment__c(
				Program__c = course.Id,
				Contact__c = cara.Id,
				Stage__c = 'Completed'
			);
			Enrollment__c elsewhere = new Enrollment__c(Program__c = other.Id, Contact__c = ben.Id);
			insert new List<Enrollment__c>{ anaOpen, caraEnded, elsewhere };
			Id goneId = gone.Id;
			delete gone;

			Test.startTest();
			CohortController.Members before = CohortController.getMembers(spring.Id);
			CohortController.Members after = CohortController.addMembers(
				spring.Id,
				new List<Id>{ anaOpen.Id, elsewhere.Id },
				new List<Id>{ ben.Id, cara.Id, goneId }
			);
			Test.stopTest();

			Assert.areEqual(0, before.members.size(), 'Nobody yet.');
			Assert.areEqual(1, before.candidates.size(), 'Ana: open and in no cohort.');
			Assert.isTrue(before.canEdit && before.canEnroll, 'The admin may add and enroll.');
			Assert.areEqual(3, after.added, 'Ana moved in; Ben and Cara enrolled in it.');
			Assert.areEqual(2, after.failures.size(), 'Each refused alone.');
			Assert.areEqual(
				BarnHelp.text('Programs', 'Programs_Cohort_NotOpen'),
				after.failures[0].message
			);
			Assert.areEqual(
				new Set<String>{ 'Pat Ana', 'Pat Ben', 'Pat Cara' },
				namesOf(after.members)
			);
			Assert.areEqual(0, after.candidates.size(), 'Nobody left to add.');
			Enrollment__c benNew = [
				SELECT Stage__c, Cohort__c, Start_Date__c
				FROM Enrollment__c
				WHERE Contact__c = :ben.Id AND Program__c = :course.Id
				WITH SYSTEM_MODE
			];
			Assert.areEqual('Enrolled', benNew.Stage__c, 'Enrolled at stage Enrolled.');
			Assert.areEqual(spring.Id, benNew.Cohort__c);
			Assert.areEqual(Date.today(), benNew.Start_Date__c, 'Through the enrollment rules.');
			Assert.areEqual(
				null,
				[SELECT Cohort__c FROM Enrollment__c WHERE Id = :caraEnded.Id WITH SYSTEM_MODE]
				.Cohort__c,
				'An ended enrollment is left alone.'
			);
		}
	}

	@IsTest
	static void removingAMemberKeepsTheEnrollment() {
		System.runAs(admin()) {
			contactMode();
			Program__c course = new Program__c(Name = 'Job Readiness');
			insert course;
			Cohort__c spring = springOf(course);
			Enrollment__c ana = new Enrollment__c(
				Program__c = course.Id,
				Contact__c = person('Ana').Id,
				Cohort__c = spring.Id
			);
			Enrollment__c ben = new Enrollment__c(
				Program__c = course.Id,
				Contact__c = person('Ben').Id
			);
			insert new List<Enrollment__c>{ ana, ben };

			Test.startTest();
			CohortController.Members after = CohortController.removeMember(spring.Id, ana.Id);
			String refusal;
			try {
				CohortController.removeMember(spring.Id, ben.Id);
			} catch (AuraHandledException refused) {
				refusal = refused.getMessage();
			}
			Test.stopTest();

			Assert.areEqual(0, after.members.size(), 'Out of the cohort.');
			Assert.areEqual(2, after.candidates.size(), 'Both may be added again.');
			Assert.areEqual(2, [SELECT COUNT() FROM Enrollment__c WITH SYSTEM_MODE], 'Kept.');
			Assert.areEqual(
				BarnHelp.text('Programs', 'Programs_Cohort_NotFoundOne'),
				refusal,
				'Not a member.'
			);
		}
	}

	@IsTest
	static void anEnrollmentsCohortMustBeOfItsProgramAndACohortEndsAfterItStarts() {
		System.runAs(admin()) {
			contactMode();
			Program__c course = new Program__c(Name = 'Job Readiness');
			Program__c other = new Program__c(Name = 'Pantry');
			insert new List<Program__c>{ course, other };
			Cohort__c elsewhere = springOf(other);

			Test.startTest();
			Database.SaveResult wrongCohort = Database.insert(
				new Enrollment__c(
					Program__c = course.Id,
					Contact__c = person('Ana').Id,
					Cohort__c = elsewhere.Id
				),
				false
			);
			Database.SaveResult backwards = Database.insert(
				new Cohort__c(
					Name = 'Backwards',
					Program__c = course.Id,
					Start_Date__c = Date.newInstance(2027, 3, 1),
					End_Date__c = Date.newInstance(2027, 2, 1)
				),
				false
			);
			Test.stopTest();

			Assert.isFalse(wrongCohort.isSuccess(), 'R-EN8: a cohort of another program.');
			Assert.isFalse(backwards.isSuccess(), 'R-CO2: end before start.');
		}
	}

	@IsTest
	static void staffAddPeopleAndReadOnlyChangesNothing() {
		Program__c course = new Program__c(Name = 'Job Readiness');
		Cohort__c spring;
		Contact ana;
		User staff = TestUsers.standardUserWith('Coordinator', STAFF);
		User reader = TestUsers.standardUserWith('Reader', READER);
		System.runAs(admin()) {
			contactMode();
			insert course;
			spring = springOf(course);
		}

		Test.startTest();
		CohortController.Members byStaff;
		CohortController.Members readerView;
		CohortController.Members byReader;
		System.runAs(staff) {
			ana = person('Ana');
			byStaff = CohortController.addMembers(spring.Id, null, new List<Id>{ ana.Id });
		}
		System.runAs(reader) {
			readerView = CohortController.getMembers(spring.Id);
			byReader = CohortController.addMembers(spring.Id, null, new List<Id>{ ana.Id });
		}
		Test.stopTest();

		Assert.areEqual(1, byStaff.added, 'Staff enroll a person into the cohort.');
		Assert.isTrue(byStaff.canEnroll);
		Assert.isFalse(readerView.canEdit, 'Read Only sees no controls.');
		Assert.areEqual(0, byReader.added, 'Read Only adds nobody.');
		Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c WITH SYSTEM_MODE]);
	}

	@IsTest
	static void refusesNobodyTooManyAndAMissingCohort() {
		List<Id> many = new List<Id>();
		for (Integer i = 0; i <= CohortController.MAX_SHOWN; i++) {
			many.add(UserInfo.getUserId());
		}
		List<String> refusals = new List<String>();
		Test.startTest();
		System.runAs(admin()) {
			for (Integer attempt = 0; attempt < 4; attempt++) {
				try {
					switch on attempt {
						when 0 {
							CohortController.addMembers(null, null, new List<Id>());
						}
						when 1 {
							CohortController.addMembers(null, many, null);
						}
						when 2 {
							CohortController.getMembers(null);
						}
						when else {
							CohortController.removeMember(null, null);
						}
					}
				} catch (AuraHandledException refused) {
					refusals.add(refused.getMessage());
				}
			}
		}
		Test.stopTest();
		Assert.areEqual(
			new List<String>{
				BarnHelp.text('Programs', 'Programs_Cohort_NobodyChosen'),
				String.format(
					BarnHelp.text('Programs', 'Programs_Cohort_TooMany'),
					new List<Object>{ CohortController.MAX_SHOWN }
				),
				BarnHelp.text('Programs', 'Programs_Cohort_NotFound'),
				BarnHelp.text('Programs', 'Programs_Fail_Cohort')
			},
			refusals
		);
	}

	@IsTest
	static void aPickedPersonIsNamed() {
		System.runAs(admin()) {
			contactMode();
			Contact ana = person('Ana');
			Test.startTest();
			String name = CohortController.getPersonName(ana.Id);
			String none = CohortController.getPersonName(null);
			Test.stopTest();
			Assert.areEqual('Pat Ana', name);
			Assert.isNull(none);
		}
	}
}
