/**
 * Test setup for the rollup timing setting (ADR-NEXT async rollups).
 *
 * By default a save queues its real-time totals and the Rollup Queue recalculates them just
 * after the save, so a test reads them after `Test.stopTest`. The tests that check what the
 * engine calculates, often several saves in one test method with a read after each, switch the
 * org to recalculating in the save instead. The two paths run the same engine over the same
 * marked records; `RollupBackgroundTest` and the Giving `GiftSaveRollupCostTest` pin the queued
 * path and its cost.
 */
@IsTest
public class RollupTestSupport {
    /** Real-time totals are recalculated in the save, as before ADR-NEXT. */
    public static void recalculateInTheSave() {
        SettingsService.saveSystemValue(
            RollupService.PROCESSING_SETTING,
            RollupService.PROCESSING_IN_SAVE
        );
    }

    /** Real-time totals are queued and recalculated just after the save: the default. */
    public static void recalculateJustAfterTheSave() {
        SettingsService.saveSystemValue(
            RollupService.PROCESSING_SETTING,
            RollupService.PROCESSING_BACKGROUND
        );
    }
}
