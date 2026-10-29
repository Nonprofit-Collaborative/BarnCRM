/**
 * C-20: merging two people stored as accounts, in junction mode, keeps what the merged-away
 * person had. Their memberships go to the survivor, every household keeps exactly one current
 * primary member and its Primary Contact mirrors it (R-M3, ADR-0044), a household the merge
 * leaves empty is kept, and the rollup engine, when the Rollup Builder module is there, is
 * asked to recalculate the survivors only (ADR-0125; a stub stands in for the module).
 *
 * The first tests set the person overrides, so they hold on every org shape; the last one
 * needs real person accounts and returns early on an org without them.
 */
@IsTest(testFor='ApexClass:AccountTriggerHandler')
private class PersonAccountMergeTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** Records which survivors Core asked the engine to recalculate. */
    private class RecordingEngine implements RollupEngineExtension {
        public Map<String, Set<Id>> survivorsByObject = new Map<String, Set<Id>>();
        public void afterMerge(String targetObject, List<SObject> mergedRecords) {
            return;
        }
        public void forSurvivors(String targetObject, Set<Id> survivorIds) {
            survivorsByObject.put(targetObject, survivorIds);
        }
        public void startQueuedRecalculation() {
            return;
        }
        public void processPending() {
            return;
        }
        public Datetime lastCalculated() {
            return null;
        }
        public Boolean isStale() {
            return false;
        }
        public Map<String, Set<String>> targetFieldsByObject() {
            return new Map<String, Set<String>>();
        }
    }

    @IsTest
    static void theSurvivorTakesTheMergedPersonsHouseholdAndItsPrimary() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aSurvivorAlreadyInTheHouseholdBecomesItsPrimary() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aMergeRecalculatesTheSurvivorsTotalsOnly() {
        System.runAs(TestUsers.admin()) {
            settingsThatTidyEmptyHouseholds();
            overridePeople();
            Account ana = new Account(Name = 'Ana Okafor');
            Account bea = new Account(Name = 'Bea Lindqvist');
            insert new List<Account>{ ana, bea };
            Map<Id, Id> contactBehind = contactsBehind(ana, bea);
            RecordingEngine engine = new RecordingEngine();
            RollupEngineExtensions.extensionOverride = engine;

            Test.startTest();
            Database.merge(ana, bea.Id);
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ contactBehind.get(ana.Id) },
                engine.survivorsByObject.get('Contact'),
                'Only the survivor person contact is recalculated, the record a gift names a person by'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex'],
                'A merge starts no batch job'
            );
        }
    }

    @IsTest
    static void realPersonAccountsKeepTheirHouseholdsAndPrimaryThroughAMerge() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                // Proven on every shape by the tests above; this one needs real person accounts,
                // of a record type the running user is given. The reason is checked and logged.
                return;
            }
            Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
            settingsThatTidyEmptyHouseholds();
            Account ana = (Account) realPerson(personType, 'Ana', 'Okafor');
            Account bea = (Account) realPerson(personType, 'Bea', 'Lindqvist');
            insert new List<Account>{ ana, bea };
            Account hers = household('The Okafor Household');
            Account theirs = household('The Lindqvist Household');
            insert new List<Household_Member__c>{
                membership(hers.Id, ana.Id, true),
                membership(theirs.Id, bea.Id, true)
            };
            Id anaContact = PersonRecordSelector.getPersonContactIds(new Set<Id>{ ana.Id })
                .get(ana.Id);

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
        Database.insert(record, AccessLevel.SYSTEM_MODE);
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
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(1, primaries.size(), 'The household has exactly one current primary');
        Assert.areEqual(survivorId, primaries[0].Account__c, 'And it is the survivor');
        Assert.areEqual(
            contactId,
            [SELECT Primary_Contact__c FROM Account WHERE Id = :householdId WITH SYSTEM_MODE]
            .Primary_Contact__c,
            'Its Primary Contact mirrors the survivor (R-M3)'
        );
    }
}
