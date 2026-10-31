/**
 * The Programs card on a person: their enrollments, open ones first, for a contact or a person
 * account; no card for a household, no record, or a user who cannot read enrollments.
 */
@IsTest(testFor='ApexClass:PersonEnrollmentsController, ApexClass:EnrollmentSelector')
private class PersonEnrollmentsControllerTest {
    private static final String ADMIN = 'Programs_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith('Noprograms', new List<String>{ 'BarnCRM_Read_Only' });
    }

    private static void contactMode() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
    }

    private static Program__c program(String name) {
        Program__c record = new Program__c(Name = name);
        insert record;
        return record;
    }

    @IsTest
    static void listsAContactsEnrollmentsOpenOnesFirst() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
            insert ana;
            Program__c reading = program('Summer Reading');
            Program__c tutoring = program('Tutoring');
            insert new List<Enrollment__c>{
                new Enrollment__c(
                    Program__c = reading.Id,
                    Contact__c = ana.Id,
                    Stage__c = 'Completed',
                    Start_Date__c = Date.today().addDays(-10),
                    End_Date__c = Date.today().addDays(-5)
                ),
                new Enrollment__c(
                    Program__c = tutoring.Id,
                    Contact__c = ana.Id,
                    Start_Date__c = Date.today().addDays(-20)
                )
            };

            Test.startTest();
            PersonEnrollmentsController.PersonEnrollments result = PersonEnrollmentsController.getEnrollments(
                ana.Id
            );
            Test.stopTest();

            Assert.isTrue(result.canSee, 'A contact is a person.');
            Assert.areEqual(2, result.enrollments.size(), 'Both enrollments are listed.');
            Assert.areEqual('Tutoring', result.enrollments[0].programName, 'The open one first.');
            Assert.isTrue(result.enrollments[0].isOpen, 'And it is open.');
            Assert.areEqual('Completed', result.enrollments[1].stageLabel, 'With its stage.');
            Assert.isFalse(result.moreThanShown, 'Nothing left out.');
            Assert.isNull(result.lastServiceDate, 'No service yet.');
            Assert.areEqual(0, result.servicesAttended, 'None attended.');
        }
    }

    @IsTest
    static void showsTheLastServiceAttendedAndHowMany() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
            insert ana;
            Service__c meal = new Service__c(Name = 'Meal', Program__c = program('Pantry').Id);
            insert meal;
            insert new List<Service_Delivery__c>{
                new Service_Delivery__c(
                    Service__c = meal.Id,
                    Contact__c = ana.Id,
                    Delivery_Date__c = Date.today().addDays(-7)
                ),
                new Service_Delivery__c(
                    Service__c = meal.Id,
                    Contact__c = ana.Id,
                    Delivery_Date__c = Date.today().addDays(-3)
                ),
                new Service_Delivery__c(
                    Service__c = meal.Id,
                    Contact__c = ana.Id,
                    Delivery_Date__c = Date.today(),
                    Attendance__c = 'Unexcused Absence',
                    Quantity__c = 0
                )
            };

            Test.startTest();
            PersonEnrollmentsController.PersonEnrollments result = PersonEnrollmentsController.getEnrollments(
                ana.Id
            );
            Test.stopTest();

            Assert.areEqual(
                Date.today().addDays(-3),
                result.lastServiceDate,
                'The absence is not a service.'
            );
            Assert.areEqual(2, result.servicesAttended, 'Two attended.');
        }
    }

    @IsTest
    static void aHouseholdOrNoRecordShowsNothing() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Account family = HouseholdTestDataFactory.newHousehold('The Rivera Family');
            Database.insert(family, AccessLevel.SYSTEM_MODE);

            Assert.isFalse(
                PersonEnrollmentsController.getEnrollments(family.Id).canSee,
                'A household is not a person.'
            );
            Assert.isFalse(PersonEnrollmentsController.getEnrollments(null).canSee, 'No record.');
        }
    }

    @IsTest
    static void aUserWithoutProgramsGetsNoCard() {
        Contact ana;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            ana = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
            insert ana;
        }
        System.runAs(TestUsers.standardUserWith(
            'Noprograms',
            new List<String>{ 'BarnCRM_Read_Only' }
        )) {
            Assert.isFalse(
                PersonEnrollmentsController.getEnrollments(ana.Id).canSee,
                'Without a Programs set there is no card.'
            );
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountIsRead() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            if (
                !OrgShapeDetector.hasPersonAccounts() ||
                OrgShapeDetector.creatablePersonRecordTypeId() == null
            ) {
                return; // An org without person accounts has no such person.
            }
            Account person = new Account();
            person.put('LastName', 'Lindqvist');
            person.put('RecordTypeId', OrgShapeDetector.creatablePersonRecordTypeId());
            insert person;
            Program__c tutoring = program('Tutoring');
            insert new Enrollment__c(Program__c = tutoring.Id, Account__c = person.Id);

            PersonEnrollmentsController.PersonEnrollments result = PersonEnrollmentsController.getEnrollments(
                person.Id
            );

            Assert.isTrue(result.canSee, 'A person account is a person.');
            Assert.areEqual(1, result.enrollments.size(), 'Their enrollment is read.');
        }
    }
}
