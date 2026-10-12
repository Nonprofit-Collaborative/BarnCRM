/**
 * The other side of a relationship: created, kept in step, and taken away again, one record at
 * a time and two hundred at a time.
 *
 * NOT EXECUTED. No Salesforce org exists in the environment these were written in, so every
 * assertion here is unverified. They are written to the same standard as if they had run, and
 * the first person with a scratch org should run them before trusting the feature.
 */
@IsTest
private class RelationshipServiceTest {
    @IsTest
    static void createsTheOtherSideWhenARelationshipIsSaved() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');

        Test.startTest();
        insert RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');
        Test.stopTest();

        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(2, all.size(), 'One saved relationship should leave two records');
        Relationship__c first = all[0];
        Relationship__c second = all[1];
        Assert.areEqual(second.Id, first.Reciprocal_Relationship__c, 'The two sides pair up');
        Assert.areEqual(first.Id, second.Reciprocal_Relationship__c, 'And they pair both ways');
        Assert.areEqual(
            people[1].Id,
            second.Contact__c,
            'The other side is described from the other person'
        );
        Assert.areEqual(people[0].Id, second.Related_Contact__c, 'And points back at the first');
        Assert.areEqual('Spouse', second.Type__c, 'Spouse mirrors to Spouse');
    }

    @IsTest
    static void mirrorsParentToChild() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');

        Test.startTest();
        insert RelationshipTestDataFactory.between(people[0], people[1], 'Parent');
        Test.stopTest();

        Relationship__c other = otherSideOf(people[1].Id);
        Assert.areEqual('Child', other.Type__c, 'The parent of someone is that person\'s child');
        Assert.areEqual('Parent', other.Reciprocal_Type__c, 'And the reciprocal reads back');
    }

    @IsTest
    static void worksWhenBothPeopleAreHeldAsAccounts() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Account> people = RelationshipTestDataFactory.peopleAsAccounts(2, 'Okafor');

        Test.startTest();
        insert RelationshipTestDataFactory.between(people[0], people[1], 'Sibling');
        Test.stopTest();

        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(2, all.size(), 'A relationship between two accounts still gets both sides');
        Relationship__c other = all[0].Person_Account__c == people[1].Id ? all[0] : all[1];
        Assert.areEqual(people[1].Id, other.Person_Account__c, 'The account pair swaps whole');
        Assert.areEqual(people[0].Id, other.Related_Person_Account__c, 'Both halves of it');
        Assert.isNull(other.Contact__c, 'And nothing lands on the contact side');
    }

    @IsTest
    static void worksWhenOnePersonIsAContactAndTheOtherIsAnAccount() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> asContact = RelationshipTestDataFactory.contacts(1, 'Garcia');
        List<Account> asAccount = RelationshipTestDataFactory.peopleAsAccounts(1, 'Okafor');

        Test.startTest();
        insert RelationshipTestDataFactory.between(asContact[0], asAccount[0], 'Friend');
        Test.stopTest();

        Relationship__c other = otherSideOf(asAccount[0].Id);
        Assert.areEqual(
            asAccount[0].Id,
            other.Person_Account__c,
            'The account person owns the other side'
        );
        Assert.areEqual(
            asContact[0].Id,
            other.Related_Contact__c,
            'And the contact is the related one'
        );
        Assert.isNull(other.Contact__c, 'The two halves never both fill in');
    }

    @IsTest
    static void keepsTheOtherSideInStepWhenTheFirstIsEdited() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        Relationship__c saved = RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');
        insert saved;

        Test.startTest();
        update new Relationship__c(
            Id = saved.Id,
            End_Date__c = Date.today().addDays(-30),
            Description__c = 'Separated last month'
        );
        Test.stopTest();

        Relationship__c other = otherSideOf(people[1].Id);
        Assert.areEqual('Former', other.Status__c, 'An end date makes both sides former');
        Assert.areEqual(Date.today().addDays(-30), other.End_Date__c, 'With the same end date');
        Assert.areEqual('Separated last month', other.Description__c, 'And the same description');
    }

    @IsTest
    static void retypingOneSideRetypesTheOther() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        Relationship__c saved = RelationshipTestDataFactory.between(people[0], people[1], 'Parent');
        insert saved;

        Test.startTest();
        update new Relationship__c(Id = saved.Id, Type__c = 'Grandparent');
        Test.stopTest();

        Relationship__c other = otherSideOf(people[1].Id);
        Assert.areEqual('Grandchild', other.Type__c, 'Retyping one side retypes the other');
    }

    @IsTest
    static void deletingOneSideDeletesTheOther() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        Relationship__c saved = RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');
        insert saved;
        Assert.areEqual(2, RelationshipTestDataFactory.allRelationships().size(), 'Two to start');

        Test.startTest();
        delete saved;
        Test.stopTest();

        Assert.areEqual(
            0,
            RelationshipTestDataFactory.allRelationships().size(),
            'Deleting one side takes the other with it'
        );
    }

    @IsTest
    static void deletingBothSidesAtOnceDoesNotDeleteTwice() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        insert RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');

        Test.startTest();
        delete RelationshipTestDataFactory.allRelationships();
        Test.stopTest();

        Assert.areEqual(
            0,
            RelationshipTestDataFactory.allRelationships().size(),
            'Both sides deleted in one go is not an error'
        );
    }

    @IsTest
    static void writesNoOtherSideWhenTheOrgHasTurnedItOff() {
        RelationshipTestDataFactory.quietOtherAutomations();
        insert new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Relationship_Auto_Reciprocal__c = false
        );
        SettingsService.clearCache();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');

        Test.startTest();
        insert RelationshipTestDataFactory.between(people[0], people[1], 'Spouse');
        Test.stopTest();

        Assert.areEqual(
            1,
            RelationshipTestDataFactory.allRelationships().size(),
            'With the setting off, only the side that was entered exists'
        );
    }

    @IsTest
    static void writesNoOtherSideWhenTheRecordOptsOut() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        Relationship__c oneSided = RelationshipTestDataFactory.between(
            people[0],
            people[1],
            'Friend'
        );
        oneSided.Is_Reciprocal_Managed__c = false;

        Test.startTest();
        insert oneSided;
        Test.stopTest();

        Assert.areEqual(
            1,
            RelationshipTestDataFactory.allRelationships().size(),
            'Clearing Keep Both Sides In Step on one record leaves it one sided'
        );
    }

    @IsTest
    static void pairsWithARecordThatIsAlreadyTheOtherSide() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(2, 'Garcia');
        // Both sides arrive in one save, the way an import that carried both would deliver them.
        List<Relationship__c> bothSides = new List<Relationship__c>{
            RelationshipTestDataFactory.between(people[0], people[1], 'Parent'),
            RelationshipTestDataFactory.between(people[1], people[0], 'Child')
        };

        Test.startTest();
        insert bothSides;
        Test.stopTest();

        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(2, all.size(), 'Both sides were already there, so nothing was created');
        Assert.areEqual(all[1].Id, all[0].Reciprocal_Relationship__c, 'They pair with each other');
        Assert.areEqual(all[0].Id, all[1].Reciprocal_Relationship__c, 'Both ways');
    }

    @IsTest
    static void handlesTwoHundredRelationshipsInOneSave() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(400, 'Bulk');
        List<Relationship__c> batch = new List<Relationship__c>();
        for (Integer i = 0; i < 200; i++) {
            batch.add(RelationshipTestDataFactory.between(people[i], people[i + 200], 'Colleague'));
        }

        Test.startTest();
        insert batch;
        Test.stopTest();

        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(
            400,
            all.size(),
            'Two hundred saved relationships leave four hundred records'
        );
        Integer unpaired = 0;
        for (Relationship__c record : all) {
            if (record.Reciprocal_Relationship__c == null) {
                unpaired++;
            }
        }
        Assert.areEqual(
            0,
            unpaired,
            'Every record in a two hundred record save has its other side'
        );
    }

    @IsTest
    static void endsTwoHundredRelationshipsInOneSave() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(400, 'Bulk');
        List<Relationship__c> batch = new List<Relationship__c>();
        for (Integer i = 0; i < 200; i++) {
            batch.add(RelationshipTestDataFactory.between(people[i], people[i + 200], 'Colleague'));
        }
        insert batch;
        for (Relationship__c record : batch) {
            record.End_Date__c = Date.today();
        }

        Test.startTest();
        update batch;
        Test.stopTest();

        Integer former = 0;
        for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
            if (record.Status__c == 'Former') {
                former++;
            }
        }
        Assert.areEqual(400, former, 'Ending two hundred relationships ends four hundred records');
    }

    @IsTest
    static void deletesTwoHundredRelationshipsInOneSave() {
        RelationshipTestDataFactory.quietOtherAutomations();
        List<Contact> people = RelationshipTestDataFactory.contacts(400, 'Bulk');
        List<Relationship__c> batch = new List<Relationship__c>();
        for (Integer i = 0; i < 200; i++) {
            batch.add(RelationshipTestDataFactory.between(people[i], people[i + 200], 'Colleague'));
        }
        insert batch;

        Test.startTest();
        delete batch;
        Test.stopTest();

        Assert.areEqual(
            0,
            RelationshipTestDataFactory.allRelationships().size(),
            'Deleting two hundred takes all four hundred'
        );
    }

    @IsTest
    static void unmappedTypeFallsBackToOther() {
        RelationshipSelector.typeMappingOverride = new List<Relationship_Type__mdt>{
            new Relationship_Type__mdt(Type__c = 'Spouse', Reciprocal_Type__c = 'Spouse')
        };
        RelationshipService.clearTypeCache();

        Test.startTest();
        String reciprocal = RelationshipService.reciprocalOf('Grandparent');
        Test.stopTest();

        Assert.areEqual(
            'Other',
            reciprocal,
            'A type with no mapping still produces a usable other side'
        );
    }

    /**
     * The setting this whole feature hangs on, on an org that has never saved anything. It read
     * false there until ADR-0035, because a checkbox that ships on reads back false from
     * `getOrgDefaults()`, and this feature therefore wrote no other side on any fresh install
     * while reporting no error at all.
     */
    @IsTest
    static void theUpkeepIsOnForAnOrgThatHasNeverSavedItsSettings() {
        Test.startTest();
        Boolean upkeepIsOn = RelationshipService.isAutoReciprocalOn();
        Test.stopTest();

        Assert.isTrue(
            upkeepIsOn,
            'The upkeep ships on, so both sides are written before anyone saves a setting'
        );
    }

    private static Relationship__c otherSideOf(Id personId) {
        for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
            if (record.Contact__c == personId || record.Person_Account__c == personId) {
                return record;
            }
        }
        Assert.fail('No relationship described from that person');
        return null;
    }
}
