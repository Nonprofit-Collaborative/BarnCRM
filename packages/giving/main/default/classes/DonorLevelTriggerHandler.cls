/**
 * Puts a donor on the right rung of the giving ladder in the same save that changes their giving
 * total (R-DL6, ADR-0028).
 *
 * One handler serves Account and Contact, registered once for each in `Automation_Registry__mdt`,
 * because the work is identical: both records carry the giving totals the Giving package rolls up
 * and both carry the three level fields.
 *
 * It runs in before insert and before update on purpose. The save that changes a donor's total is
 * usually the rollup engine's own update after a gift lands, and doing the placement before that
 * write means the level is right in the same transaction, with no second DML, no recursion guard,
 * and no elevated write. An after context would need all three.
 */
@NamespaceAccessible
public with sharing class DonorLevelTriggerHandler extends TriggerHandler {
    private static final String CONTEXT = 'Donor level assignment';

    @NamespaceAccessible
    public DonorLevelTriggerHandler() {
        return;
    }

    public override void beforeInsert() {
        place();
    }

    public override void beforeUpdate() {
        place();
    }

    private void place() {
        List<SObject> records = newRecords();
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            DonorLevelService.assignAll(records);
        } catch (Exception failure) {
            // A ladder that cannot be read must not stop somebody saving a household or a person.
            ErrorLogger.log(failure, CONTEXT);
        }
    }
}
