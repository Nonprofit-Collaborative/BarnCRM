/**
 * The Sign-ups panel's controller (V-02, R-VU2 to R-VU4): places filled and remaining, adding a
 * sign-up, changing its status, attendance writing the hours through the sign-up automation,
 * and what a Read Only user gets. Run as users holding the packaged Volunteers permission sets
 * for each role, so the sets are what is tested.
 */
@IsTest(
    testFor='ApexClass:VolunteerShiftSignupsController, ApexClass:VolunteerSignupSelector, ApexClass:VolunteerSignupService'
)
private class VolunteerShiftSignupsControllerTest {
    private static final String COORDINATOR = 'SignupsCoordinator';
    private static final String STAFFER = 'SignupsStaffer';
    private static final String READER = 'SignupsReader';

    @TestSetup
    static void makeData() {
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
            new List<String>{ 'BarnCRM_Read_Only', 'Volunteers_Read_Only' }
        );
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.volunteerSettings(true, true);
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.shift(job.Id);
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Id shiftId() {
        return [SELECT Id FROM Volunteer_Shift__c LIMIT 1].Id;
    }

    /** People owned by the user, so record access is theirs. */
    private static List<Contact> peopleOwnedBy(String lastName, Integer howMany) {
        List<Contact> people;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            people = VolunteersTestData.contacts(howMany);
            Id ownerId = user(lastName).Id;
            for (Contact person : people) {
                person.OwnerId = ownerId;
            }
            update people;
        }
        return people;
    }

    @IsTest
    static void aStafferSignsPeopleUpAndSeesThePlacesFill() {
        List<Contact> people = peopleOwnedBy(STAFFER, 2);
        VolunteerShiftSignupsController.Panel empty;
        VolunteerShiftSignupsController.Panel twoIn;
        VolunteerShiftSignupsController.Panel oneCancelled;
        String second = '';

        Test.startTest();
        System.runAs(user(STAFFER)) {
            empty = VolunteerShiftSignupsController.getPanel(shiftId());
            VolunteerShiftSignupsController.addSignup(shiftId(), people[0].Id, null);
            twoIn = VolunteerShiftSignupsController.addSignup(shiftId(), people[1].Id, 'Confirmed');
            try {
                VolunteerShiftSignupsController.addSignup(shiftId(), people[0].Id, null);
            } catch (AuraHandledException refused) {
                second = refused.getMessage();
            }
            oneCancelled = VolunteerShiftSignupsController.setStatus(
                twoIn.signups[1].recordId,
                VolunteerSignupService.STATUS_CANCELLED
            );
        }
        Test.stopTest();

        Assert.areEqual(0, empty.slotsFilled, 'Nobody yet.');
        Assert.areEqual(4, empty.slotsRemaining, 'Four wanted, four to fill.');
        Assert.isTrue(empty.canAdd && empty.canEdit, 'Staff add and change sign-ups.');
        Assert.isFalse(empty.statusOptions.isEmpty(), 'The panel offers the statuses.');
        Assert.areEqual(
            HouseholdService.isPersonAccountOrg(),
            empty.personFilterField != null,
            'The picker is narrowed to person accounts only where people are accounts.'
        );
        Assert.areEqual(2, twoIn.signups.size(), 'Both listed.');
        Assert.areEqual('Signed up', twoIn.signups[0].status, 'The default status.');
        Assert.areEqual('Confirmed', twoIn.signups[1].status, 'Or the one chosen.');
        Assert.areEqual(2, twoIn.slotsFilled, 'Two places filled.');
        Assert.isTrue(second.contains('Shift'), 'A second sign-up is refused: ' + second);
        Assert.areEqual(1, oneCancelled.slotsFilled, 'A cancelled sign-up frees its place.');
        Assert.areEqual(3, oneCancelled.slotsRemaining, 'Three to fill again.');
    }

    @IsTest
    static void markingAttendedWritesTheHoursAndNoShowWritesNone() {
        List<Contact> people = peopleOwnedBy(COORDINATOR, 2);
        VolunteerShiftSignupsController.Panel attended;
        VolunteerShiftSignupsController.Panel noShow;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            VolunteerShiftSignupsController.addSignup(shiftId(), people[0].Id, null);
            VolunteerShiftSignupsController.Panel panel = VolunteerShiftSignupsController.addSignup(
                shiftId(),
                people[1].Id,
                null
            );
            attended = VolunteerShiftSignupsController.setStatus(
                panel.signups[0].recordId,
                VolunteerSignupService.STATUS_ATTENDED
            );
            noShow = VolunteerShiftSignupsController.setStatus(
                panel.signups[1].recordId,
                'No show'
            );
        }
        Test.stopTest();

        Assert.isTrue(attended.hoursWritten, 'Attendance wrote the hours.');
        Assert.isFalse(noShow.hoursWritten, 'A no show writes none.');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c written = [
                SELECT Hours__c, Status__c, Contact__c
                FROM Volunteer_Hours__c
                LIMIT 1
            ];
            Assert.areEqual(3, written.Hours__c, 'For the shift length.');
            Assert.areEqual('Submitted', written.Status__c, 'Waiting for approval.');
            Assert.areEqual(people[0].Id, written.Contact__c, 'For the person who came.');
        }
    }

    @IsTest
    static void aReadOnlyUserSeesTheSignupsAndChangesNothing() {
        List<Contact> people = peopleOwnedBy(STAFFER, 1);
        Id signupId;
        System.runAs(user(STAFFER)) {
            signupId = VolunteerShiftSignupsController.addSignup(shiftId(), people[0].Id, null)
                .signups[0]
                .recordId;
        }
        VolunteerShiftSignupsController.Panel panel;
        String refused = '';

        Test.startTest();
        System.runAs(user(READER)) {
            panel = VolunteerShiftSignupsController.getPanel(shiftId());
            try {
                VolunteerShiftSignupsController.setStatus(signupId, 'Confirmed');
            } catch (AuraHandledException failure) {
                refused = failure.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(1, panel.signups.size(), 'Read Only sees the sign-up.');
        Assert.isFalse(panel.canAdd || panel.canEdit, 'And may change nothing.');
        Assert.isTrue(String.isNotBlank(refused), 'A status change is refused.');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                'Signed up',
                [SELECT Status__c FROM Volunteer_Signup__c WHERE Id = :signupId].Status__c,
                'Nothing changed.'
            );
        }
    }

    @IsTest
    static void aPersonAccountIsSignedUpOnTheAccountSide() {
        Account person;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            person.OwnerId = user(COORDINATOR).Id;
            update person;
        }
        if (person == null) {
            return;
        }
        VolunteerShiftSignupsController.Panel panel;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            panel = VolunteerShiftSignupsController.addSignup(shiftId(), person.Id, null);
        }
        Test.stopTest();

        Assert.isTrue(panel.hasPersonAccounts, 'The panel knows people are accounts here.');
        Assert.areEqual(1, panel.signups.size(), 'The person is signed up.');
        Assert.areEqual('Okafor', panel.signups[0].personName, 'Named from the account.');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Signup__c saved = [SELECT Contact__c, Account__c FROM Volunteer_Signup__c];
            Assert.areEqual(person.Id, saved.Account__c, 'On the Account side.');
            Assert.isNull(saved.Contact__c, 'And no contact.');
        }
    }

    @IsTest
    static void aRequestWithoutAPersonOrWithAnUnknownStatusIsRefused() {
        String noPerson = '';
        String badStatus = '';

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            try {
                VolunteerShiftSignupsController.addSignup(shiftId(), null, null);
            } catch (AuraHandledException refused) {
                noPerson = refused.getMessage();
            }
            try {
                VolunteerShiftSignupsController.addSignup(shiftId(), UserInfo.getUserId(), 'Maybe');
            } catch (AuraHandledException refused) {
                badStatus = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(Label.Volunteers_Signups_PersonRequired, noPerson, 'A person is needed.');
        Assert.areEqual(
            Label.Volunteers_Signups_ActionFailed,
            badStatus,
            'A status the picklist does not offer is refused.'
        );
    }
}
