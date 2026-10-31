/**
 * Keeps each donor's Next Ask Date in step with their open asks (canonical model R-SO9), through
 * the dispatcher (registry row `Ask_Donor_Next_Ask_Date`, on by default, switchable).
 *
 * It runs after the save, so the asks are in the database when the earliest open Target Date is
 * read. A donor that cannot be updated is logged and never refuses the ask's save.
 */
@NamespaceAccessible
public with sharing class AskNextAskDateHandler extends TriggerHandler {
    private static final String CONTEXT = 'Ask: donor Next Ask Date';

    @NamespaceAccessible
    public AskNextAskDateHandler() {
        return;
    }

    public override void afterInsert() {
        sync(newRecords(), null);
    }

    public override void afterUpdate() {
        sync(newRecords(), oldRecords());
    }

    public override void afterDelete() {
        sync(null, oldRecords());
    }

    /** An ask restored from the Recycle Bin is open again, so its date counts again. */
    public override void afterUndelete() {
        sync(newRecords(), null);
    }

    private void sync(List<SObject> afterRows, List<SObject> beforeRows) {
        try {
            AskDonorDateSync.sync(afterRows, beforeRows);
        } catch (Exception failure) {
            // A donor date that could not be kept in step must not stop the ask being saved.
            ErrorLogger.log(failure, CONTEXT);
        }
    }
}
