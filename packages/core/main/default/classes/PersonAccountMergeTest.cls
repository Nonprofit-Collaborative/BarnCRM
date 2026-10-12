/**
 * C-20: merging two people stored as accounts, in junction mode, keeps what the merged-away
 * person had. Their memberships go to the survivor, every household keeps exactly one current
 * primary member and its Primary Contact mirrors it (R-M3, ADR-0044), a household the merge
 * leaves empty is kept, and the survivors' real-time totals are recalculated for the
 * survivors only.
 *
 * The first tests set the person overrides, so they hold on every org shape; the last one
 * needs real person accounts and returns early on an org without them.
 */
@IsTest
private class PersonAccountMergeTest {
    @IsTest
    static void theSurvivorTakesTheMergedPersonsHouseholdAndItsPrimary() {
        settingsThatTidyEmptyHouseholds();
        overridePeople();
        Account ana = new Account(Name = 'Ana Okafor');
        Account bea = new Account(Name = 'Bea Lindqvist');
        insert new List<Account>{ ana, bea };
        Map<Id, Id> contactBehind = contactsBehind(ana, bea);
        Account hers = household('The Okafor Household');
        Account theirs = household('The Lindqvist Household');
        insert new List<Household_Member__c>{
            membership(hers.Id, ana.Id, true),
            membership(theirs.Id, bea.Id, true)
        };

        Test.startTest();
        Database.merge(ana, bea.Id);
        Test.stopTest();

        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE Id IN :new List<Id>{ hers.Id, theirs.Id }],
            'The household the merge left empty is kept, although the org tidies empty ones'
        );
        assertOnePrimaryMirrored(hers.Id, ana.Id, contactBehind.get(ana.Id));
        assertOnePrimaryMirrored(theirs.Id, ana.Id, contactBehind.get(ana.Id));
    }

    @IsTest
    static void aSurvivorAlreadyInTheHouseholdBecomesItsPrimary() {
        settingsThatTidyEmptyHouseholds();
        overridePeople();
        Account ana = new Account(Name = 'Ana Okafor');
        Account bea = new Account(Name = 'Bea Lindqvist');
        insert new List<Account>{ ana, bea };
        Map<Id, Id> contactBehind = contactsBehind(ana, bea);
        Account theirs = household('The Lindqvist Household');
        insert new List<Household_Member__c>{
            membership(theirs.Id, bea.Id, true),
            membership(theirs.Id, ana.Id, false)
        };

        Test.startTest();
        Database.merge(ana, bea.Id);
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Household_Member__c WHERE Household__c = :theirs.Id],
            'The survivor is not given a second row in a household they are already in'
        );
        assertOnePrimaryMirrored(theirs.Id, ana.Id, contactBehind.get(ana.Id));
    }

    @IsTest
    static void aMergeRecalculatesTheSurvivorsTotalsOnly() {
        settingsThatTidyEmptyHouseholds();
        overridePeople();
        Account ana = new Account(Name = 'Ana Okafor');
        Account bea = new Account(Name = 'Bea Lindqvist');
        insert new List<Account>{ ana, bea };
        Map<Id, Id> contactBehind = contactsBehind(ana, bea);
        // A real-time total on the person contact, the record a gift names a person by.
        insert new Rollup_Definition__c(
            Name = 'Person total',
            Definition_Key__c = 'Core_Person_Merge_Live',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Contact',
            Relationship_Path__c = 'Contact__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
        RollupService.skipEngine = true;

        Test.startTest();
        Database.merge(ana, bea.Id);
        Test.stopTest();

        Assert.areEqual(
            new Set<Id>{ contactBehind.get(ana.Id) },
            RollupService.lastParentIds,
            'Only the survivor person contact is recalculated, not every record the total covers'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
            'A merge starts no batch job'
        );
    }

    @IsTest
    static void realPersonAccountsKeepTheirHouseholdsAndPrimaryThroughAMerge() {
        Set<Id> personTypes = OrgShapeSelector.personTypeRecordTypeIds();
        if (personTypes.isEmpty()) {
            // Proven on every shape by the tests above; this one needs real person accounts.
            return;
        }
        settingsThatTidyEmptyHouseholds();
        Id personType = new List<Id>(personTypes)[0];
        Account ana = (Account) realPerson(personType, 'Ana', 'Okafor');
        Account bea = (Account) realPerson(personType, 'Bea', 'Lindqvist');
        insert new List<Account>{ ana, bea };
        Account hers = household('The Okafor Household');
        Account theirs = household('The Lindqvist Household');
        insert new List<Household_Member__c>{
            membership(hers.Id, ana.Id, true),
            membership(theirs.Id, bea.Id, true)
        };
        Id anaContact = PersonRecordSelector.getPersonContactIds(new Set<Id>{ ana.Id }).get(ana.Id);

        Test.startTest();
        Database.merge(ana, bea.Id);
        Test.stopTest();

        Assert.isNotNull(anaContact, 'A real person account has a person contact');
        Assert.areEqual(
            2,
            [SELECT COUNT() FROM Account WHERE Id IN :new List<Id>{ hers.Id, theirs.Id }],
            'The household the merge left empty is kept'
        );
        assertOnePrimaryMirrored(hers.Id, ana.Id, anaContact);
        assertOnePrimaryMirrored(theirs.Id, ana.Id, anaContact);
    }

    // ------------------------------------------------------------------------------ helpers

    private static void settingsThatTidyEmptyHouseholds() {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_JUNCTION
        );
        settings.Auto_Create_Households__c = false;
        settings.Delete_Empty_Households__c = true;
        HouseholdTestDataFactory.save(settings);
    }

    private static void overridePeople() {
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
    }

    /** Stands in for the contact the platform keeps behind each person account. */
    private static Map<Id, Id> contactsBehind(Account ana, Account bea) {
        Contact behindAna = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Okafor');
        Contact behindBea = HouseholdTestDataFactory.newContact('Ms.', 'Bea', 'Lindqvist');
        insert new List<Contact>{ behindAna, behindBea };
        PersonRecordSelector.personContactIdOverride = new Map<Id, Id>{
            ana.Id => behindAna.Id,
            bea.Id => behindBea.Id
        };
        return PersonRecordSelector.personContactIdOverride;
    }

    private static SObject realPerson(Id personType, String firstName, String lastName) {
        SObject person = Account.SObjectType.newSObject();
        person.put('RecordTypeId', personType);
        person.put('FirstName', firstName);
        person.put('LastName', lastName);
        return person;
    }

    private static Account household(String name) {
        Account record = HouseholdTestDataFactory.newHousehold(name);
        insert record;
        return record;
    }

    private static Household_Member__c membership(Id householdId, Id personId, Boolean primary) {
        return new Household_Member__c(
            Household__c = householdId,
            Account__c = personId,
            Is_Primary__c = primary
        );
    }

    /** The household has exactly one current primary, the survivor, and mirrors them. */
    private static void assertOnePrimaryMirrored(Id householdId, Id survivorId, Id contactId) {
        Date today = Date.today();
        List<Household_Member__c> primaries = [
            SELECT Account__c
            FROM Household_Member__c
            WHERE
                Household__c = :householdId
                AND Is_Primary__c = TRUE
                AND (End_Date__c = NULL
                OR End_Date__c > :today)
        ];
        Assert.areEqual(1, primaries.size(), 'The household has exactly one current primary');
        Assert.areEqual(survivorId, primaries[0].Account__c, 'And it is the survivor');
        Assert.areEqual(
            contactId,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :householdId].Primary_Contact__c,
            'Its Primary Contact mirrors the survivor (R-M3)'
        );
    }
}
