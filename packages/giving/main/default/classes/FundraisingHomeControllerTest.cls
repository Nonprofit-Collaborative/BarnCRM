/**
 * Tests for Fundraising Home (people-giving-22): the figures, Enter a Gift, and the Fundraising
 * Setup tiles, for an administrator and for a reader.
 */
@IsTest(testFor='ApexClass:FundraisingHomeController')
private class FundraisingHomeControllerTest {
    private static final String PERMISSION_SET = 'FundraisingHomeTestAccess';

    /** Manage BarnCRM Settings for the admin, committed before the test methods run. */
    @TestSetup
    static void grantPermission() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            SettingsTestPermissions.grantTo(PERMISSION_SET, UserInfo.getUserId());
        }
    }

    private static Map<String, FundraisingHomeController.Tile> byName(
        FundraisingHomeController.HomeView view
    ) {
        Map<String, FundraisingHomeController.Tile> tiles = new Map<String, FundraisingHomeController.Tile>();
        for (FundraisingHomeController.Tile tile : view.tiles) {
            tiles.put(tile.name, tile);
        }
        return tiles;
    }

    private static Set<String> setupNames(FundraisingHomeController.HomeView view) {
        Set<String> names = new Set<String>();
        for (FundraisingHomeController.SetupTile tile : view.setupTiles) {
            names.add(tile.name);
            Assert.isTrue(String.isNotBlank(tile.label), 'Each setup tile carries its tab label.');
        }
        return names;
    }

    @IsTest
    static void anAdministratorSeesAllFiveFiguresEnterAGiftAndEverySetupTile() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new Gift_Batch__c(Description__c = 'Tuesday mail');

            Test.startTest();
            FundraisingHomeController.HomeView view = FundraisingHomeController.getHome();
            Test.stopTest();

            Map<String, FundraisingHomeController.Tile> tiles = byName(view);
            Assert.areEqual(
                new Set<String>{
                    'giftsToThank',
                    'installmentsOverdue',
                    'myAsksDue',
                    'openBatches',
                    'runningPlans'
                },
                tiles.keySet(),
                'An administrator can read every object behind the five figures.'
            );
            FundraisingHomeController.Tile batches = tiles.get('openBatches');
            Assert.areEqual(1, batches.count, 'The new batch is open, so it is counted.');
            Assert.isFalse(batches.capped, 'One batch is far below the cap.');
            Assert.areEqual(
                Schema.SObjectType.Gift_Batch__c.getLabelPlural(),
                batches.label,
                'The figure is named by the object label, not a custom label.'
            );
            Assert.areEqual('Open', batches.badgeLabel, 'The badge is the Open picklist label.');
            Assert.areEqual(
                'Open_Batches',
                batches.filterName,
                'It opens the Open Batches list view.'
            );
            Assert.areEqual(
                'Acknowledgments',
                tiles.get('giftsToThank').tabName,
                'Gifts to thank open the Acknowledgment Queue page.'
            );
            Assert.areEqual(
                'Overdue',
                tiles.get('installmentsOverdue').filterName,
                'Overdue pledge payments open the Overdue list view.'
            );
            Assert.areEqual(
                'My Asks Due This Month',
                tiles.get('myAsksDue').label,
                'The asks figure is named by the list view it opens.'
            );
            Assert.isTrue(view.canEnterGift, 'An administrator may create gifts.');
            Assert.areEqual(
                new Set<String>{
                    'Donor_Levels',
                    'Stewardship_Plans',
                    'Pledge_Reminders',
                    'Receipts'
                },
                setupNames(view),
                'An administrator with Manage BarnCRM Settings sees every setup tile.'
            );
        }
    }

    @IsTest
    static void aReaderCannotEnterAGiftAndSeesNoOrgWideSetup() {
        User reader = TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'BarnCRM_Read_Only', 'Giving_Read_Only' }
        );
        System.runAs(reader) {
            Test.startTest();
            FundraisingHomeController.HomeView view = FundraisingHomeController.getHome();
            Test.stopTest();

            Assert.isFalse(view.canEnterGift, 'A reader cannot create gifts.');
            Set<String> names = setupNames(view);
            Assert.isFalse(
                names.contains('Donor_Levels') || names.contains('Stewardship_Plans'),
                'The org-wide setup pages need Manage BarnCRM Settings.'
            );
            Assert.isTrue(
                names.contains('Pledge_Reminders') && names.contains('Receipts'),
                'A reader may open the pages that list what they can read.'
            );
            Assert.isFalse(view.tiles.isEmpty(), 'A reader still sees the figures they can read.');
        }
    }

    @IsTest
    static void aLargeCountIsCappedAndAnUnknownPicklistValueShowsAsItself() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            FundraisingHomeController.Tile tile = FundraisingHomeController.tile(
                'x',
                'X',
                FundraisingHomeController.COUNT_CAP + 1
            );
            Assert.areEqual(
                FundraisingHomeController.COUNT_CAP,
                tile.count,
                'The count stops at the cap.'
            );
            Assert.isTrue(tile.capped, 'The page shows the cap with a plus.');
            Assert.areEqual(
                'Nope',
                FundraisingHomeController.picklistLabel(
                    Schema.SObjectType.Gift_Batch__c.fields.Status__c,
                    'Nope'
                ),
                'A value the picklist does not have falls back to itself.'
            );
        }
    }
}
