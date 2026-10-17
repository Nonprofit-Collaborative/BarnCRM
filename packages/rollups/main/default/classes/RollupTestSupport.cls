/**
 * Test setup for the rollup timing setting (ADR-0098 async rollups).
 *
 * By default a save queues its real-time totals and the Rollup Queue recalculates them just
 * after the save, so a test reads them after `Test.stopTest`. The tests that check what the
 * engine calculates, often several saves in one test method with a read after each, switch the
 * org to recalculating in the save instead. The two paths run the same engine over the same
 * marked records; `RollupBackgroundTest` and the Giving `GiftSaveRollupCostTest` pin the queued
 * path and its cost.
 *
 * The setting lives on the module's own `Rollup_Settings__c` (ADR-0125 decision 6) and is
 * saved through the settings service, as the console saves it.
 */
@IsTest
@NamespaceAccessible
public class RollupTestSupport {
    /** Real-time totals are recalculated in the save, as before ADR-0098. */
    @NamespaceAccessible
    public static void recalculateInTheSave() {
        saveProcessing(RollupService.PROCESSING_IN_SAVE);
    }

    /** Real-time totals are queued and recalculated just after the save: the default. */
    @NamespaceAccessible
    public static void recalculateJustAfterTheSave() {
        saveProcessing(RollupService.PROCESSING_BACKGROUND);
    }

    private static void saveProcessing(String value) {
        SettingsService.saveValues(
            RollupService.SETTINGS_OBJECT,
            new Map<String, Object>{ RollupService.PROCESSING_SETTING => value }
        );
    }
}
