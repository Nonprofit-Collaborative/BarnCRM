/**
 * Household upkeep follows its feature switch end to end (ADR-0124): off on a new install, so a
 * new contact gets no household; on in an upgraded org; and turning it on catches up everyone
 * added while it was off, in both membership modes.
 */
@IsTest(testFor='ApexClass:HouseholdCatchUpBatch')
private class HouseholdCatchUpBatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id accountOf(Id contactId) {
        return [SELECT AccountId FROM Contact WHERE Id = :contactId].AccountId;
    }

    private static Integer currentMemberships(Set<Id> contactIds) {
        return [
            SELECT COUNT()
            FROM Household_Member__c
            WHERE Contact__c IN :contactIds AND End_Date__c = NULL
            WITH SYSTEM_MODE
        ];
    }

    /** Real people stored as accounts; only called once `PersonAccountTestShape` allows it. */
    private static List<Account> personAccounts(Integer howMany, String lastName) {
        Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
        List<Account> people = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            Account person = new Account(RecordTypeId = personType);
            person.put('FirstName', 'Person' + i); // person field, set by name
            person.put('LastName', lastName); // person field, set by name
            people.add(person);
        }
        insert people;
        return people;
    }

    private static List<Household_Member__c> currentAccountMemberships(Set<Id> accountIds) {
        return [
            SELECT Account__c, Household__c, Household__r.Name, Is_Primary__c
            FROM Household_Member__c
            WHERE Account__c IN :accountIds AND End_Date__c = NULL
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void thePersonAccountJobIsQueuedOnlyWhereTheOrgHasPersonAccounts() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);

            Test.startTest();
            Id contactJob = HouseholdCatchUpBatch.enqueue();
            Test.stopTest();

            Assert.isNotNull(contactJob, 'The contact job is always queued');
            Assert.areEqual(
                HouseholdService.isPersonAccountOrg() ? 2 : 1,
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'HouseholdCatchUpBatch'],
                'A Platform-only org queues the one job it always did (ADR-0013)'
            );
        }
    }

    @IsTest
    static void turningHouseholdUpkeepOnCatchesUpPersonAccountsInBulk() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                // Platform-only shape: no person accounts to catch up; the reason is logged.
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            TestSettings.newInstall();
            List<Account> people = personAccounts(251, 'Garcia');
            Set<Id> ids = new Map<Id, Account>(people).keySet();
            Assert.areEqual(
                0,
                currentAccountMemberships(ids).size(),
                'No membership while the feature is off'
            );
            HouseholdCatchUpBatch.chunkSize = 300;

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            List<Household_Member__c> rows = currentAccountMemberships(ids);
            Set<Id> households = new Set<Id>();
            for (Household_Member__c row : rows) {
                Assert.isTrue(row.Is_Primary__c, 'Each is the primary member, as on insert');
                Assert.areEqual('The Garcia Family', row.Household__r.Name, 'Named as on insert');
                households.add(row.Household__c);
            }
            Assert.areEqual(251, rows.size(), 'Every person account is caught up, once');
            Assert.areEqual(251, households.size(), 'Each in a household of their own');
        }
    }

    @IsTest
    static void contactModeGivesAPersonAccountNothingAsOnInsert() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            TestSettings.newInstall();
            List<Account> people = personAccounts(3, 'Adeyemi');
            Id householdType = HouseholdService.householdRecordTypeId();
            Integer before = [SELECT COUNT() FROM Account WHERE RecordTypeId = :householdType];

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Assert.areEqual(
                0,
                currentAccountMemberships(new Map<Id, Account>(people).keySet()).size(),
                'No membership in contact mode'
            );
            Assert.areEqual(
                before,
                [SELECT COUNT() FROM Account WHERE RecordTypeId = :householdType],
                'And no household, nor one for the contact behind each person account'
            );
        }
    }

    @IsTest
    static void contactsAndPersonAccountsAreCaughtUpTogetherOnce() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            TestSettings.newInstall();
            List<Contact> contacts = HouseholdTestDataFactory.manyContacts(120, 'Mixed');
            insert contacts;
            List<Account> people = personAccounts(131, 'Lee');
            // One person account already has a household: the catch-up leaves her in it.
            Account household = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert household;
            insert new Household_Member__c(
                Household__c = household.Id,
                Account__c = people[0].Id,
                Is_Primary__c = true
            );
            Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
            Set<Id> accountIds = new Map<Id, Account>(people).keySet();
            Map<Id, Id> personContacts = PersonRecordSelector.getPersonContactIds(accountIds);
            HouseholdCatchUpBatch.chunkSize = 300;

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Assert.areEqual(120, currentMemberships(contactIds), 'Every contact is caught up');
            Assert.areEqual(
                131,
                currentAccountMemberships(accountIds).size(),
                'Every person account has one membership, none a second'
            );
            Assert.areEqual(
                0,
                currentMemberships(new Set<Id>(personContacts.values())),
                'The contact behind a person account is the account to settle (R-M4)'
            );
        }
    }

    @IsTest
    static void aNewInstallGivesANewContactNoHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            TestSettings.newInstall();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');

            Test.startTest();
            insert maria;
            Test.stopTest();

            Assert.isNull(accountOf(maria.Id), 'Household upkeep is off until first-run setup');
        }
    }

    @IsTest
    static void anUpgradedOrgStillGivesANewContactAHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');

            Test.startTest();
            insert maria;
            Test.stopTest();

            Assert.isNotNull(accountOf(maria.Id), 'An empty features list means every one is on');
        }
    }

    @IsTest
    static void turningHouseholdUpkeepOnCatchesUpAndThenRunsTheTrigger() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            TestSettings.newInstall();
            Contact early = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert early;

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Id household = accountOf(early.Id);
            Assert.isNotNull(household, 'Maria, added before, is caught up');
            Account saved = [SELECT Name, Primary_Contact__c FROM Account WHERE Id = :household];
            Assert.areEqual('The Garcia Family', saved.Name, 'Named from the pattern');
            Assert.areEqual(early.Id, saved.Primary_Contact__c, 'And she is its Primary Contact');

            Contact later = HouseholdTestDataFactory.newContact('Mr.', 'David', 'Adeyemi');
            insert later;
            Assert.isNotNull(
                accountOf(later.Id),
                'A contact added after gets one from the trigger'
            );
        }
    }

    @IsTest
    static void theCatchUpIsBulkSafe() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            TestSettings.newInstall();
            List<Contact> people = HouseholdTestDataFactory.manyContacts(250, 'Bulk');
            insert people;
            HouseholdCatchUpBatch.chunkSize = 300;

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Set<Id> households = new Set<Id>();
            for (Contact person : [
                SELECT AccountId
                FROM Contact
                WHERE Id IN :new Map<Id, Contact>(people).keySet()
            ]) {
                Assert.isNotNull(person.AccountId, 'Every contact is caught up');
                households.add(person.AccountId);
            }
            Assert.areEqual(250, households.size(), 'Each in a household of their own');
        }
    }

    @IsTest
    static void junctionModeGetsMembershipRows() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            TestSettings.newInstall();
            List<Contact> people = HouseholdTestDataFactory.manyContacts(201, 'Junction');
            insert people;
            Set<Id> ids = new Map<Id, Contact>(people).keySet();
            Assert.areEqual(0, currentMemberships(ids), 'No membership while the feature is off');
            HouseholdCatchUpBatch.chunkSize = 300;

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Assert.areEqual(201, currentMemberships(ids), 'Each person joins a new household');
        }
    }

    @IsTest
    static void nothingIsCreatedWhenAutomaticHouseholdsAreOff() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Auto_Create_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            TestSettings.newInstall();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;

            Test.startTest();
            FeatureSwitchService.turnOn(FeatureSwitchService.HOUSEHOLD_UPKEEP);
            Test.stopTest();

            Assert.isNull(accountOf(maria.Id), 'The setting is honoured');
        }
    }

    @IsTest
    static void aContactThatCannotBeLinkedLeavesNoEmptyHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            TestSettings.newInstall();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            // Work is preferred but empty: once preferred email is on, her save is refused.
            maria.Preferred_Email__c = 'Work';
            insert maria;
            Id householdType = HouseholdService.householdRecordTypeId();
            Integer before = [SELECT COUNT() FROM Account WHERE RecordTypeId = :householdType];

            Test.startTest();
            FeatureSwitchService.turnOn(
                new Set<String>{
                    FeatureSwitchService.HOUSEHOLD_UPKEEP,
                    FeatureSwitchService.PREFERRED_EMAIL
                }
            );
            Test.stopTest();

            Assert.isNull(accountOf(maria.Id), 'Her save was refused');
            Assert.areEqual(
                before,
                [SELECT COUNT() FROM Account WHERE RecordTypeId = :householdType],
                'The household made for her is removed again'
            );
        }
    }
}
