/**
 * The Programs records and their rules (canonical model Sections 29W to 29Y): one open
 * enrollment per person per program (R-EN2), always enforced; stage dates filled in (R-EN3),
 * switchable; one person per enrollment (R-EN1); end after start (R-PG1, R-EN4); a program with
 * enrollments kept (R-PG2); and what each permission set may do.
 */
@IsTest(
    testFor='ApexClass:EnrollmentService, ApexClass:EnrollmentRulesHandler, ApexClass:EnrollmentDatesHandler, ApexClass:EnrollmentIntegritySelector, ApexClass:EnrollmentSelector, ApexTrigger:EnrollmentTrigger'
)
private class EnrollmentRulesTest {
    private static final String ADMIN = 'Programs_Admin';
    private static final String CORE_STAFF = 'BarnCRM_Staff';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith('Staffer', new List<String>{ CORE_STAFF, 'Programs_Staff' });
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        );
    }

    private static User staffer() {
        return TestUsers.standardUserWith(
            'Staffer',
            new List<String>{ CORE_STAFF, 'Programs_Staff' }
        );
    }

    /** People are Contacts, with no household made for them, so the tests stay small. */
    private static void contactMode() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
    }

    private static List<Contact> people(Integer howMany) {
        List<Contact> records = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            records.add(HouseholdTestDataFactory.newContact('Pat', 'Person' + i));
        }
        insert records;
        return records;
    }

    private static Program__c program(String name) {
        Program__c record = new Program__c(Name = name, Status__c = 'Active');
        insert record;
        return record;
    }

    private static Enrollment__c newEnrollment(Id programId, Id contactId, String stage) {
        return new Enrollment__c(Program__c = programId, Contact__c = contactId, Stage__c = stage);
    }

    @IsTest
    static void aSecondOpenEnrollmentIsRefusedNamingTheProgramInBulk() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            List<Contact> persons = people(200);
            Program__c tutoring = program('Tutoring');
            List<Enrollment__c> first = new List<Enrollment__c>();
            for (Contact person : persons) {
                first.add(newEnrollment(tutoring.Id, person.Id, 'Applied'));
            }
            insert first;
            List<Enrollment__c> second = new List<Enrollment__c>();
            for (Contact person : persons) {
                second.add(newEnrollment(tutoring.Id, person.Id, 'Enrolled'));
            }

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(second, false);
            Test.stopTest();

            String expected = String.format(
                Label.Programs_Enrollment_AlreadyOpen,
                new List<String>{ 'Tutoring' }
            );
            for (Database.SaveResult result : results) {
                Assert.isFalse(result.isSuccess(), 'A second open enrollment is refused.');
                Assert.areEqual(
                    expected,
                    result.getErrors()[0].getMessage(),
                    'Naming the program.'
                );
            }
            Assert.areEqual(200, [SELECT COUNT() FROM Enrollment__c], 'Only the first ones stay.');
        }
    }

    @IsTest
    static void twoOpenEnrollmentsInOneSaveAreRefusedButOtherProgramsAreFine() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact person = people(1)[0];
            Program__c tutoring = program('Tutoring');
            Program__c pantry = program('Pantry');

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Enrollment__c>{
                    newEnrollment(tutoring.Id, person.Id, 'Enrolled'),
                    newEnrollment(tutoring.Id, person.Id, 'Applied'),
                    newEnrollment(pantry.Id, person.Id, 'Enrolled')
                },
                false
            );
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'The first is kept.');
            Assert.isFalse(results[1].isSuccess(), 'The second in the same program is refused.');
            Assert.isTrue(results[2].isSuccess(), 'Another program is another enrollment.');
        }
    }

    @IsTest
    static void aPersonEnrollsAgainOnceTheFirstHasEndedButCannotReopenIt() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact person = people(1)[0];
            Program__c tutoring = program('Tutoring');
            Enrollment__c first = newEnrollment(tutoring.Id, person.Id, 'Enrolled');
            insert first;
            first.Stage__c = 'Completed';
            update first;

            Test.startTest();
            Enrollment__c again = newEnrollment(tutoring.Id, person.Id, 'Enrolled');
            insert again;
            first.Stage__c = 'Enrolled';
            Database.SaveResult reopened = Database.update(first, false);
            Test.stopTest();

            Assert.isNotNull(again.Id, 'A person may enroll again once the first has ended.');
            Assert.isFalse(reopened.isSuccess(), 'Reopening the old one makes two open: refused.');
        }
    }

    @IsTest
    static void theRuleRunsWhileAutomationIsPausedButTheDatesDoNot() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact person = people(1)[0];
            Program__c tutoring = program('Tutoring');
            insert newEnrollment(tutoring.Id, person.Id, 'Enrolled');
            TestDataFactory.pausedSettings(1);
            Contact other = people(1)[0];

            Test.startTest();
            Database.SaveResult second = Database.insert(
                newEnrollment(tutoring.Id, person.Id, 'Applied'),
                false
            );
            Enrollment__c undated = newEnrollment(tutoring.Id, other.Id, 'Enrolled');
            insert undated;
            Test.stopTest();

            Assert.isFalse(second.isSuccess(), 'The rule always runs (ADR-0024).');
            Assert.isNull(
                [SELECT Start_Date__c FROM Enrollment__c WHERE Id = :undated.Id].Start_Date__c,
                'Filling in dates is work for the user, so pausing stops it.'
            );
        }
    }

    @IsTest
    static void undeletingAnOpenEnrollmentForSomeoneEnrolledSinceIsRefused() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact person = people(1)[0];
            Program__c tutoring = program('Tutoring');
            Enrollment__c old = newEnrollment(tutoring.Id, person.Id, 'Enrolled');
            insert old;
            delete old;
            insert newEnrollment(tutoring.Id, person.Id, 'Enrolled');

            Test.startTest();
            Database.UndeleteResult result = Database.undelete(old.Id, false);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'Restoring it would make two open enrollments.');
        }
    }

    @IsTest
    static void stageDatesAreFilledInAndTypedDatesKept() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            List<Contact> persons = people(3);
            Program__c tutoring = program('Tutoring');
            Date typed = Date.today().addDays(-30);
            Enrollment__c enrolled = newEnrollment(tutoring.Id, persons[0].Id, 'Enrolled');
            Enrollment__c applied = newEnrollment(tutoring.Id, persons[1].Id, 'Applied');
            Enrollment__c dated = newEnrollment(tutoring.Id, persons[2].Id, 'Enrolled');
            dated.Start_Date__c = typed;
            insert new List<Enrollment__c>{ enrolled, applied, dated };

            Test.startTest();
            enrolled.Stage__c = 'Withdrawn';
            applied.Stage__c = 'Enrolled';
            update new List<Enrollment__c>{ enrolled, applied };
            Test.stopTest();

            Map<Id, Enrollment__c> saved = new Map<Id, Enrollment__c>(
                [SELECT Id, Start_Date__c, End_Date__c FROM Enrollment__c]
            );
            Assert.areEqual(Date.today(), saved.get(enrolled.Id).Start_Date__c, 'Enrolled: start.');
            Assert.areEqual(Date.today(), saved.get(enrolled.Id).End_Date__c, 'Withdrawn: end.');
            Assert.areEqual(Date.today(), saved.get(applied.Id).Start_Date__c, 'Enrolled later.');
            Assert.isNull(saved.get(applied.Id).End_Date__c, 'Still open: no end.');
            Assert.areEqual(typed, saved.get(dated.Id).Start_Date__c, 'A typed date is kept.');
        }
    }

    @IsTest
    static void theEligibilityDateIsFilledInWhenEligibilityIsDecided() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
        }
        System.runAs(staffer()) {
            List<Contact> persons = people(3);
            Program__c pantry = program('Pantry');
            Date typed = Date.today().addDays(-10);
            Enrollment__c screened = newEnrollment(pantry.Id, persons[0].Id, 'Applied');
            screened.Eligibility_Status__c = 'Eligible';
            screened.Intake_Date__c = typed;
            screened.Referral_Source__c = 'Another Agency';
            screened.Eligibility_Basis__c = 'Income';
            Enrollment__c waiting = newEnrollment(pantry.Id, persons[1].Id, 'Applied');
            Enrollment__c dated = newEnrollment(pantry.Id, persons[2].Id, 'Applied');
            dated.Eligibility_Status__c = 'Not Eligible';
            dated.Eligibility_Date__c = typed;
            insert new List<Enrollment__c>{ screened, waiting, dated };

            Test.startTest();
            waiting.Eligibility_Status__c = 'Awaiting Documents';
            update waiting;
            Date afterWaiting = [
                SELECT Eligibility_Date__c
                FROM Enrollment__c
                WHERE Id = :waiting.Id
            ]
            .Eligibility_Date__c;
            waiting.Eligibility_Status__c = 'Not Eligible';
            update waiting;
            Test.stopTest();

            Map<Id, Enrollment__c> saved = new Map<Id, Enrollment__c>(
                [SELECT Id, Eligibility_Status__c, Eligibility_Date__c FROM Enrollment__c]
            );
            Assert.areEqual(Date.today(), saved.get(screened.Id).Eligibility_Date__c, 'Decided.');
            Assert.isNull(afterWaiting, 'Awaiting documents decides nothing.');
            Assert.areEqual(Date.today(), saved.get(waiting.Id).Eligibility_Date__c, 'Later.');
            Assert.areEqual(
                typed,
                saved.get(dated.Id).Eligibility_Date__c,
                'A typed date is kept.'
            );
        }
    }

    @IsTest
    static void aNewEnrollmentIsNotScreenedByDefault() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c pantry = program('Pantry');
            Enrollment__c fresh = newEnrollment(pantry.Id, people(1)[0].Id, 'Applied');
            insert fresh;
            Assert.areEqual(
                'Not Screened',
                [SELECT Eligibility_Status__c FROM Enrollment__c WHERE Id = :fresh.Id]
                .Eligibility_Status__c,
                'The shipped default.'
            );
        }
    }

    @IsTest
    static void anEnrollmentIsOnePersonAndEndsAfterItStarts() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact person = people(1)[0];
            Program__c tutoring = program('Tutoring');
            Enrollment__c nobody = new Enrollment__c(Program__c = tutoring.Id);
            Enrollment__c backwards = newEnrollment(tutoring.Id, person.Id, 'Completed');
            backwards.Start_Date__c = Date.today();
            backwards.End_Date__c = Date.today().addDays(-1);
            Program__c backwardsProgram = new Program__c(
                Name = 'Backwards',
                Start_Date__c = Date.today(),
                End_Date__c = Date.today().addDays(-1)
            );

            Test.startTest();
            Database.SaveResult noPerson = Database.insert(nobody, false);
            Database.SaveResult endBeforeStart = Database.insert(backwards, false);
            Database.SaveResult programBackwards = Database.insert(backwardsProgram, false);
            Test.stopTest();

            Assert.isFalse(noPerson.isSuccess(), 'An enrollment names a person (R-EN1).');
            Assert.isFalse(endBeforeStart.isSuccess(), 'End is not before start (R-EN4).');
            Assert.isFalse(programBackwards.isSuccess(), 'Nor for a program (R-PG1).');
        }
    }

    @IsTest
    static void aProgramWithEnrollmentsIsKeptAndOneWithoutGoesWithItsServices() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Contact person = people(1)[0];
            Program__c used = program('Used');
            Program__c unused = program('Unused');
            insert new Service__c(
                Name = 'Meal',
                Program__c = unused.Id,
                Unit_Of_Measure__c = 'meals'
            );
            insert newEnrollment(used.Id, person.Id, 'Enrolled');

            Test.startTest();
            Database.DeleteResult keep = Database.delete(used, false);
            delete unused;
            Test.stopTest();

            Assert.isFalse(keep.isSuccess(), 'A program with enrollments is kept (R-PG2).');
            Assert.areEqual(1, [SELECT COUNT() FROM Program__c], 'Only the unused one went.');
            Assert.areEqual(0, [SELECT COUNT() FROM Service__c], 'With its services.');
        }
    }

    @IsTest
    static void staffSetUpAndEnrollButNeverDelete() {
        Program__c tutoring;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
        }
        System.runAs(staffer()) {
            // A contact with no account is seen by its owner only, so the staffer adds their own.
            Contact person = people(1)[0];
            Test.startTest();
            tutoring = new Program__c(Name = 'Tutoring');
            insert as user tutoring;
            insert as user new Service__c(Name = 'Hour', Program__c = tutoring.Id);
            Enrollment__c enrollment = newEnrollment(tutoring.Id, person.Id, 'Applied');
            insert as user enrollment;
            enrollment.Stage__c = 'Enrolled';
            update as user enrollment;
            Boolean deleteRefused = false;
            try {
                delete as user enrollment;
            } catch (System.TypeException e) {
                deleteRefused = true;
            }
            Test.stopTest();

            Assert.isTrue(deleteRefused, 'Programs Staff never deletes.');
            Assert.areEqual(
                'Active',
                [SELECT Status__c FROM Program__c WHERE Id = :tutoring.Id WITH USER_MODE].Status__c,
                'A new program starts Active.'
            );
        }
    }

    @IsTest
    static void readOnlyUsersSeeButCannotEnroll() {
        Program__c tutoring;
        Contact person;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            person = people(1)[0];
            tutoring = program('Tutoring');
            insert newEnrollment(tutoring.Id, person.Id, 'Enrolled');
        }
        System.runAs(TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        )) {
            Test.startTest();
            Integer seen = [SELECT COUNT() FROM Enrollment__c WITH USER_MODE];
            Boolean refused = false;
            try {
                insert as user newEnrollment(tutoring.Id, person.Id, 'Applied');
            } catch (System.TypeException e) {
                refused = true;
            }
            Test.stopTest();

            Assert.areEqual(1, seen, 'Read Only sees enrollments.');
            Assert.isTrue(refused, 'And creates none.');
        }
    }
}
