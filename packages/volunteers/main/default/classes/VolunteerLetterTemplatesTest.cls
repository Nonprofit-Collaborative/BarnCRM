/**
 * The volunteer letter templates (canonical model Section 29U): the shipped ones arrive once and
 * never overwrite an edit (R-VL5), one template per type is active (R-VL1), and only Volunteers
 * Admin writes them while a coordinator reads them.
 */
@IsTest(
    testFor='ApexClass:VolunteerLetterTemplates, ApexClass:VolunteerLetterTemplateTriggerHandler, ApexTrigger:VolunteerLetterTemplateTrigger'
)
private class VolunteerLetterTemplatesTest {
    private static final String COORDINATOR = 'TemplateCoordinator';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestUsers.standardUserWith(
                COORDINATOR,
                new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
            );
            VolunteerLetterTemplates.installDefaultsDuringInstall();
        }
    }

    private static Volunteer_Letter_Template__c shipped(String key) {
        return [
            SELECT Id, Body__c, Active__c
            FROM Volunteer_Letter_Template__c
            WHERE Template_Key__c = :key
        ];
    }

    @IsTest
    static void anUpgradeCopiesNothingTheOrgHasAndKeepsAnEdit() {
        List<Volunteer_Letter_Template__c> again;
        Test.startTest();
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            update new Volunteer_Letter_Template__c(
                Id = shipped('Hours_Letter').Id,
                Body__c = '<p>Ours</p>'
            );
            again = VolunteerLetterTemplates.installDefaultsDuringInstall();
        }
        Test.stopTest();

        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.isTrue(again.isEmpty(), 'Nothing copied twice.');
            Assert.areEqual('<p>Ours</p>', shipped('Hours_Letter').Body__c, 'The edit stays.');
            Assert.isTrue(shipped('Hours_Letter').Active__c, 'Each type arrived active.');
            Assert.isTrue(shipped('Certificate').Active__c, 'Each type arrived active.');
        }
    }

    @IsTest
    static void activatingATemplateDeactivatesTheOthersOfItsType() {
        List<Volunteer_Letter_Template__c> mine = new List<Volunteer_Letter_Template__c>();
        for (String name : new List<String>{ 'First', 'Second' }) {
            mine.add(
                new Volunteer_Letter_Template__c(
                    Name = name,
                    Type__c = VolunteerLetterTemplates.TYPE_HOURS_LETTER,
                    Body__c = '<p>{PersonName}</p>',
                    Active__c = true
                )
            );
        }
        Test.startTest();
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            insert mine;
        }
        Test.stopTest();

        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Volunteer_Letter_Template__c
                    WHERE Active__c = TRUE AND Type__c = :VolunteerLetterTemplates.TYPE_HOURS_LETTER
                ],
                'One active hours letter.'
            );
            Assert.isTrue(
                [SELECT Active__c FROM Volunteer_Letter_Template__c WHERE Name = 'Second']
                .Active__c,
                'The last one saved is the active one.'
            );
            Assert.isTrue(shipped('Certificate').Active__c, 'Another type is untouched.');
        }
    }

    @IsTest
    static void oneActiveTemplatePerTypeHoldsForA251RecordSave() {
        List<Volunteer_Letter_Template__c> mine = new List<Volunteer_Letter_Template__c>();
        for (Integer i = 0; i < 251; i++) {
            mine.add(
                new Volunteer_Letter_Template__c(
                    Name = 'Bulk ' + i,
                    Type__c = VolunteerLetterTemplates.TYPE_HOURS_LETTER,
                    Body__c = '<p>{PersonName}</p>',
                    Active__c = true
                )
            );
        }
        Test.startTest();
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            insert mine;
        }
        Test.stopTest();

        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            List<Volunteer_Letter_Template__c> active = [
                SELECT Name
                FROM Volunteer_Letter_Template__c
                WHERE Active__c = TRUE AND Type__c = :VolunteerLetterTemplates.TYPE_HOURS_LETTER
            ];
            Assert.areEqual(1, active.size(), 'One active hours letter after 251 saved active.');
            Assert.areEqual('Bulk 250', active[0].Name, 'The last one saved stays active.');
            Assert.isTrue(shipped('Certificate').Active__c, 'Another type is untouched.');
        }
    }

    @IsTest
    static void aCoordinatorReadsTemplatesButCannotWriteThem() {
        Integer seen;
        String refused;
        User coordinator = [SELECT Id FROM User WHERE LastName = :COORDINATOR LIMIT 1];
        Test.startTest();
        System.runAs(coordinator) {
            seen = [SELECT COUNT() FROM Volunteer_Letter_Template__c WITH USER_MODE];
            try {
                Database.update(
                    new Volunteer_Letter_Template__c(Id = shipped('Certificate').Id, Body__c = 'x'),
                    AccessLevel.USER_MODE
                );
            } catch (Exception denied) {
                refused = denied.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(2, seen, 'The coordinator reads both shipped templates.');
        Assert.isNotNull(refused, 'Only Volunteers Admin edits a template.');
    }
}
