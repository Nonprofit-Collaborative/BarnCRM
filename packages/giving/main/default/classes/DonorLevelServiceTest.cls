/**
 * The arithmetic of the ladder (R-DL2) and the two settings that govern it (R-DL1, R-DL7).
 *
 * The placement tests work on records in memory, because that is exactly how the trigger handler
 * uses the service: it mutates the record in front of the save rather than writing a second time.
 */
@IsTest
private class DonorLevelServiceTest {
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
        }
    }

    private static Map<String, Donor_Level__c> ladderByName() {
        Map<String, Donor_Level__c> byName = new Map<String, Donor_Level__c>();
        for (Donor_Level__c level : DonorLevelSelector.selectActiveLevels()) {
            byName.put(level.Name, level);
        }
        return byName;
    }

    private static void turnLevelsOn(String sourceField) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Donor_Levels_Enabled__c = true;
        settings.Donor_Level_Source_Field__c = sourceField;
        upsert settings;
        SettingsService.clearCaches();
        DonorLevelService.clearCache();
    }

    @IsTest
    static void aDonorLandsOnTheHighestRungTheirGivingReaches() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Donor_Level__c> rungs = ladderByName();
            List<Donor_Level__c> ladder = DonorLevelSelector.selectActiveLevels();

            Assert.areEqual(
                rungs.get(FRIEND).Id,
                DonorLevelService.levelFor(250, ladder),
                '250 is above the Friend minimum of 100 and below the Sustainer minimum of 1000.'
            );
            Assert.areEqual(
                rungs.get(SUSTAINER).Id,
                DonorLevelService.levelFor(4999.99, ladder),
                'A cent short of 5000 is still inside the Sustainer band.'
            );
            Assert.areEqual(
                rungs.get(LEADERSHIP).Id,
                DonorLevelService.levelFor(250000, ladder),
                'The top rung has no maximum, so every larger amount stays on it.'
            );
        }
    }

    @IsTest
    static void theMinimumIsInclusiveAndTheMaximumIsExclusive() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Map<String, Donor_Level__c> rungs = ladderByName();
            List<Donor_Level__c> ladder = DonorLevelSelector.selectActiveLevels();

            Assert.areEqual(
                rungs.get(SUSTAINER).Id,
                DonorLevelService.levelFor(1000, ladder),
                'A donor at exactly 1000 has reached Sustainer, which is what the guide promises.'
            );
            Assert.areEqual(
                rungs.get(LEADERSHIP).Id,
                DonorLevelService.levelFor(5000, ladder),
                'Exactly 5000 is the Leadership Circle minimum, so it belongs to the rung above.'
            );
        }
    }

    @IsTest
    static void aDonorBelowTheLadderOrWithNoTotalIsOnNoLevel() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Donor_Level__c> ladder = DonorLevelSelector.selectActiveLevels();

            Assert.areEqual(
                null,
                DonorLevelService.levelFor(99, ladder),
                'Below the lowest minimum is no level, which is a legitimate answer (R-DL2).'
            );
            Assert.areEqual(
                null,
                DonorLevelService.levelFor(null, ladder),
                'A donor with no giving total has no level rather than the bottom rung.'
            );
        }
    }

    @IsTest
    static void anInactiveRungHoldsNobodyNew() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Donor_Level__c sustainer = [SELECT Id FROM Donor_Level__c WHERE Name = :SUSTAINER];
            sustainer.Active__c = false;
            update sustainer;
            DonorLevelService.clearCache();

            List<Donor_Level__c> ladder = DonorLevelSelector.selectActiveLevels();
            Assert.areEqual(
                2,
                ladder.size(),
                'The ladder assignment reads is the active rungs only (R-DL8).'
            );
            Assert.areEqual(
                null,
                DonorLevelService.levelFor(2000, ladder),
                'With Sustainer retired, 2000 is held by no rung: Friend stops at 1000 and Leadership ' +
                'starts at 5000, and a band is never stretched to cover the gap (R-DL2).'
            );
            Assert.areEqual(
                [SELECT Id FROM Donor_Level__c WHERE Name = :FRIEND].Id,
                DonorLevelService.levelFor(750, ladder),
                'The active rungs either side still hold their own bands.'
            );
        }
    }

    @IsTest
    static void overlappingRungsResolveUpwardRatherThanAtRandom() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new Donor_Level__c(
                Name = 'Overlapping',
                Minimum_Amount__c = 500,
                Maximum_Amount__c = 2000
            );
            DonorLevelService.clearCache();

            List<Donor_Level__c> ladder = DonorLevelSelector.selectActiveLevels();
            Assert.areEqual(
                [SELECT Id FROM Donor_Level__c WHERE Name = 'Overlapping'].Id,
                DonorLevelService.levelFor(600, ladder),
                'Two rungs match 600, and the one with the greater minimum wins (R-DL2).'
            );
        }
    }

    @IsTest
    static void movingUpKeepsTheLevelLeftBehindAndDatesTheMove() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            turnLevelsOn(DonorLevelService.DEFAULT_SOURCE_FIELD);
            Map<String, Donor_Level__c> rungs = ladderByName();
            Account household = new Account(
                Name = 'The Nolan Family',
                Total_Giving__c = 6000,
                Donor_Level__c = rungs.get(SUSTAINER).Id
            );

            Boolean moved = DonorLevelService.assign(
                household,
                DonorLevelSelector.selectActiveLevels(),
                DonorLevelService.DEFAULT_SOURCE_FIELD
            );

            Assert.isTrue(moved, '6000 earns Leadership Circle, so this donor has moved.');
            Assert.areEqual(
                rungs.get(LEADERSHIP).Id,
                household.Donor_Level__c,
                'The level states what the current total earns.'
            );
            Assert.areEqual(
                rungs.get(SUSTAINER).Id,
                household.Previous_Donor_Level__c,
                'The rung they came from is retained, which is what makes the movement visible.'
            );
            Assert.areEqual(
                Date.today(),
                household.Donor_Level_Changed_Date__c,
                'The date says when the donor moved.'
            );
        }
    }

    @IsTest
    static void aRefundThatLowersTheTotalMovesTheDonorDownAndKeepsTheRungTheyLeft() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            turnLevelsOn(DonorLevelService.DEFAULT_SOURCE_FIELD);
            Map<String, Donor_Level__c> rungs = ladderByName();
            Contact person = new Contact(
                LastName = 'Nolan',
                Total_Giving__c = 1200,
                Donor_Level__c = rungs.get(LEADERSHIP).Id
            );

            Boolean moved = DonorLevelService.assign(
                person,
                DonorLevelSelector.selectActiveLevels(),
                DonorLevelService.DEFAULT_SOURCE_FIELD
            );

            Assert.isTrue(moved, 'A total of 1200 no longer earns Leadership Circle (R-DL5).');
            Assert.areEqual(
                rungs.get(SUSTAINER).Id,
                person.Donor_Level__c,
                'The level follows the total down rather than disagreeing with it.'
            );
            Assert.areEqual(
                rungs.get(LEADERSHIP).Id,
                person.Previous_Donor_Level__c,
                'What is retained is the record of where the donor came from, not a floor.'
            );
        }
    }

    @IsTest
    static void placingADonorTwiceChangesNothingTheSecondTime() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            turnLevelsOn(DonorLevelService.DEFAULT_SOURCE_FIELD);
            Account household = new Account(Name = 'The Garcia Family', Total_Giving__c = 2500);
            List<Donor_Level__c> ladder = DonorLevelSelector.selectActiveLevels();
            String source = DonorLevelService.DEFAULT_SOURCE_FIELD;

            DonorLevelService.assign(household, ladder, source);
            household.Donor_Level_Changed_Date__c = Date.today().addDays(-30);
            Boolean movedAgain = DonorLevelService.assign(household, ladder, source);

            Assert.isFalse(movedAgain, 'The second placement produces the level already held.');
            Assert.areEqual(
                Date.today().addDays(-30),
                household.Donor_Level_Changed_Date__c,
                'The changed date says when the donor last moved, not when the job last ran (R-DL4).'
            );
        }
    }

    @IsTest
    static void nothingIsAssignedOrClearedWhileLevelsAreOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.SetupOwnerId = UserInfo.getOrganizationId();
            settings.Donor_Levels_Enabled__c = false;
            upsert settings;
            SettingsService.clearCaches();
            Donor_Level__c held = [SELECT Id FROM Donor_Level__c WHERE Name = :FRIEND];
            Account household = new Account(
                Name = 'The Okafor Family',
                Total_Giving__c = 9000,
                Donor_Level__c = held.Id
            );

            List<SObject> moved = DonorLevelService.assignAll(new List<SObject>{ household });

            Assert.areEqual(0, moved.size(), 'Levels are off, so nobody is placed (R-DL7).');
            Assert.areEqual(
                held.Id,
                household.Donor_Level__c,
                'Switching levels off never clears the levels already assigned.'
            );
        }
    }

    @IsTest
    static void theSourceDefaultsToLifetimeGivingAndRefusesAFieldWeDoNotShip() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                'Total_Giving__c',
                DonorLevelService.sourceField(),
                'An organization that has chosen nothing gets the total that never resets.'
            );

            turnLevelsOn('Something_Invented__c');
            Assert.areEqual(
                'Total_Giving__c',
                DonorLevelService.sourceField(),
                'A stored value outside the four we ship is treated as unset rather than obeyed.'
            );

            turnLevelsOn('Giving_This_Year__c');
            Assert.areEqual(
                'Giving_This_Year__c',
                DonorLevelService.sourceField(),
                'An annual society is one setting away (ADR-0028).'
            );
        }
    }

    @IsTest
    static void theFiscalYearSourceMeasuresThisYearRatherThanTheLifetimeTotal() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            turnLevelsOn('Giving_This_Year__c');
            Map<String, Donor_Level__c> rungs = ladderByName();
            Account household = new Account(
                Name = 'The Reyes Family',
                Total_Giving__c = 20000,
                Giving_This_Year__c = 300
            );

            DonorLevelService.assignAll(new List<SObject>{ household });

            Assert.areEqual(
                rungs.get(FRIEND).Id,
                household.Donor_Level__c,
                'A long standing donor who has given 300 this year is a Friend on an annual ladder.'
            );
        }
    }
}
