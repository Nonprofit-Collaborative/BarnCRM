/**
 * The other side of a relationship is kept in step for a user who may save their side but may
 * not edit the other side's package fields, nor the other person (PEOPLE-26, ADR-0021 category
 * 2 as extended by 0109-relationship-mirror-upkeep-in-system-mode.md).
 *
 * The user here holds BarnCRM Read Only, which reads people and relationships and edits
 * neither, plus a permission set built in the test that lets them create, edit and delete
 * relationships and fill in the fields a person types, but not the Reciprocal Relationship
 * pairing the package keeps. Their own saves run in user mode, as a save from the record page
 * does; the other side is the package's to write.
 *
 * Private sharing cannot be set from a test, so these prove the object and field access half
 * of the change. The sharing half is confirmed by an org run under a private sharing model.
 */
@IsTest
private class RelationshipUpkeepTest {
    private static final String ENTRY_PERMISSION_SET = 'Barn_Relationship_Entry_Test';
    private static final String READ_ONLY_PERMISSION_SET = 'BarnCRM_Read_Only';

    @IsTest
    static void theOtherSideIsCreatedForAUserWhoCannotWriteIt() {
        User narrow = narrowUser();
        List<Contact> people;
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        }

        System.runAs(narrow) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Assert.isFalse(
                Schema.SObjectType.Relationship__c.fields.Reciprocal_Relationship__c.isUpdateable(),
                'The test user really cannot write the pairing, or this test proves nothing'
            );
            Assert.isFalse(Schema.SObjectType.Contact.isUpdateable(), 'Nor edit the other person');

            Test.startTest();
            Database.insert(
                RelationshipTestDataFactory.between(people[0], people[1], 'Spouse'),
                AccessLevel.USER_MODE
            );
            Test.stopTest();
        }

        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(2, all.size(), 'The other side was created');
        Assert.areEqual(all[1].Id, all[0].Reciprocal_Relationship__c, 'The two sides pair up');
        Assert.areEqual(all[0].Id, all[1].Reciprocal_Relationship__c, 'And they pair both ways');
    }

    @IsTest
    static void anEditAndADeleteReachTheOtherSideForAUserWhoCannotWriteIt() {
        User narrow = narrowUser();
        List<Contact> people;
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        }

        System.runAs(narrow) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Relationship__c mine = RelationshipTestDataFactory.between(
                people[0],
                people[1],
                'Spouse'
            );
            Database.insert(mine, AccessLevel.USER_MODE);

            Test.startTest();
            Database.update(
                new Relationship__c(Id = mine.Id, Description__c = 'Married in 2004'),
                AccessLevel.USER_MODE
            );
            Relationship__c other = otherSideOf(people[1].Id);
            Assert.areEqual(
                'Married in 2004',
                other.Description__c,
                'The edit reached the other side'
            );

            Database.delete(new Relationship__c(Id = mine.Id), AccessLevel.USER_MODE);
            Test.stopTest();
        }

        Assert.areEqual(
            0,
            RelationshipTestDataFactory.allRelationships().size(),
            'Deleting one side took the other with it'
        );
    }

    @IsTest
    static void twoHundredRelationshipsSavedByAUserWhoCannotWriteTheOtherSide() {
        User narrow = narrowUser();
        List<Contact> people;
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            people = RelationshipTestDataFactory.contacts(400, 'Bulk');
        }

        System.runAs(narrow) {
            RelationshipTestDataFactory.quietOtherAutomations();
            List<Relationship__c> batch = new List<Relationship__c>();
            for (Integer i = 0; i < 200; i++) {
                batch.add(
                    RelationshipTestDataFactory.between(people[2 * i], people[2 * i + 1], 'Friend')
                );
            }

            Test.startTest();
            Database.insert(batch, AccessLevel.USER_MODE);
            Test.stopTest();
        }

        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(400, all.size(), 'Every one of the two hundred has another side');
        for (Relationship__c record : all) {
            Assert.isNotNull(record.Reciprocal_Relationship__c, 'And every record is paired');
        }
    }

    private static Relationship__c otherSideOf(Id personId) {
        for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
            if (record.Contact__c == personId) {
                return record;
            }
        }
        return null;
    }

    /**
     * BarnCRM Read Only plus create, edit and delete on relationships and edit on the fields a
     * person fills in. Reciprocal Relationship is left read only: it is the package's pairing.
     * Type and Status are left out because a universally required field takes no field access
     * row; Read Only already reads them.
     */
    private static User narrowUser() {
        User narrow = TestDataFactory.createUser(
            'Narrow',
            new List<String>{ READ_ONLY_PERMISSION_SET }
        );
        List<String> fields = new List<String>{
            'Contact__c',
            'Person_Account__c',
            'Related_Contact__c',
            'Related_Person_Account__c',
            'Reciprocal_Type__c',
            'Is_Reciprocal_Managed__c',
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
                SobjectType = 'Relationship__c',
                PermissionsRead = true,
                PermissionsCreate = true,
                PermissionsEdit = true,
                PermissionsDelete = true
            );
            List<FieldPermissions> edits = new List<FieldPermissions>();
            for (String field : fields) {
                edits.add(
                    new FieldPermissions(
                        ParentId = grant.Id,
                        SobjectType = 'Relationship__c',
                        Field = 'Relationship__c.' + field,
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
