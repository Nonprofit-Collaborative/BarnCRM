/**
 * The year end run: one consolidated statement per donor who gave in the statement year
 * (ADR-0016, canonical model 25C).
 *
 * **Scope 25.** Chosen so that peak heap stays far under the 12 MB asynchronous limit while still
 * amortising the per chunk query and the one sequence lock. ADR-0016 is explicit that this number
 * is a starting point to be measured, not a fact: 40,000 households at scope 25 is 1,600 chunks,
 * and if a chunk takes thirty seconds that is over thirteen hours. The v0.4 performance baseline
 * sets the real number.
 *
 * **Nothing holds a PDF.** Blobs are created, stored and dropped inside `execute`. The only state
 * carried between chunks is four integers, which is what keeps a long run inside the heap limit.
 *
 * **A chunk failure never aborts the run** (R-RR1). It is counted, written to the Error Log with
 * the donors it covered, and the next chunk runs. A partial run is resumed rather than restarted,
 * because the unique donor, year and type key makes reissuing to the same donor impossible
 * (R-RC9).
 */
public with sharing class ReceiptStatementBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Donors per chunk. See the class comment: a starting point to be measured, not a fact. */
    public static final Integer SCOPE = 25;

    private final Integer statementYear;
    private final Id runId;

    private Integer donorsProcessed = 0;
    private Integer receiptsIssued = 0;
    private Integer chunkErrors = 0;
    /** Who started the run from the Receipts page, told when it ends (Q-04). */
    private Id notifyUserId = JobNotifier.starter();

    public ReceiptStatementBatch(Integer statementYear, Id runId) {
        this.statementYear = statementYear;
        this.runId = runId;
    }

    /**
     * Every donor account with at least one qualifying gift in the year. Donor discovery runs in
     * the running user's sharing on purpose: a run issues statements to the donors the person who
     * started it can see. Storing the document does not, because a receipt that was half written
     * is worse than one an administrator cannot personally open (`ReceiptWriter`, ADR-0021).
     */
    public Database.QueryLocator start(Database.BatchableContext context) {
        return ReceiptSelector.donorLocator(statementYear);
    }

    public void execute(Database.BatchableContext context, List<Account> scope) {
        donorsProcessed += scope.size();
        try {
            receiptsIssued += issueFor(scope);
        } catch (Exception chunkFailure) {
            // One bad donor must not stop the rest of the org being receipted.
            chunkErrors++;
            ErrorLogger.log(chunkFailure, 'ReceiptStatementBatch', runId);
        }
        try {
            ReceiptRunService.recordProgress(runId, donorsProcessed, receiptsIssued, chunkErrors);
        } catch (Exception progressFailure) {
            ErrorLogger.log(progressFailure, 'ReceiptStatementBatch.progress', runId);
        }
    }

    /**
     * Accounts for every number the run consumed before it closes (R-RC3), then writes the
     * outcome. Reconciliation runs even when the run had no errors, because a number can be
     * consumed by a chunk that then rolled back, which is exactly the case nobody would think to
     * look for.
     */
    public void finish(Database.BatchableContext context) {
        try {
            ReceiptNumberSequence.reconcile(
                ReceiptNumberSequence.TYPE_STATEMENT,
                statementYear,
                runId
            );
        } catch (Exception reconcileFailure) {
            chunkErrors++;
            ErrorLogger.log(reconcileFailure, 'ReceiptStatementBatch.reconcile', runId);
        }
        try {
            ReceiptRunService.finish(runId, donorsProcessed, receiptsIssued, chunkErrors);
        } catch (Exception finishFailure) {
            ErrorLogger.log(finishFailure, 'ReceiptStatementBatch.finish', runId);
        }
        JobNotifier.aboutRecord(
            notifyUserId,
            Label.Giving_JobNotice_Statements,
            false,
            String.format(
                Label.Giving_JobNotice_StatementsBody,
                new List<Object>{
                    donorsProcessed.format(),
                    receiptsIssued.format(),
                    chunkErrors.format()
                }
            ),
            runId
        );
    }

    // ----------------------------------------------------------------------- internals

    /**
     * One chunk's worth of statements. The whole block of numbers is taken in a single locked
     * update, so a run holds the sequence lock once per chunk rather than once per donor (R-RS1).
     */
    private Integer issueFor(List<Account> donors) {
        Map<Id, Account> pending = new Map<Id, Account>();
        Map<String, Id> keyToDonor = new Map<String, Id>();
        for (Account donor : donors) {
            String key = ReceiptService.donorYearKey(
                donor.Id,
                statementYear,
                ReceiptNumberSequence.TYPE_STATEMENT
            );
            keyToDonor.put(key, donor.Id);
            pending.put(donor.Id, donor);
        }
        // Anyone who already holds a statement for this year is skipped, which is what makes a
        // failed run resumable rather than a source of duplicates (R-RR2).
        for (Receipt__c already : ReceiptSelector.issuedKeys(keyToDonor.keySet())) {
            pending.remove(keyToDonor.get(already.Donor_Year_Key__c));
        }
        if (pending.isEmpty()) {
            return 0;
        }

        Map<Id, List<Gift__c>> giftsByDonor = new Map<Id, List<Gift__c>>();
        for (Gift__c gift : ReceiptSelector.giftsForReceipting(pending.keySet(), statementYear)) {
            Id donorId = pending.containsKey(gift.Household__c)
                ? gift.Household__c
                : gift.Donor_Account__c;
            if (donorId == null || !pending.containsKey(donorId)) {
                continue;
            }
            if (!giftsByDonor.containsKey(donorId)) {
                giftsByDonor.put(donorId, new List<Gift__c>());
            }
            giftsByDonor.get(donorId).add(gift);
        }
        if (giftsByDonor.isEmpty()) {
            return 0;
        }

        List<Id> donorOrder = new List<Id>(giftsByDonor.keySet());
        donorOrder.sort();
        List<String> numbers = ReceiptNumberSequence.allocate(
            ReceiptNumberSequence.TYPE_STATEMENT,
            statementYear,
            donorOrder.size()
        );

        String templateBody = ReceiptTemplateService.activeBodyFor(
            ReceiptNumberSequence.TYPE_STATEMENT
        );
        ReceiptRenderer renderer = ReceiptRendererFactory.get();

        Integer issued = 0;
        for (Integer index = 0; index < donorOrder.size(); index++) {
            Id donorId = donorOrder[index];
            ReceiptService.issueStatement(
                pending.get(donorId),
                giftsByDonor.get(donorId),
                statementYear,
                numbers[index],
                runId,
                templateBody,
                renderer
            );
            issued++;
        }
        return issued;
    }
}
