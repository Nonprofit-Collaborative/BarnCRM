/**
 * Assignment as it actually happens: in the save that changes a donor's giving total, and in the
 * recalculation that catches what no save announces (R-DL6).
 *
 * The tests write the giving total directly onto the record rather than entering gifts, because
 * that is precisely what the rollup engine's own update does when a gift lands, and because the
 * thing under test here is the placement, not the arithmetic of the total (which G-02 owns and
 * `GiftRollupRefundTest` already asserts).
 */
@IsTest(testFor='ApexClass:DonorLevelBatch, ApexClass:DonorLevelService')
private class DonorLevelAssignmentTest {
    private static final String FRIEND = 'Friend';
    private static final String SUSTAINER = 'Sustainer';
    private static final String LEADERSHIP = 'Leadership Circle';

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new List<Donor_Level__c>{
                new Donor_Level__c(
                    Name = FRIEND,
                    Minimum_Amount__c = 100,
                    Maximum_Amount__c = 1000
                ),
                new Donor_Level__c(
                    Name = SUSTAINER,
                    Minimum_Amount__c = 1000,
                    Maximum_Amount__c = 5000
                ),
                new Donor_Level__c(Name = LEADERSHIP, Minimum_Amount__c = 5000)
            };
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            settings.Donor_Levels_Enabled__c = true;
            settings.Donor_Level_Source_Field__c = 'Total_Giving__c';
            upsert settings;
        }
    }

    private static Id levelId(String name) {
        return [SELECT Id FROM Donor_Level__c WHERE Name = :name LIMIT 1].Id;
    }

    @IsTest
    static void aHouseholdIsPlacedInTheSaveThatGivesItAGivingTotal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account household = new Account(Name = 'The Nolan Family', Total_Giving__c = 2500);

            Test.startTest();
            insert household;
            Test.stopTest();

            Account saved = [
                SELECT Donor_Level__c, Previous_Donor_Level__c, Donor_Level_Changed_Date__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(
                levelId(SUSTAINER),
                saved.Donor_Level__c,
                'A total of 2500 earns Sustainer, and the level is set in the same save.'
            );
            Assert.areEqual(
                null,
                saved.Previous_Donor_Level__c,
                'A donor placed for the first time has no rung to have come from.'
            );
            Assert.areEqual(
                Date.today(),
                saved.Donor_Level_Changed_Date__c,
                'The move is dated even when it is the donor first joining the ladder.'
            );
        }
    }

    @IsTest
    static void aPersonMovesUpAndDownWithTheirOwnTotalAndKeepsTheRungTheyLeft() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = new Contact(
                FirstName = 'Ana',
                LastName = 'Garcia',
                Total_Giving__c = 600
            );
            insert person;

            Test.startTest();
            person.Total_Giving__c = 7000;
            update person;
            Contact promoted = [
                SELECT Donor_Level__c, Previous_Donor_Level__c
                FROM Contact
                WHERE Id = :person.Id
            ];
            person.Total_Giving__c = 1500;
            update person;
            Test.stopTest();

            Assert.areEqual(
                levelId(LEADERSHIP),
                promoted.Donor_Level__c,
                'Ana reached Leadership Circle when her total rose to 7000.'
            );
            Assert.areEqual(
                levelId(FRIEND),
                promoted.Previous_Donor_Level__c,
                'She came from Friend, and that is what Previous Donor Level is for.'
            );

            Contact demoted = [
                SELECT Donor_Level__c, Previous_Donor_Level__c
                FROM Contact
                WHERE Id = :person.Id
            ];
            Assert.areEqual(
                levelId(SUSTAINER),
                demoted.Donor_Level__c,
                'A refund that takes her total to 1500 moves her down, because the level states what ' +
                'the current total earns (R-DL5).'
            );
            Assert.areEqual(
                levelId(LEADERSHIP),
                demoted.Previous_Donor_Level__c,
                'The rung she left is retained, so the movement is visible to the person who has to ' +
                'act on it.'
            );
        }
    }

    @IsTest
    static void aDonorWhoseTotalFallsBelowTheLadderIsLeftOnNoLevel() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account household = new Account(Name = 'The Okafor Family', Total_Giving__c = 1200);
            insert household;

            Test.startTest();
            household.Total_Giving__c = 40;
            update household;
            Test.stopTest();

            Account saved = [
                SELECT Donor_Level__c, Previous_Donor_Level__c
                FROM Account
                WHERE Id = :household.Id
            ];
            Assert.areEqual(
                null,
                saved.Donor_Level__c,
                'Below the lowest rung the answer is no level rather than the bottom one.'
            );
            Assert.areEqual(
                levelId(SUSTAINER),
                saved.Previous_Donor_Level__c,
                'Leaving the ladder is a move like any other and keeps the rung they left.'
            );
        }
    }

    @IsTest
    static void recalculationPlacesDonorsAfterTheLadderIsEdited() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Account> households = new List<Account>();
            for (Integer index = 0; index < 25; index++) {
                households.add(new Account(Name = 'Household ' + index, Total_Giving__c = 3000));
            }
            insert households;
            Assert.areEqual(
                levelId(SUSTAINER),
                [SELECT Donor_Level__c FROM Account WHERE Id = :households[0].Id].Donor_Level__c,
                'They start as Sustainers, which is what 3000 earns on the ladder as built.'
            );

            Donor_Level__c sustainerRung = [
                SELECT Id, Minimum_Amount__c
                FROM Donor_Level__c
                WHERE Name = :SUSTAINER
            ];
            sustainerRung.Minimum_Amount__c = 3500;
            update sustainerRung;
            Donor_Level__c friendRung = [
                SELECT Id, Maximum_Amount__c
                FROM Donor_Level__c
                WHERE Name = :FRIEND
            ];
            friendRung.Maximum_Amount__c = 3500;
            update friendRung;
            DonorLevelService.clearCache();

            Test.startTest();
            Database.executeBatch(new DonorLevelBatch(), 200);
            Test.stopTest();

            Id friendLevel = levelId(FRIEND);
            Assert.areEqual(
                25,
                [SELECT COUNT() FROM Account WHERE Donor_Level__c = :friendLevel],
                'Editing the ladder moves nobody by itself, and the recalculation moves everybody ' +
                'the edit affects (R-DL8).'
            );
        }
    }

    @IsTest
    static void recalculationStampsWhenItFinished() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new Contact(LastName = 'Reyes', Total_Giving__c = 2000);

            Test.startTest();
            Database.executeBatch(new DonorLevelBatch(DonorLevelBatch.CONTACTS), 200);
            Test.stopTest();

            Assert.isNotNull(
                Giving_Settings__c.getOrgDefaults().Donor_Levels_Last_Recalculated__c,
                'The page has to be able to say when donors were last placed (Principle 2).'
            );
        }
    }

    @IsTest
    static void nobodyIsPlacedWhileLevelsAreOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.Donor_Levels_Enabled__c = false;
            update settings;
            SettingsService.clearCaches();

            Test.startTest();
            Account household = new Account(Name = 'The Reyes Family', Total_Giving__c = 9000);
            insert household;
            Test.stopTest();

            Assert.areEqual(
                null,
                [SELECT Donor_Level__c FROM Account WHERE Id = :household.Id].Donor_Level__c,
                'Levels are off, so a donor with a large total is still on no level (R-DL7).'
            );
        }
    }

    @IsTest
    static void twoHundredDonorsAreAllPlacedInOneSave() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Contact> people = new List<Contact>();
            for (Integer index = 0; index < 200; index++) {
                people.add(new Contact(LastName = 'Donor ' + index, Total_Giving__c = 5500));
            }

            Test.startTest();
            insert people;
            Test.stopTest();

            Id topLevel = levelId(LEADERSHIP);
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE Donor_Level__c = :topLevel],
                'A bulk load places every record, not the first chunk (plan Principle 2).'
            );
        }
    }
}
