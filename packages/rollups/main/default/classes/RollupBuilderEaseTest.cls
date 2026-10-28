/**
 * What the Rollup Builder adds for ease of use (ADR-0136): the model says when instant totals
 * are calculated and when the nightly run is, so each mode is explained by its consequence
 * (U10).
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupBuilderController')
private class RollupBuilderEaseTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    @IsTest
    static void theModelSaysWhenEachModeRecalculates() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.BuilderModel model = RollupBuilderController.getModel();

            System.Assert.areEqual(
                RollupScheduler.nightlyTime(),
                model.nightlyTime,
                'Every night and Both say the hour'
            );
            System.Assert.areEqual(
                RollupService.recalculatesInTheSave(),
                model.inSave,
                'Instantly says whether it is after the save or during it'
            );
            System.Assert.isFalse(model.inSave, 'After the save is the default');
        }
    }
}
