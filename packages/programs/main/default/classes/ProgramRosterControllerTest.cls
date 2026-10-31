/**
 * The Program Roster panel's server side: the stage counts, the open (or all) enrollments, enrolling
 * a person and changing a stage, each through the enrollment rules, and refusals passed on in
 * their own words.
 */
@IsTest(testFor='ApexClass:ProgramRosterController, ApexClass:EnrollmentSelector')
private class ProgramRosterControllerTest {
    private static final String ADMIN = 'Programs_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        );
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

    private static Program__c program() {
        Program__c record = new Program__c(Name = 'Tutoring');
        insert record;
        return record;
    }

    private static Integer countAt(ProgramRosterController.Roster roster, String stage) {
        for (ProgramRosterController.Option option : roster.stages) {
            if (option.value == stage) {
                return option.count;
            }
        }
        return null;
    }

    @IsTest
    static void listsOpenEnrollmentsAndCountsEveryStage() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = program();
            Contact ana = person('Rivera');
            Contact ben = person('Okafor');
            insert new List<Enrollment__c>{
                new Enrollment__c(Program__c = tutoring.Id, Contact__c = ana.Id),
                new Enrollment__c(
                    Program__c = tutoring.Id,
                    Contact__c = ben.Id,
                    Stage__c = 'Completed'
                )
            };

            Test.startTest();
            ProgramRosterController.Roster open = ProgramRosterController.getRoster(
                tutoring.Id,
                false
            );
            ProgramRosterController.Roster all = ProgramRosterController.getRoster(
                tutoring.Id,
                true
            );
            Test.stopTest();

            Assert.areEqual('Tutoring', open.programName, 'The program is named.');
            Assert.areEqual(4, open.stages.size(), 'Every stage has a figure.');
            Assert.areEqual(1, countAt(open, 'Enrolled'), 'One enrolled.');
            Assert.areEqual(1, countAt(open, 'Completed'), 'One completed.');
            Assert.areEqual(1, open.enrollments.size(), 'Only the open one is listed.');
            Assert.areEqual('Pat Rivera', open.enrollments[0].personName, 'By the person name.');
            Assert.areEqual(2, all.enrollments.size(), 'Show Ended lists both.');
            Assert.isTrue(open.canAdd && open.canEdit, 'An admin enrolls and edits.');
        }
    }

    @IsTest
    static void enrollsAPersonAndChangesTheirStage() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = program();
            Contact ana = person('Rivera');

            Test.startTest();
            ProgramRosterController.Roster enrolled = ProgramRosterController.enroll(
                tutoring.Id,
                ana.Id,
                'Applied',
                false
            );
            Id enrollmentId = enrolled.enrollments[0].recordId;
            ProgramRosterController.Roster withdrawn = ProgramRosterController.setStage(
                enrollmentId,
                'Withdrawn',
                false
            );
            Test.stopTest();

            Assert.areEqual(
                'Applied',
                enrolled.enrollments[0].stage,
                'Enrolled at the stage chosen.'
            );
            Assert.isTrue(withdrawn.enrollments.isEmpty(), 'An ended enrollment leaves the list.');
            Assert.areEqual(
                Date.today(),
                [SELECT End_Date__c FROM Enrollment__c WHERE Id = :enrollmentId].End_Date__c,
                'And its end date is filled in.'
            );
        }
    }

    @IsTest
    static void aSecondOpenEnrollmentIsRefusedInItsOwnWords() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = program();
            Contact ana = person('Rivera');
            ProgramRosterController.enroll(tutoring.Id, ana.Id, null, false);
            String message;

            Test.startTest();
            try {
                ProgramRosterController.enroll(tutoring.Id, ana.Id, 'Applied', false);
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                String.format(
                    Label.Programs_Enrollment_AlreadyOpen,
                    new List<String>{ 'Tutoring' }
                ),
                message,
                'The rule speaks for itself.'
            );
        }
    }

    @IsTest
    static void badRequestsAreRefusedPlainly() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            Program__c tutoring = program();
            List<String> messages = new List<String>();

            Test.startTest();
            try {
                ProgramRosterController.enroll(tutoring.Id, null, null, false);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            try {
                ProgramRosterController.getRoster(null, false);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            try {
                ProgramRosterController.setStage(tutoring.Id, 'Not a stage', false);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            try {
                ProgramRosterController.enroll(null, tutoring.Id, null, false);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            Test.stopTest();

            Assert.areEqual(
                new List<String>{
                    Label.Programs_Roster_PersonRequired,
                    Label.Programs_Roster_ActionFailed,
                    Label.Programs_Roster_ActionFailed,
                    Label.Programs_Roster_ActionFailed
                },
                messages,
                'Each bad request is refused with a plain message.'
            );
        }
    }

    @IsTest
    static void readOnlyUsersSeeTheRosterButMayNotChangeIt() {
        Program__c tutoring;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            contactMode();
            tutoring = program();
        }
        System.runAs(TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Programs_Read_Only' }
        )) {
            Test.startTest();
            ProgramRosterController.Roster roster = ProgramRosterController.getRoster(
                tutoring.Id,
                false
            );
            Test.stopTest();

            Assert.isFalse(roster.canAdd, 'Read Only adds no one.');
            Assert.isFalse(roster.canEdit, 'And changes no stage.');
        }
    }
}
