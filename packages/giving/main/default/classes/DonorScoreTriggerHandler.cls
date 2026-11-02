/**
 * Scores a donor in the same save that changes their rollups (R-DT5, feature G-19).
 *
 * One handler serves Account and Contact, registered once for each in `Automation_Registry__mdt`.
 * It runs in before insert and before update, as `DonorLevelTriggerHandler` does and for the same
 * reasons: the save that changes a donor's totals is usually the rollup engine's own update, and a
 * before context writes the scores with that save, with no second DML and no elevated write.
 */
@NamespaceAccessible
public with sharing class DonorScoreTriggerHandler extends TriggerHandler {
    private static final String CONTEXT = 'Donor score assignment';

    @NamespaceAccessible
    public DonorScoreTriggerHandler() {
        return;
    }

    public override void beforeInsert() {
        score();
    }

    public override void beforeUpdate() {
        score();
    }

    private void score() {
        List<SObject> records = newRecords();
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            // The registry switch already decided this handler runs, so score without re-checking.
            DonorScoreService.Cutoffs cutoffs = DonorScoreService.cutoffs();
            for (SObject record : records) {
                DonorScoreService.score(record, cutoffs);
            }
        } catch (Exception failure) {
            // Scoring must not stop somebody saving a household or a person.
            ErrorLogger.log(failure, CONTEXT);
        }
    }
}
