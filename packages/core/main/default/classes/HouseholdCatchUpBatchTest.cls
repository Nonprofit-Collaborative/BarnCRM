/**
 * Household upkeep follows its feature switch end to end (ADR-NEXT): off on a new install, so a
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
        ];
    }

    @IsTest
    static void aNewInstallGivesANewContactNoHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            FeatureSwitchService.markNewInstall();
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
            FeatureSwitchService.markNewInstall();
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
            FeatureSwitchService.markNewInstall();
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
            FeatureSwitchService.markNewInstall();
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
            FeatureSwitchService.markNewInstall();
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
            FeatureSwitchService.markNewInstall();
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
