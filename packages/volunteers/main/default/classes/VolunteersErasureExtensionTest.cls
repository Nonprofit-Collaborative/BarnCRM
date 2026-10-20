/**
 * Erasing a volunteer (canonical model R-VQ4, R-VK5, R-VU5, R-VG10, R-ER8): their onboarding
 * requirements and skills are deleted and emptied from the Recycle Bin, the Erasure record lists
 * them by Id only, the preview lists them without deleting, and a person erasing without access
 * to requirements is refused rather than leaving a background check behind. Their hours and
 * sign-ups are kept with their notes emptied, Approved hours included, and the volunteer totals
 * on the person are kept. Runs through Core's `PersonErasure`, which finds the extension by name.
 */
@IsTest(testFor='ApexClass:VolunteersErasureExtension, ApexClass:VolunteerErasureSelector')
private class VolunteersErasureExtensionTest {
    private static User eraser() {
        return TestUsers.withPermissionSets(
            new List<String>{
                TestUsers.CORE_ADMIN,
                VolunteersTestData.ADMIN,
                'BarnCRM_Erase_People'
            }
        );
    }

    /** How many Deleted changes name the requirements, through the getters Core exposes. */
    private static Integer deletedLists(PersonErasure.Result result) {
        Integer found = 0;
        String label = Volunteer_Requirement__c.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getLabelPlural();
        for (PersonErasure.Change change : result.getChanges()) {
            if (change.getAction() == PersonErasure.DELETED && change.getObjectLabel() == label) {
                found++;
            }
        }
        return found;
    }

    private static Contact person(String lastName) {
        return VolunteersTestData.contact(lastName, null);
    }

    private static Volunteer_Requirement__c check(Id contactId, String note) {
        return new Volunteer_Requirement__c(
            Contact__c = contactId,
            Type__c = 'Background check',
            Status__c = 'Completed',
            Completed_Date__c = System.today().addDays(-5),
            Notes__c = note
        );
    }

