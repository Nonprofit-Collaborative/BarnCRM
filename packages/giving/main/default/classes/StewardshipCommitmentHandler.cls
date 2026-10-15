/**
 * Starts the stewardship plans a commitment calls for, once the commitment is running (R-SP3a).
 *
 * "Started" is answered both ways deliberately. A pledge entered as Active has started, and so has
 * a pledge entered as Paused and turned on a week later: to the donor they are the same event, and
 * an organization that enters commitments in a draft state would otherwise get no follow-up at all.
 * A commitment that leaves Active and comes back starts a plan again only once the earlier plan has
 * been closed, because R-SP6 still holds and is checked in the service.
 *
 * After insert and after update rather than before, because a plan holds a lookup to the commitment
 * and a lookup needs an id.
 *
 * Registered in `Automation_Registry__mdt` as `Stewardship_Plan_Starter_Commitment` with Always Runs
 * false, separately from the gift starter, so an administrator loading a file of commitments can
 * switch this one off without also stopping the gifts her team enters from starting their plans
 * (R-SP1). Nothing is started retroactively when it is switched back on.
 */
@NamespaceAccessible
public with sharing class StewardshipCommitmentHandler extends TriggerHandler {
    private static final String CONTEXT = 'Stewardship plans';

    @NamespaceAccessible
    public StewardshipCommitmentHandler() {
        return;
    }

    public override void afterInsert() {
        start(enteredRunning());
    }

    public override void afterUpdate() {
        start(turnedOn());
    }

    /** A commitment entered as Active has started, whatever it is called afterwards. */
    private List<Commitment__c> enteredRunning() {
        List<Commitment__c> started = new List<Commitment__c>();
        List<SObject> records = newRecords();
        if (records == null) {
            return started;
        }
        for (Commitment__c commitment : (List<Commitment__c>) records) {
            if (StewardshipService.COMMITMENT_ACTIVE.equals(commitment.Status__c)) {
                started.add(commitment);
            }
        }
        return started;
    }

    /**
     * A commitment that moves into Active from any other status has started. An edit that leaves
     * the status alone is not a start, which is what keeps a plan from being laid out again every
     * time somebody corrects an amount.
     */
    private List<Commitment__c> turnedOn() {
        List<Commitment__c> started = new List<Commitment__c>();
        List<SObject> records = newRecords();
        Map<Id, SObject> before = oldRecordsById();
        if (records == null) {
            return started;
        }
        for (Commitment__c commitment : (List<Commitment__c>) records) {
            if (!StewardshipService.COMMITMENT_ACTIVE.equals(commitment.Status__c)) {
                continue;
            }
            Commitment__c previous = before == null
                ? null
                : (Commitment__c) before.get(commitment.Id);
            if (
                previous == null || !StewardshipService.COMMITMENT_ACTIVE.equals(previous.Status__c)
            ) {
                started.add(commitment);
            }
        }
        return started;
    }

    private void start(List<Commitment__c> commitments) {
        if (commitments.isEmpty()) {
            return;
        }
        try {
            StewardshipService.startForCommitments(commitments);
        } catch (Exception failure) {
            // A plan that could not start must not stop somebody recording a pledge (R-SP9).
            ErrorLogger.log(failure, CONTEXT);
        }
    }
}
