/**
 * Erasing a volunteer (canonical model R-VQ4, R-ER8): their onboarding requirements are deleted
 * and emptied from the Recycle Bin, the Erasure record lists them by Id only, the preview
 * lists them without deleting, and a person erasing without access to requirements is refused
 * rather than leaving a background check behind. Runs through Core's `PersonErasure`, which
 * finds the extension by name.
 */
@IsTest(testFor='ApexClass:VolunteersErasureExtension')
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
