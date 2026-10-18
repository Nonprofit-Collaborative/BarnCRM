/**
 * The readiness card's data (R-VQ3): each Type's most recent row or not started, whether it is
 * current, in user mode, so a coordinator sees it and a Team Member or Read Only user gets
 * nothing; a household shows nothing; a person held as an account is read where the org has them.
 */
@IsTest(testFor='ApexClass:VolunteerReadinessController')
private class VolunteerReadinessControllerTest {
    private static final String COORDINATOR = 'ReadyCoordinator';
    private static final String STAFFER = 'ReadyStaffer';
    private static final String READER = 'ReadyReader';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestUsers.standardUserWith(
                COORDINATOR,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
            );
            TestUsers.standardUserWith(
                STAFFER,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
            );
            TestUsers.standardUserWith(
                READER,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Read_Only' }
            );
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Map<String, VolunteerReadinessController.Step> byType(
        VolunteerReadinessController.Readiness readiness
    ) {
        Map<String, VolunteerReadinessController.Step> steps = new Map<String, VolunteerReadinessController.Step>();
        for (VolunteerReadinessController.Step step : readiness.steps) {
            steps.put(step.type, step);
        }
        return steps;
    }

    /** Ana Rivera: an application refused then restarted, a current check, no orientation. */
    private static Contact ana() {
        VolunteersTestData.contactModeWithoutAutomaticHouseholds();
        Contact person = VolunteersTestData.contact('Rivera', null);
        insert new Volunteer_Requirement__c(
            Contact__c = person.Id,
            Type__c = 'Application',
            Status__c = 'Not approved'
        );
        insert new Volunteer_Requirement__c(
            Contact__c = person.Id,
            Type__c = 'Application',
            Status__c = 'In progress'
        );
        insert new Volunteer_Requirement__c(
            Contact__c = person.Id,
            Type__c = 'Background check',
            Status__c = 'Completed',
            Completed_Date__c = System.today().addDays(-10),
            Expires__c = System.today().addYears(2)
        );
        return person;
    }

    @IsTest
    static void eachTypeShowsItsMostRecentRowOrNotStarted() {
        Contact person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = ana();
        }

        System.runAs(user(COORDINATOR)) {
            VolunteerReadinessController.Readiness readiness = VolunteerReadinessController.getReadiness(
                person.Id
            );

            Assert.isTrue(readiness.canSee, 'A coordinator sees requirements');
            Map<String, VolunteerReadinessController.Step> steps = byType(readiness);
            Assert.areEqual(
                'In progress',
                steps.get('Application').statusLabel,
                'The most recent application, not the refused one'
            );
            Assert.isFalse(steps.get('Application').isCurrent, 'In progress is not current');
            Assert.isTrue(steps.get('Background check').isCurrent, 'A valid check is current');
            Assert.areEqual(
                System.today().addYears(2),
                steps.get('Background check').expires,
                'With its expiry'
            );
            Assert.isNull(
                steps.get('Orientation').requirementId,
                'A Type with no row is not started'
            );
            Assert.areEqual('Application', readiness.steps[0].type, 'Types in picklist order');
        }
    }

    @IsTest
    static void aLapsedStepIsNotCurrent() {
        Contact person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            person = VolunteersTestData.contact('Okafor', null);
            insert new Volunteer_Requirement__c(
                Contact__c = person.Id,
                Type__c = 'Orientation',
                Status__c = 'Completed',
                Completed_Date__c = System.today().addYears(-3),
                Expires__c = System.today().addDays(-1)
            );

            VolunteerReadinessController.Step orientation = byType(
                    VolunteerReadinessController.getReadiness(person.Id)
                )
                .get('Orientation');

            Assert.isNotNull(orientation.requirementId, 'The row is shown');
            Assert.isFalse(orientation.isCurrent, 'Expired yesterday, so not current');
        }
    }

    @IsTest
    static void teamMembersAndReadOnlyUsersGetNothing() {
        Contact person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = ana();
        }
        for (String lastName : new List<String>{ STAFFER, READER }) {
            System.runAs(user(lastName)) {
                VolunteerReadinessController.Readiness readiness = VolunteerReadinessController.getReadiness(
                    person.Id
                );
                Assert.isFalse(readiness.canSee, lastName + ' cannot see requirements');
                Assert.isTrue(readiness.steps.isEmpty(), lastName + ' gets no step');
            }
        }
    }

    @IsTest
    static void aHouseholdOrNoRecordShowsNothing() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Account family = VolunteersTestData.household('The Rivera Family');

            Assert.isFalse(
                VolunteerReadinessController.getReadiness(family.Id).canSee,
                'A household is not a person'
            );
            Assert.isFalse(VolunteerReadinessController.getReadiness(null).canSee, 'No record');
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountIsRead() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Account person = VolunteersTestData.personAccount('Lindqvist');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            insert new Volunteer_Requirement__c(
                Account__c = person.Id,
                Type__c = 'Background check',
                Status__c = 'In progress'
            );

            VolunteerReadinessController.Readiness readiness = VolunteerReadinessController.getReadiness(
                person.Id
            );

            Assert.isTrue(readiness.canSee, 'A person account is a person');
            Assert.areEqual(
                'In progress',
                byType(readiness).get('Background check').statusLabel,
                'Their check is read'
            );
        }
    }
}
