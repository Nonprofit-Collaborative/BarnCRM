/**
 * Deleting a person deletes their requirement rows and volunteer skills (R-VQ5, R-VK4), 251 at a
 * time, whoever deletes them; a merge keeps them on the person kept; an account takes its
 * contacts' rows with it; and a person held as an account is covered where the org has them.
 */
@IsTest(
    testFor='ApexClass:VolunteerPersonDeleteHandler, ApexClass:VolunteerIntegritySelector, ApexTrigger:ContactTrigger, ApexTrigger:AccountTrigger'
)
private class VolunteerPersonDeleteHandlerTest {
    private static final Integer ROWS = 251;
    private static final String DELETER = 'PersonDeleter';

    @TestSetup
    static void makeUsers() {
        TestUsers.adminWith(VolunteersTestData.ADMIN);
        // On the standard profile, so nothing but the permission set gives access.
        TestUsers.standardUserWith(DELETER, new List<String>{ TestUsers.CORE_ADMIN });
    }

    private static User deleter() {
        return [SELECT Id FROM User WHERE LastName = :DELETER AND IsActive = TRUE LIMIT 1];
    }

    private static User volunteersAdmin() {
        return TestUsers.adminWith(VolunteersTestData.ADMIN);
    }

    private static Skill__c skill() {
        Skill__c record = new Skill__c(Name = 'Spanish', Active__c = true);
        insert record;
        return record;
    }

    /** One background check and one skill for each person, as a Contact or an Account. */
    private static void giveRows(List<SObject> people, Id skillId) {
        List<Volunteer_Requirement__c> checks = new List<Volunteer_Requirement__c>();
        List<Volunteer_Skill__c> skills = new List<Volunteer_Skill__c>();
        for (SObject person : people) {
            String field = person.getSObjectType() == Contact.SObjectType
                ? 'Contact__c'
                : 'Account__c';
            Volunteer_Requirement__c check = new Volunteer_Requirement__c(
                Type__c = 'Background check',
                Status__c = 'Completed',
                Completed_Date__c = System.today().addDays(-3)
            );
            Volunteer_Skill__c held = new Volunteer_Skill__c(Skill__c = skillId);
            check.put(field, person.Id);
            held.put(field, person.Id);
            checks.add(check);
            skills.add(held);
        }
        insert checks;
        insert skills;
    }

    private static Integer rowsLeft() {
        return [SELECT COUNT() FROM Volunteer_Requirement__c] +
            [SELECT COUNT() FROM Volunteer_Skill__c];
    }

