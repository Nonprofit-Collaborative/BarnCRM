/**
 * The rules an affiliation has to pass, registered as "Check affiliations before they are
 * saved" in the automation registry at execution order 10, so it runs before the automation
 * that settles who is primary.
 *
 * It is a separate registry row from the maintenance one on purpose. An administrator who
 * switches the primary affiliation maintenance off before a bulk import still gets the person
 * and organization checks, the self affiliation check, the overlap check, and the status and
 * date rules, which are the checks that matter most at exactly that moment.
 *
 * Before insert and before update it settles the status against the dates, takes the primary
 * flag off anything that has ended, and refuses an affiliation that does not name one person
 * and one organization, that names the same party on both sides, or that covers dates another
 * one already covers.
 *
 * The defaults sit here rather than with the maintenance automation because the status and date
 * rule and the "a former affiliation is never the primary one" rule (R-AF4) are among the rules
 * that have to survive the maintenance being switched off, and because both write the record in
 * front of the person saving it rather than anything else.
 *
 * The service stands this automation down along with its own while it clears the primary flag
 * from a person's other affiliations, so the package's own writes are not validated a second
 * time.
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler, which is the contract every packaged handler is written to.
 */
public with sharing class AffiliationValidationHandler extends TriggerHandler {
    public override void beforeInsert() {
        applyAndValidate((List<Affiliation__c>) newRecords(), null);
    }

    public override void beforeUpdate() {
        applyAndValidate((List<Affiliation__c>) newRecords(), oldRecordsById());
    }

    private void applyAndValidate(List<Affiliation__c> records, Map<Id, SObject> previousById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        try {
            AffiliationDomain.applyDefaults(records, previousById);
            AffiliationDomain.validate(records, previousById);
        } catch (Exception thrown) {
            reportFailure(
                thrown,
                records,
                'AffiliationValidationHandler.applyAndValidate',
                Label.Core_Affiliation_PrimaryFailed
            );
        }
    }
}
