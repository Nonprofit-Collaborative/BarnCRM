/**
 * Donor scoring on real records (G-19): the trigger path, the nightly pass, the Automation switch,
 * the organization's own cutoffs, and the shipped rollups that feed it.
 */
@IsTest(testFor='ApexClass:DonorScoreService, ApexClass:DonorScoreTriggerHandler, ApexClass:DonorLevelBatch')
private class DonorScoreServiceTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
            GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
        }
    }

    private static Contact scored(Id id) {
        return [
            SELECT
                RFM_Recency_Score__c,
                RFM_Frequency_Score__c,
                RFM_Monetary_Score__c,
                RFM_Score__c,
                RFM_Segment__c,
                Days_Since_Last_Gift__c
            FROM Contact
            WHERE Id = :id
        ];
    }

    @IsTest
    static void aSaveThatChangesTheRollupsScoresTheDonorInTheSameSave() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];

            Test.startTest();
            ana.Last_Gift_Date__c = Date.today().addDays(-30);
            ana.Recent_Gift_Count__c = 7;
            ana.Recent_Giving__c = 6000;
            update ana;
            Test.stopTest();

            Contact saved = scored(ana.Id);
            Assert.areEqual(5, saved.RFM_Recency_Score__c, '30 days ago is inside 90.');
            Assert.areEqual(5, saved.RFM_Frequency_Score__c, '7 gifts reaches 6.');
            Assert.areEqual(5, saved.RFM_Monetary_Score__c, '6000 reaches 5000.');
            Assert.areEqual(15, saved.RFM_Score__c, 'The three scores added.');
            Assert.areEqual('Champion', saved.RFM_Segment__c, 'Recent, often, generous.');
            Assert.areEqual(30, saved.Days_Since_Last_Gift__c, 'The formula counts the days.');
        }
    }

    @IsTest
    static void aDonorWithNoGiftHasNoScoresAndLosesOnesHeld() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            ana.Last_Gift_Date__c = Date.today();
            ana.Recent_Gift_Count__c = 1;
            ana.Recent_Giving__c = 10;
            update ana;
            Assert.areEqual('Promising', scored(ana.Id).RFM_Segment__c, 'Scored once there is a gift.');

            ana.Last_Gift_Date__c = null;
            update ana;

            Contact cleared = scored(ana.Id);
            Assert.isNull(cleared.RFM_Segment__c, 'No gift, no segment.');
            Assert.isNull(cleared.RFM_Score__c, 'No gift, no score.');
            Assert.isNull(cleared.RFM_Recency_Score__c, 'No gift, no recency score.');
        }
    }

    @IsTest
    static void theOrganizationsOwnCutoffsReplaceTheDefaults() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            settings.Donor_Score_Recency_Days__c = '10,20,30,40';
            settings.Donor_Score_Frequency_Gifts__c = '3,2,1,0.5';
            settings.Donor_Score_Monetary_Amount__c = 'not numbers';
            upsert settings;
            SettingsService.clearCaches();

            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            ana.Last_Gift_Date__c = Date.today().addDays(-35);
            ana.Recent_Gift_Count__c = 1;
            ana.Recent_Giving__c = 300;
            update ana;

            Contact saved = scored(ana.Id);
            Assert.areEqual(2, saved.RFM_Recency_Score__c, '35 days is inside 40 but not 30.');
            Assert.areEqual(3, saved.RFM_Frequency_Score__c, 'One gift reaches the third cutoff.');
            Assert.areEqual(3, saved.RFM_Monetary_Score__c, 'A bad setting uses the default: 300 reaches 250.');
        }
    }

    @IsTest
    static void theAutomationSwitchTurnsScoringOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AutomationControl.bypass('Donor_Score_Assignment_Contact');
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            ana.Last_Gift_Date__c = Date.today();
            ana.Recent_Gift_Count__c = 9;
            ana.Recent_Giving__c = 9000;
            update ana;
            AutomationControl.clearBypass('Donor_Score_Assignment_Contact');

            Assert.isNull(scored(ana.Id).RFM_Segment__c, 'Switched off, the save does not score.');
        }
    }

    @IsTest
    static void theNightlyPassScoresADonorWhoseDaysMovedWithNoSave() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            ana.Last_Gift_Date__c = Date.today().addDays(-100);
            ana.Recent_Gift_Count__c = 7;
            ana.Recent_Giving__c = 6000;
            update ana;
            Assert.areEqual(4, scored(ana.Id).RFM_Recency_Score__c, '100 days is inside 180.');

            DonorScoreService.todayOverride = Date.today().addDays(120);
            Test.startTest();
            Database.executeBatch(new DonorLevelBatch(DonorLevelBatch.CONTACTS));
            Test.stopTest();

            Contact later = scored(ana.Id);
            Assert.areEqual(3, later.RFM_Recency_Score__c, '220 days is inside 365 but not 180.');
            Assert.areEqual('Loyal', later.RFM_Segment__c, 'The segment follows the score.');
        }
    }

    @IsTest
    static void theShippedRollupsFeedTheScores() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = [SELECT Id FROM Contact LIMIT 1];
            List<Gift__c> gifts = GivingTestDataFactory.buildGifts(ana.Id, 3, 100);
            Gift__c old = GivingTestDataFactory.buildGift(ana.Id, 800);
            old.Gift_Date__c = Date.today().addDays(-800);
            gifts.add(old);
            insert gifts;

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(
                definitionsFor(
                    new Set<String>{
                        'Contact_Recent_Gift_Count',
                        'Contact_Recent_Giving',
                        'Contact_Last_Gift_Date'
                    }
                )
            );
            Test.stopTest();

            Contact recalculated = [
                SELECT Recent_Gift_Count__c, Recent_Giving__c, RFM_Segment__c, RFM_Score__c
                FROM Contact
                WHERE Id = :ana.Id
            ];
            Assert.areEqual(3, recalculated.Recent_Gift_Count__c, 'The 800 day old gift is outside 730 days.');
            Assert.areEqual(300, recalculated.Recent_Giving__c, 'Only the three recent gifts.');
            Assert.areEqual(
                'Loyal',
                recalculated.RFM_Segment__c,
                'Recency 5, frequency 3, monetary 3, scored in the rollup save.'
            );
            Assert.areEqual(11, recalculated.RFM_Score__c, 'The three scores added.');
        }
    }

    private static List<Rollup_Definition__c> definitionsFor(Set<String> keys) {
        List<Rollup_Definition__c> definitions = [
            SELECT
                Id,
                Name,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Active__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c IN :keys
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(keys.size(), definitions.size(), 'The shipped defaults are materialized.');
        return definitions;
    }
}