    @IsTest
    static void deleting251PeopleDeletesTheirRowsAndKeepsEveryoneElses() {
        List<Contact> leaving;
        Contact staying;
        System.runAs(volunteersAdmin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Id spanish = skill().Id;
            leaving = VolunteersTestData.contacts(ROWS);
            staying = VolunteersTestData.contact('Staying', null);
            List<SObject> everyone = new List<SObject>{ staying };
            everyone.addAll(leaving);
            giveRows(everyone, spanish);
        }

        // A BarnCRM admin without any Volunteers set: they cannot see requirements at all.
        System.runAs(deleter()) {
            Assert.isFalse(
                Schema.SObjectType.Volunteer_Requirement__c.isAccessible(),
                'The person deleting cannot see requirements'
            );
            Test.startTest();
            delete leaving;
            Test.stopTest();
        }

        System.runAs(volunteersAdmin()) {
            Assert.areEqual(2, rowsLeft(), 'Only the remaining person keeps rows');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__c = :staying.Id],
                'The remaining person keeps their background check'
            );
            Assert.areEqual(
                ROWS * 2,
                [
                    SELECT COUNT()
                    FROM Volunteer_Requirement__c
                    WHERE IsDeleted = TRUE AND Contact__c = NULL
                    ALL ROWS
                ] +
                [
                    SELECT COUNT()
                    FROM Volunteer_Skill__c
                    WHERE IsDeleted = TRUE AND Contact__c = NULL
                    ALL ROWS
                ],
                'Each deleted person took one requirement and one skill with them'
            );
        }
    }

    /** The people as the trigger hands them to the handler: by Id, with their MasterRecordId. */
    private static Map<Id, SObject> triggerOld(List<Contact> people) {
        return new Map<Id, SObject>(
            [SELECT Id, MasterRecordId FROM Contact WHERE Id IN :people ORDER BY Id]
        );
    }

    private static void runDeletePass(Map<Id, SObject> people) {
        TriggerHandler.setTestRecords(null, people);
        VolunteerPersonDeleteHandler handler = new VolunteerPersonDeleteHandler();
        handler.beforeDelete();
        handler.afterDelete();
    }

    @IsTest
    static void aRetriedBatchStillDeletesTheRowsOfThePeopleThatRemain() {
        System.runAs(volunteersAdmin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Id spanish = skill().Id;
            List<Contact> people = VolunteersTestData.contacts(3);
            giveRows(people, spanish);
            Map<Id, SObject> everyone = triggerOld(people);
            Savepoint beforeFirstPass = Database.setSavepoint();

            runDeletePass(everyone);
            Assert.areEqual(0, rowsLeft(), 'The first pass deleted every row.');

            // One person's delete fails, so the platform rolls the batch back and runs the
            // triggers again for the two that remain.
            Database.rollback(beforeFirstPass);
            Assert.areEqual(6, rowsLeft(), 'The rollback brought the rows back.');
            everyone.remove(people[2].Id);
            runDeletePass(everyone);

            Assert.areEqual(
                2,
                rowsLeft(),
                'The retry deleted the rows of the two that remain and left the third person\'s.'
            );
        }
    }

    @IsTest
    static void aBatchWhereOneDeleteFailsStillDeletesTheRowsOfTheOthers() {
        System.runAs(volunteersAdmin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Id spanish = skill().Id;
            List<Contact> people = VolunteersTestData.contacts(3);
            giveRows(people, spanish);
            Contact gone = people[2];
            delete gone;
            Assert.areEqual(4, rowsLeft(), 'Deleting the third took its two rows.');
            // The third is already deleted, so its row of the list fails and the others go.
            Test.startTest();
            List<Database.DeleteResult> results = Database.delete(people, false);
            Test.stopTest();

            Integer failed = 0;
            for (Database.DeleteResult result : results) {
                failed += result.isSuccess() ? 0 : 1;
            }
            Assert.areEqual(1, failed, 'One row of the batch failed.');
            Assert.areEqual(
                0,
                rowsLeft(),
                'The rows of the people whose delete succeeded are deleted.'
            );
        }
    }

    @IsTest
    static void aMergeKeepsTheBackgroundCheckOnThePersonKept() {
        System.runAs(volunteersAdmin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Id spanish = skill().Id;
            Contact kept = VolunteersTestData.contact('Okafor', null);
            Contact duplicate = VolunteersTestData.contact('Okafor', null);
            giveRows(new List<SObject>{ duplicate }, spanish);

            Test.startTest();
            Database.merge(kept, duplicate.Id);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__c = :kept.Id],
                'The merge moved the background check to the person kept'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Contact__c = :kept.Id],
                'And the skill'
            );
        }
    }

    @IsTest
    static void deletingAnAccountDeletesItsContactsRows() {
        System.runAs(volunteersAdmin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Id spanish = skill().Id;
            Account family = VolunteersTestData.household('The Rivera Family');
            Contact member = VolunteersTestData.contact('Rivera', family.Id);
            giveRows(new List<SObject>{ member, family }, spanish);

            Test.startTest();
            delete family;
            Test.stopTest();

            Assert.areEqual(0, rowsLeft(), 'The account and its contact took their rows');
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountTakesTheirRowsAndAMergeKeepsThem() {
        System.runAs(volunteersAdmin()) {
            Account leaving = VolunteersTestData.personAccount('Okafor');
            if (leaving == null) {
                return; // An org without person accounts has no such person.
            }
            Account kept = VolunteersTestData.personAccount('Lindqvist');
            Account duplicate = VolunteersTestData.personAccount('Lindqvist');
            Id spanish = skill().Id;
            giveRows(new List<SObject>{ leaving, duplicate }, spanish);

            Test.startTest();
            delete leaving;
            Database.merge(kept, duplicate.Id);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Account__c = :leaving.Id],
                'The deleted person account took their background check'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Account__c = :kept.Id],
                'The merge moved the duplicate background check to the person kept'
            );
            Assert.areEqual(2, rowsLeft(), 'Only the merged rows are left');
        }
    }
}