    @IsTest
    static void deletesTheirRequirementsAndKeepsEveryoneElses() {
        System.runAs(eraser()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact jordan = person('Lee');
            Contact sam = person('Park');
            insert new List<Volunteer_Requirement__c>{
                check(jordan.Id, 'Ref A'),
                check(jordan.Id, 'Ref B'),
                check(sam.Id, 'Ref C')
            };
            Set<Id> theirs = new Map<Id, Volunteer_Requirement__c>(
                    [SELECT Id FROM Volunteer_Requirement__c WHERE Contact__c = :jordan.Id]
                )
                .keySet();

            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Ana Lee', null);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__c = :jordan.Id],
                'Their requirements are deleted'
            );
            // A test still reads purged rows with ALL ROWS, so it cannot see the Recycle Bin
            // empty: it proves the purge ran without failing.
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'PersonErasure.emptyRecycleBin'
                ],
                'Emptying the Recycle Bin did not fail'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__c = :sam.Id],
                'Another volunteer keeps theirs'
            );
            Assert.areEqual(1, deletedLists(result), 'The result lists the requirements once');
            Erasure__c audit = [
                SELECT Details__c
                FROM Erasure__c
                WHERE Contact__c = :jordan.Id
            ];
            for (Id requirementId : theirs) {
                Assert.isTrue(
                    audit.Details__c.contains(String.valueOf(requirementId)),
                    'The Erasure record lists each requirement by Id'
                );
            }
            Assert.isFalse(
                audit.Details__c.contains('Ref A'),
                'The Erasure record holds Ids, never what a requirement said'
            );
        }
    }

    @IsTest
    static void thePreviewListsThemAndDeletesNothing() {
        System.runAs(eraser()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact jordan = person('Lee');
            insert check(jordan.Id, 'Ref A');

            PersonErasure.Result preview = PersonErasure.preview(jordan.Id);

            Assert.areEqual(
                1,
                deletedLists(preview),
                'The preview says the requirement would be deleted'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__c = :jordan.Id],
                'The preview deleted nothing'
            );
        }
    }

    @IsTest
    static void aPersonWithNoRequirementsIsErasedAsBefore() {
        System.runAs(eraser()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact jordan = person('Lee');

            PersonErasure.erase(jordan.Id, 'Ana Lee', null);

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Erasure__c WHERE Contact__c = :jordan.Id],
                'Erased as before'
            );
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountHasTheirRequirementsDeleted() {
        System.runAs(eraser()) {
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            insert new Volunteer_Requirement__c(
                Account__c = person.Id,
                Type__c = 'Orientation',
                Status__c = 'In progress'
            );

            PersonErasure.erase(
                person.Id,
                [SELECT Name FROM Account WHERE Id = :person.Id].Name,
                null
            );

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Account__c = :person.Id],
                'The person account has none left'
            );
        }
    }

    /** The changes the result reports for one object and action. */
    private static List<PersonErasure.Change> changesFor(
        PersonErasure.Result result,
        Schema.SObjectType type,
        String action
    ) {
        List<PersonErasure.Change> found = new List<PersonErasure.Change>();
        String objectLabel = type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
        for (PersonErasure.Change change : result.getChanges()) {
            if (change.getAction() == action && change.getObjectLabel() == objectLabel) {
                found.add(change);
            }
        }
        return found;
    }

    @IsTest
    static void keepsTheirApprovedHoursAndTotalsAndEmptiesTheNotesOnEveryEntry() {
        System.runAs(eraser()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            // Approval off: each entry is Approved as it is saved, so all 251 are locked (R-VG7).
            VolunteersTestData.volunteerSettings(false, true);
            Contact jordan = person('Lee');
            Contact sam = person('Park');
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            for (Integer i = 0; i < 251; i++) {
                Volunteer_Hours__c entry = VolunteersTestData.newHours(jordan.Id, pantry.Id, 2);
                entry.Notes__c = 'Talked about her diagnosis ' + i;
                entries.add(entry);
            }
            Volunteer_Hours__c samsEntry = VolunteersTestData.newHours(sam.Id, pantry.Id, 3);
            samsEntry.Notes__c = 'Sam brought a friend';
            entries.add(samsEntry);
            insert entries;
            // The total the rollups would have written; read only to every user (29O).
            update new Contact(Id = jordan.Id, Volunteer_Hours_Total__c = 502);

            Test.startTest();
            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Ana Lee', null);
            Test.stopTest();

            Assert.areEqual(
                251,
                [
                    SELECT COUNT()
                    FROM Volunteer_Hours__c
                    WHERE Contact__c = :jordan.Id AND Status__c = 'Approved' AND Notes__c = NULL
                ],
                'Every entry is kept, still Approved and credited to the person, with no notes'
            );
            Assert.areEqual(
                502,
                [SELECT Volunteer_Hours_Total__c FROM Contact WHERE Id = :jordan.Id]
                .Volunteer_Hours_Total__c,
                'The total is kept, so it still matches the hours kept'
            );
            Assert.areEqual(
                'Sam brought a friend',
                [SELECT Notes__c FROM Volunteer_Hours__c WHERE Contact__c = :sam.Id].Notes__c,
                'Another volunteer keeps their notes'
            );
            Assert.areEqual(
                1,
                changesFor(result, Volunteer_Hours__c.SObjectType, PersonErasure.KEPT).size(),
                'The result says the hours were kept'
            );
            Assert.areEqual(
                1,
                changesFor(result, Volunteer_Hours__c.SObjectType, PersonErasure.CLEARED).size(),
                'The result says their notes were emptied'
            );
            Assert.isFalse(
                [SELECT Details__c FROM Erasure__c WHERE Contact__c = :jordan.Id]
                    .Details__c.contains('diagnosis'),
                'The Erasure record never holds what a note said'
            );
        }
    }

    @IsTest
    static void cancelsTheirUpcomingBookingsKeepsPastOnesAndEmptiesSignupNotes() {
        System.runAs(eraser()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact jordan = person('Lee');
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            Volunteer_Shift__c past = VolunteersTestData.newShift(
                pantry.Id,
                Datetime.now().addDays(-7),
                3
            );
            Volunteer_Shift__c coming = VolunteersTestData.newShift(
                pantry.Id,
                Datetime.now().addDays(7),
                3
            );
            insert new List<Volunteer_Shift__c>{ past, coming };
            Volunteer_Signup__c worked = VolunteersTestData.newSignup(past.Id, jordan.Id);
            worked.Status__c = 'No show';
            worked.Notes__c = 'Called in sick';
            Volunteer_Signup__c booked = VolunteersTestData.newSignup(coming.Id, jordan.Id);
            booked.Status__c = 'Confirmed';
            insert new List<Volunteer_Signup__c>{ worked, booked };

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Ana Lee', null);

            Map<Id, Volunteer_Signup__c> after = new Map<Id, Volunteer_Signup__c>(
                [SELECT Status__c, Notes__c FROM Volunteer_Signup__c WHERE Contact__c = :jordan.Id]
            );
            Assert.areEqual(2, after.size(), 'Both sign-ups are kept');
            Assert.areEqual('No show', after.get(worked.Id).Status__c, 'A past booking is history');
            Assert.isNull(after.get(worked.Id).Notes__c, 'Its notes are emptied');
            Assert.areEqual(
                'Cancelled',
                after.get(booked.Id).Status__c,
                'A booking on a shift still to come is cancelled'
            );
            Assert.areEqual(
                1,
                changesFor(result, Volunteer_Signup__c.SObjectType, PersonErasure.ENDED).size(),
                'The result says the booking was cancelled'
            );
        }
    }

    @IsTest
    static void deletesTheirSkillsAndInterests() {
        System.runAs(eraser()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact jordan = person('Lee');
            Contact sam = person('Park');
            Skill__c spanish = new Skill__c(Name = 'Spanish', Active__c = true);
            insert spanish;
            insert new List<Volunteer_Skill__c>{
                new Volunteer_Skill__c(Contact__c = jordan.Id, Skill__c = spanish.Id),
                new Volunteer_Skill__c(
                    Contact__c = jordan.Id,
                    Skill__c = spanish.Id,
                    Type__c = 'Interest'
                ),
                new Volunteer_Skill__c(Contact__c = sam.Id, Skill__c = spanish.Id)
            };

            PersonErasure.Result result = PersonErasure.erase(jordan.Id, 'Ana Lee', null);

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Contact__c = :jordan.Id],
                'Their skills and interests are deleted'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Skill__c WHERE Contact__c = :sam.Id],
                'Another volunteer keeps theirs'
            );
            Assert.areEqual(
                1,
                changesFor(result, Volunteer_Skill__c.SObjectType, PersonErasure.DELETED).size(),
                'The result lists them for the Recycle Bin to be emptied'
            );
        }
    }

    @IsTest
    static void aPersonHeldAsAnAccountKeepsTheirHoursWithoutNotes() {
        System.runAs(eraser()) {
            Account person = VolunteersTestData.personAccount('Okafor');
            if (person == null) {
                return; // An org without person accounts has no such person.
            }
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            Volunteer_Hours__c entry = VolunteersTestData.newHours(null, pantry.Id, 2);
            entry.Account__c = person.Id;
            entry.Notes__c = 'Prefers mornings';
            insert entry;

            PersonErasure.erase(
                person.Id,
                [SELECT Name FROM Account WHERE Id = :person.Id].Name,
                null
            );

            Volunteer_Hours__c after = [
                SELECT Account__c, Notes__c
                FROM Volunteer_Hours__c
                WHERE Id = :entry.Id
            ];
            Assert.areEqual(person.Id, after.Account__c, 'The entry stays with the person account');
            Assert.isNull(after.Notes__c, 'Its notes are emptied');
        }
    }

    @IsTest
    static void aPersonErasingWithoutAccessToRequirementsIsRefusedAndNothingChanges() {
        Contact jordan;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            jordan = person('Lee');
            insert check(jordan.Id, 'Ref A');
        }
        // A staff member allowed to erase: the access sync gives them Volunteers Staff, which
        // holds no right to requirements (a BarnCRM Admin would be given Volunteers Admin).
        User noVolunteers;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            noVolunteers = TestUsers.standardUserWith(
                'ErasesNoVolunteers',
                new List<String>{ VolunteersTestData.CORE_STAFF, 'BarnCRM_Erase_People' }
            );
        }

        System.runAs(noVolunteers) {
            try {
                PersonErasure.erase(jordan.Id, 'Ana Lee', null);
                Assert.fail('The erasure must be refused');
            } catch (PersonErasure.ErasureException refused) {
                Assert.isNotNull(refused.getMessage(), 'A reason is given');
            }
        }
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Volunteer_Requirement__c WHERE Contact__c = :jordan.Id],
                'The requirement is still there'
            );
            Assert.areEqual(
                'Lee',
                [SELECT LastName FROM Contact WHERE Id = :jordan.Id].LastName,
                'The person is not anonymized either'
            );
        }
    }
}
