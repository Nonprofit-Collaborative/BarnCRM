/**
 * C-39 interaction notes (canonical model Section 29G, ADR-0089
 * 0089-interaction-notes-are-completed-tasks.md).
 *
 * An interaction note is a completed Task logged through the packaged action
 * Log_Interaction, and the package ships no code for it. These tests hold the platform to
 * what the admin guide promises: a note saved with the values the action fills in is closed,
 * a note on a person shows on their household in contact mode (R-IN3), a note on a household
 * names the person chosen, and nothing packaged stands in the way of many notes at once
 * (R-IN4). A test that fails here means the org's Task Status or Type values differ from the
 * ones the action fills in, which is the admin guide's third common mistake.
 */
@IsTest
private class InteractionNoteTest {
    // The predefined values of Contact.Log_Interaction and Account.Log_Interaction.
    private static final String STATUS_COMPLETED = 'Completed';
    private static final String TYPE_MEETING = 'Meeting';

    private static Task note(Id whoId, Id whatId, String subject) {
        return new Task(
            Subject = subject,
            ActivityDate = Date.today().addDays(-3),
            Status = STATUS_COMPLETED,
            Type = TYPE_MEETING,
            WhoId = whoId,
            WhatId = whatId,
            OwnerId = UserInfo.getUserId(),
            Description = 'Talked about the spring project.'
        );
    }

    private static Contact personWithHousehold() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Contact person = HouseholdTestDataFactory.newContact('Ana', 'Rivera');
        insert person;
        return [SELECT Id, AccountId FROM Contact WHERE Id = :person.Id];
    }

    @IsTest
    static void noteOnAPersonIsClosedAndShowsOnTheirHousehold() {
        System.runAs(TestUsers.admin()) {
            Contact person = personWithHousehold();
            Assert.isNotNull(person.AccountId, 'Contact mode gives the person a household (R-C1).');

            Test.startTest();
            insert note(person.Id, null, 'Coffee');
            Test.stopTest();

            Task saved = [
                SELECT IsClosed, AccountId, ActivityDate
                FROM Task
                WHERE WhoId = :person.Id
            ];
            Assert.isTrue(saved.IsClosed, 'A note is history, not a to-do (R-IN1).');
            Assert.areEqual(
                person.AccountId,
                saved.AccountId,
                'The note shows on the household (R-IN3).'
            );
            Assert.areEqual(
                Date.today().addDays(-3),
                saved.ActivityDate,
                'The note keeps the day it happened.'
            );
        }
    }

    @IsTest
    static void noteOnAHouseholdNamesTheChosenPerson() {
        System.runAs(TestUsers.admin()) {
            Contact person = personWithHousehold();

            Test.startTest();
            insert note(person.Id, person.AccountId, 'Visit');
            Test.stopTest();

            Task saved = [SELECT WhatId, AccountId, IsClosed FROM Task WHERE WhoId = :person.Id];
            Assert.areEqual(
                person.AccountId,
                saved.WhatId,
                'The note is on the household it was logged on.'
            );
            Assert.areEqual(person.AccountId, saved.AccountId, 'The household timeline shows it.');
            Assert.isTrue(saved.IsClosed, 'A note is history, not a to-do (R-IN1).');
        }
    }

    @IsTest
    static void twoHundredNotesSaveTogether() {
        System.runAs(TestUsers.admin()) {
            Contact person = personWithHousehold();
            List<Task> notes = new List<Task>();
            for (Integer i = 0; i < 200; i++) {
                notes.add(note(person.Id, null, 'Call ' + i));
            }

            Test.startTest();
            insert notes;
            Test.stopTest();

            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Task
                    WHERE WhoId = :person.Id AND IsClosed = TRUE AND AccountId = :person.AccountId
                ],
                'Every note is saved closed and on the household; nothing packaged runs on Task (R-IN4).'
            );
        }
    }
}
