/**
 * The Volunteer letter record action's Apex: what it offers whom, a preview, a saved letter, and
 * a refusal the screen can show. Run as Standard User coordinator and staff.
 */
@IsTest(testFor='ApexClass:VolunteerLetterController')
private class VolunteerLetterControllerTest {
    private static final String COORDINATOR = 'ActionCoordinator';
    private static final String STAFFER = 'ActionStaffer';
    private static final Date FROM_DATE = Date.newInstance(2026, 3, 1);
    private static final Date TO_DATE = Date.newInstance(2026, 3, 31);

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            User coordinator = TestUsers.standardUserWith(
                COORDINATOR,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
            );
            TestUsers.standardUserWith(
                STAFFER,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
            );
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(false, true);
            VolunteerLetterTemplates.installDefaultsDuringInstall();
            Contact person = VolunteersTestData.contact('Rivera', null);
            update new Contact(Id = person.Id, OwnerId = coordinator.Id);
            insert VolunteersTestData.newHours(
                person.Id,
                VolunteersTestData.job('Food pantry').Id,
                3
            );
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Id personId() {
        return [SELECT Id FROM Contact WHERE LastName = 'Rivera' WITH SYSTEM_MODE LIMIT 1].Id;
    }

    private static Id hoursLetterId() {
        return [
            SELECT Id
            FROM Volunteer_Letter_Template__c
            WHERE Template_Key__c = 'Hours_Letter'
            WITH SYSTEM_MODE
        ]
        .Id;
    }

    @IsTest
    static void aCoordinatorPreviewsAndSavesALetter() {
        Map<String, Object> context;
        Map<String, String> preview;
        Map<String, String> saved;
        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            context = VolunteerLetterController.getActionContext(personId());
            preview = VolunteerLetterController.preview(
                personId(),
                hoursLetterId(),
                FROM_DATE,
                TO_DATE
            );
            saved = VolunteerLetterController.generate(
                personId(),
                hoursLetterId(),
                FROM_DATE,
                TO_DATE
            );
        }
        Test.stopTest();

        Assert.isTrue((Boolean) context.get('canManage'), 'The coordinator may.');
        Assert.isTrue((Boolean) context.get('isPerson'), 'A contact is a person.');
        Assert.areEqual(2, ((List<Object>) context.get('templates')).size(), 'One per type.');
        Assert.isTrue(preview.get('body').contains(' 3 hours'), preview.get('body'));
        Assert.isNotNull(saved.get('versionId'), 'The letter is saved.');
        Assert.isNull(saved.get('skipReason'), 'Nothing skipped.');
    }

    @IsTest
    static void staffAndHouseholdsAreToldWhyNot() {
        Map<String, Object> staff;
        Map<String, Object> household;
        String refused;
        Account home;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            home = VolunteersTestData.household('Rivera Household');
        }
        Id person = personId();
        Id template = hoursLetterId();
        Test.startTest();
        System.runAs(user(STAFFER)) {
            staff = VolunteerLetterController.getActionContext(person);
        }
        System.runAs(user(COORDINATOR)) {
            household = VolunteerLetterController.getActionContext(home.Id);
            try {
                VolunteerLetterController.preview(person, template, TO_DATE, FROM_DATE);
            } catch (AuraHandledException shown) {
                refused = shown.getMessage();
            }
        }
        Test.stopTest();

        Assert.isFalse((Boolean) staff.get('canManage'), 'Staff hold no Manage Volunteers.');
        Assert.isTrue(((List<Object>) staff.get('templates')).isEmpty(), 'Nothing offered.');
        Assert.isFalse((Boolean) household.get('isPerson'), 'A household is not a person.');
        Assert.areEqual(
            Label.Volunteers_Letter_BadPeriod,
            refused,
            'The reason reaches the screen.'
        );
    }
}
