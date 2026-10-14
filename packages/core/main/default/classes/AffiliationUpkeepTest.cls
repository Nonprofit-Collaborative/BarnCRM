/**
 * Primary affiliation upkeep completes for a user who may add an affiliation but may not edit
 * the person it belongs to (PEOPLE-26, ADR-0021 category 2).
 *
 * The user here holds BarnCRM Read Only, which reads people and affiliations and edits neither,
 * plus a permission set built in the test that lets them create and edit affiliations. Their
 * own affiliation save runs in user mode, as a save from the record page does; the corrections
 * the package makes afterwards (the person's Primary Affiliation, and the flag taken off the
 * person's other affiliation) are the package's own and must not depend on that user's access.
 *
 * Private sharing cannot be set from a test, so these prove the object and field access half
 * of the change. The sharing half is confirmed by an org run under a private sharing model.
 */
@IsTest(
    testFor='ApexClass:AffiliationUpkeepWriter, ApexClass:AffiliationMaintenanceHandler, ApexClass:AffiliationService'
)
private class AffiliationUpkeepTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String ENTRY_PERMISSION_SET = 'Barn_Affiliation_Entry_Test';
    private static final String READ_ONLY_PERMISSION_SET = 'BarnCRM_Read_Only';

    @IsTest
    static void upkeepCompletesForAUserWhoCannotEditThePerson() {
        User narrow = narrowUser();
        List<Contact> people;
        List<Account> orgs;
        Affiliation__c earlier;
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            people = RelationshipTestDataFactory.contacts(1, 'Garcia');
            orgs = RelationshipTestDataFactory.organizations(2, 'Union Foundation');
            earlier = RelationshipTestDataFactory.affiliation(people[0], orgs[0], 'Volunteer');
            earlier.Is_Primary__c = true;
            insert as system earlier;
        }

        System.runAs(narrow) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Assert.isFalse(
                canEditPersonDirectly(people[0].Id, orgs[1].Id),
                'The test user really cannot edit the person, or this test proves nothing'
            );

            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[1],
                'Program Officer'
            );
            work.Is_Primary__c = true;

            Test.startTest();
            Database.insert(work, AccessLevel.USER_MODE);
            Test.stopTest();
        }

        Contact reloaded = [
            SELECT Primary_Affiliation__c
            FROM Contact
            WHERE Id = :people[0].Id
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(
            orgs[1].Id,
            reloaded.Primary_Affiliation__c,
            'The person carries the new primary organization although the saver cannot edit them'
        );
        Affiliation__c before = [
            SELECT Is_Primary__c
            FROM Affiliation__c
            WHERE Id = :earlier.Id
            WITH SYSTEM_MODE
        ];
        Assert.isFalse(before.Is_Primary__c, 'The earlier primary lost its flag');
    }

    @IsTest
    static void upkeepCompletesForAPersonHeldAsAnAccount() {
        User narrow = narrowUser();
        List<Account> people;
        List<Account> orgs;
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            people = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');
            orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
        }

        System.runAs(narrow) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Affiliation__c work = RelationshipTestDataFactory.affiliation(
                people[0],
                orgs[0],
                'Trustee'
            );
            work.Is_Primary__c = true;

            Test.startTest();
            Database.insert(work, AccessLevel.USER_MODE);
            Test.stopTest();
        }

        Account reloaded = [
            SELECT Primary_Affiliation__c
            FROM Account
            WHERE Id = :people[0].Id
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(
            orgs[0].Id,
            reloaded.Primary_Affiliation__c,
            'A person held as an account carries it too'
        );
    }

    @IsTest
    static void upkeepCompletesForTwoHundredPeopleSavedByAUserWhoCannotEditThem() {
        User narrow = narrowUser();
        List<Contact> people;
        List<Account> orgs;
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            people = RelationshipTestDataFactory.contacts(200, 'Bulk');
            orgs = RelationshipTestDataFactory.organizations(1, 'Union Foundation');
        }

        System.runAs(narrow) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Affiliation__c> batch = new List<Affiliation__c>();
            for (Contact person : people) {
                Affiliation__c work = RelationshipTestDataFactory.affiliation(
                    person,
                    orgs[0],
                    'Member'
                );
                work.Is_Primary__c = true;
                batch.add(work);
            }

            Test.startTest();
            Database.insert(batch, AccessLevel.USER_MODE);
            Test.stopTest();
        }

        Integer carried = 0;
        for (Contact person : [
            SELECT Primary_Affiliation__c
            FROM Contact
            WHERE Id IN :people
            WITH SYSTEM_MODE
        ]) {
            if (person.Primary_Affiliation__c == orgs[0].Id) {
                carried++;
            }
        }
        Assert.areEqual(200, carried, 'Every person in a two hundred record save carries it');
    }

    /** Whether a user mode write of the person's own field goes through for the running user. */
    private static Boolean canEditPersonDirectly(Id personId, Id organizationId) {
        try {
            return Database.update(
                    new Contact(Id = personId, Primary_Affiliation__c = organizationId),
                    false,
                    AccessLevel.USER_MODE
                )
                .isSuccess();
        } catch (Exception refused) {
            return false;
        }
    }

    /**
     * BarnCRM Read Only (people and affiliations readable, neither editable) plus create and
     * edit on affiliations and on the fields a person fills in. Status is left out because a
     * universally required field takes no field access row; Read Only already reads it.
     */
    private static User narrowUser() {
        User narrow = TestDataFactory.createUser(
            'Narrow',
            new List<String>{ READ_ONLY_PERMISSION_SET }
        );
        List<String> fields = new List<String>{
            'Contact__c',
            'Person_Account__c',
            'Organization__c',
            'Role__c',
            'Is_Primary__c',
            'Start_Date__c',
            'End_Date__c',
            'Description__c'
        };
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet grant = new PermissionSet(
                Name = ENTRY_PERMISSION_SET,
                Label = ENTRY_PERMISSION_SET
            );
            insert as system grant;
            insert as system new ObjectPermissions(
                ParentId = grant.Id,
                SobjectType = 'Affiliation__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true
            );
            List<FieldPermissions> edits = new List<FieldPermissions>();
            for (String field : fields) {
                edits.add(
                    new FieldPermissions(
                        ParentId = grant.Id,
                        SobjectType = 'Affiliation__c',
                        Field = 'Affiliation__c.' + field,
                        PermissionsRead = true,
                        PermissionsEdit = true
                    )
                );
            }
            insert as system edits;
            insert as system new PermissionSetAssignment(
                AssigneeId = narrow.Id,
                PermissionSetId = grant.Id
            );
        }
        return narrow;
    }
}
