/**
 * What the Donor Levels page shows and what it refuses.
 *
 * The refusals matter as much as the model: a recalculation writes to every donor record in the
 * org, so it is not something a user without the settings permission may start, and it is not
 * something to start at all while levels are switched off.
 */
@IsTest
private class DonorLevelControllerTest {
    private static final String PERMISSION_SET = 'DonorLevelsTestAccess';

    @TestSetup
    static void makeData() {
        insert new List<Donor_Level__c>{
            new Donor_Level__c(Name = 'Friend', Minimum_Amount__c = 100, Maximum_Amount__c = 1000),
            new Donor_Level__c(
                Name = 'Sustainer',
                Minimum_Amount__c = 1000,
                Maximum_Amount__c = 5000
            ),
            new Donor_Level__c(
                Name = 'Retired Circle',
                Minimum_Amount__c = 50000,
                Active__c = false
            )
        };
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Donor_Levels_Enabled__c = true;
        settings.Donor_Level_Source_Field__c = 'Total_Giving__c';
        upsert settings;
        // The permission set is a setup object; it cannot share a transaction with the rows
        // above unless it is written as the same user in a separate context.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            SettingsTestPermissions.grantTo(PERMISSION_SET, UserInfo.getUserId());
        }
    }

    @IsTest
    static void theLadderComesBackLowestFirstWithItsDonorCounts() {
        insert new List<Account>{
            new Account(Name = 'The Nolan Family', Total_Giving__c = 2500),
            new Account(Name = 'The Garcia Family', Total_Giving__c = 1200)
        };
        insert new Contact(LastName = 'Reyes', Total_Giving__c = 300);

        Test.startTest();
        DonorLevelController.LadderModel model = DonorLevelController.getLadder();
        Test.stopTest();

        Assert.isTrue(model.enabled, 'Levels were turned on in setup.');
        Assert.areEqual(3, model.rungs.size(), 'Every rung is listed, retired ones included.');
        Assert.areEqual(
            'Friend',
            model.rungs[0].name,
            'The ladder reads lowest first, which is how the guide describes it.'
        );
        Assert.areEqual(
            1,
            model.rungs[0].donorCount,
            'One contact has given 300, which is a Friend, and accounts and contacts are counted ' +
            'together because both carry levels (R-DL3).'
        );
        Assert.areEqual(
            2,
            model.rungs[1].donorCount,
            'Two households have totals inside the Sustainer band.'
        );
        Assert.areEqual(
            0,
            model.rungs[2].donorCount,
            'A retired rung holds nobody here, and it is still shown so nobody wonders where it ' +
            'went.'
        );
        Assert.areEqual(
            'Total Giving',
            model.sourceFieldLabel,
            'Maria reads the label of the total, never its API name (plan Section 2.3).'
        );
        Assert.isTrue(
            model.canRecalculate,
            'This user was granted Manage BarnCRM Settings in setup.'
        );
    }

    @IsTest
    static void aRetiredRungIsStillListedSoNobodyWondersWhereItWent() {
        Test.startTest();
        DonorLevelController.LadderModel model = DonorLevelController.getLadder();
        Test.stopTest();

        Assert.areEqual(
            50000,
            model.rungs[2].minimumAmount,
            'The retired rung still reports the amount it starts at.'
        );
        Assert.isFalse(model.rungs[2].active, 'The page has to be able to show it as inactive.');
    }

    @IsTest
    static void recalculationStartsAJobAndCanBeSeenToHaveRun() {
        insert new Account(Name = 'The Okafor Family', Total_Giving__c = 4000);

        Test.startTest();
        Id jobId = DonorLevelController.recalculate();
        Test.stopTest();

        Assert.isNotNull(jobId, 'The page needs a job to have started to tell Maria it has.');
        Assert.areEqual(
            'Sustainer',
            [
                SELECT Donor_Level__r.Name
                FROM Account
                WHERE Name = 'The Okafor Family'
                LIMIT 1
            ]
            .Donor_Level__r.Name,
            'After the recalculation the donor is on the rung a total of 4000 earns.'
        );
    }

    @IsTest
    static void recalculationIsRefusedWhileLevelsAreOff() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.Donor_Levels_Enabled__c = false;
        update settings;
        SettingsService.clearCaches();

        String message;
        try {
            DonorLevelController.recalculate();
        } catch (AuraHandledException refused) {
            message = refused.getMessage();
        }

        Assert.areEqual(
            Label.Giving_DonorLevels_TurnOnFirst,
            message,
            'Placing donors while the feature is off would be work nobody asked for, and the ' +
            'message says what to do instead.'
        );
    }

    @IsTest
    static void aUserWithoutTheSettingsPermissionCannotRecalculate() {
        User standard = SettingsTestPermissions.buildStandardUser('Sam', 'Rivera', 'srivera');
        insert standard;

        String message;
        System.runAs(standard) {
            try {
                DonorLevelController.recalculate();
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
        }

        Assert.areEqual(
            Label.Giving_DonorLevels_NotPermitted,
            message,
            'A recalculation writes to every donor in the org, so it needs the settings ' +
            'permission and says so in words Maria can act on.'
        );
    }
}
