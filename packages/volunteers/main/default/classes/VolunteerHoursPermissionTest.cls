/**
 * What a person without Manage Volunteers cannot do to hours, with automation running and with
 * it paused (R-VG5), what nobody can do to approved hours (R-VG9), what an import may still do,
 * and what a merge does to the hours' household. Run as Standard User staff holding only the
 * sets named, so the permission is really absent.
 */
@IsTest(
    testFor='ApexClass:VolunteerHoursService, ApexClass:VolunteerHoursDeleteGuardHandler, ApexClass:VolunteerHoursWriter, ApexTrigger:VolunteerHoursTrigger'
)
private class VolunteerHoursPermissionTest {
    private static final String STAFFER = 'Staffer';
    private static final String COORDINATOR = 'ReadOnlyCoordinator';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.hoursStaffer(STAFFER);
            VolunteersTestData.readOnlyCoordinator(COORDINATOR);
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.job('Food pantry sort');
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Id jobId() {
        return [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id;
    }

    private static String updateError(Volunteer_Hours__c change) {
        try {
            update change;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return '';
    }

    private static void pauseAutomation() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            TestDataFactory.pausedSettings(1);
        }
    }

    /** A contact the staffer owns, so record access is theirs and only the permission is missing. */
    private static Contact ownedContact(String lastName, Id householdId) {
        Contact person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = VolunteersTestData.contact(lastName, householdId);
            update new Contact(Id = person.Id, OwnerId = user(STAFFER).Id);
        }
        return person;
    }

    @IsTest
    static void aStafferCannotMoveTheStatusRunningOrPaused() {
        Contact person = ownedContact('Rivera', null);
        Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, jobId(), 2);
        String running;
        String paused;
        String reason;

        Test.startTest();
        System.runAs(user(STAFFER)) {
            insert hours;
            running = updateError(new Volunteer_Hours__c(Id = hours.Id, Status__c = 'Approved'));
        }
        pauseAutomation();
        System.runAs(user(STAFFER)) {
            paused = updateError(new Volunteer_Hours__c(Id = hours.Id, Status__c = 'Approved'));
            reason = updateError(
                new Volunteer_Hours__c(Id = hours.Id, Rejection_Reason__c = 'Not me')
            );
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Volunteers_Hours_StatusThroughApproval,
            running,
            'With automation running the hours rules refuse it.'
        );
        Assert.isTrue(
            paused.contains('Manage Volunteers'),
            'Paused, the validation rule still refuses it: ' + paused
        );
        Assert.isTrue(
            reason.contains('Manage Volunteers'),
            'And a rejection reason typed by hand: ' + reason
        );
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                'Submitted',
                [SELECT Status__c FROM Volunteer_Hours__c WHERE Id = :hours.Id].Status__c,
                'Nothing moved.'
            );
        }
    }

    @IsTest
    static void aPausedImportLoadsApprovedHoursThatCannotBeDeleted() {
        Contact person = ownedContact('Okafor', null);
        String deleted = '';

        Test.startTest();
        pauseAutomation();
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c past = VolunteersTestData.newHours(person.Id, jobId(), 4);
            past.Status__c = 'Approved';
            past.Approved_Date__c = Datetime.newInstance(2025, 6, 1, 12, 0, 0);
            insert past;
            try {
                delete past;
            } catch (DmlException refused) {
                deleted = refused.getDmlMessage(0);
            }
            VolunteerHoursService.reopen(new Set<Id>{ past.Id });
            delete past;
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Volunteers_Hours_ApprovedNotDeletable,
            deleted,
            'Approved hours are kept even with automation paused (R-VG9); reopened, they go.'
        );
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(0, [SELECT COUNT() FROM Volunteer_Hours__c], 'Deleted once reopened.');
        }
    }

    @IsTest
    static void anEntryTheCoordinatorCannotEditIsReportedNotThrown() {
        Contact person = ownedContact('Nolan', null);
        Volunteer_Hours__c hours = VolunteersTestData.newHours(person.Id, jobId(), 2);
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            insert hours;
        }
        VolunteerHoursService.StatusChange result;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            result = VolunteerHoursService.approve(new Set<Id>{ hours.Id });
        }
        Test.stopTest();

        Assert.areEqual(0, result.moved, 'An entry the coordinator cannot edit is not moved.');
        Assert.isTrue(result.refused.containsKey(hours.Id), 'It is reported, not thrown.');
    }

    @IsTest
    static void aMergeKeepsTheHoursInTheHouseholdTheyWereGivenIn() {
        Account riveras;
        Account okafors;
        Contact survivor;
        Contact duplicate;
        Volunteer_Hours__c hours;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            riveras = VolunteersTestData.household('The Rivera Family');
            okafors = VolunteersTestData.household('The Okafor Family');
            survivor = VolunteersTestData.contact('Rivera', riveras.Id);
            duplicate = VolunteersTestData.contact('Rivera', okafors.Id);
            VolunteersTestData.contact('Okafor', okafors.Id);
            Id staffer = user(STAFFER).Id;
            update new List<SObject>{
                new Account(Id = riveras.Id, OwnerId = staffer),
                new Account(Id = okafors.Id, OwnerId = staffer)
            };
        }
        System.runAs(user(STAFFER)) {
            hours = VolunteersTestData.newHours(duplicate.Id, jobId(), 3);
            insert hours;
        }
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteerHoursService.approve(new Set<Id>{ hours.Id });
        }

        Test.startTest();
        System.runAs(user(STAFFER)) {
            merge survivor duplicate;
        }
        Test.stopTest();

        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c saved = [
                SELECT Contact__c, Household__c, Status__c
                FROM Volunteer_Hours__c
                WHERE Id = :hours.Id
            ];
            Assert.areEqual(survivor.Id, saved.Contact__c, 'The merge moves the hours.');
            Assert.areEqual('Approved', saved.Status__c, 'Still approved.');
            Assert.areEqual(
                okafors.Id,
                saved.Household__c,
                'A merge is not an edit of the entry: the hours stay with the household they ' +
                'were given in (R-VG2, ADR-0071).'
            );
        }
    }
}
