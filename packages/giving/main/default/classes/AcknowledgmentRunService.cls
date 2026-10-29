/**
 * Starting an acknowledgment run and keeping its record honest while it goes (canonical model
 * 25H).
 *
 * Two runs exist and they are different shapes. An email run is a batch: it is queued, it works
 * through the queue in chunks, and it finishes on its own. A letter run is one transaction that
 * produces a file and then waits for a person, because the package cannot know whether anything
 * was printed (R-AK11).
 */
public with sharing class AcknowledgmentRunService {
    public static final String STATUS_QUEUED = 'Queued';
    public static final String STATUS_RUNNING = 'Running';
    public static final String STATUS_READY_TO_MERGE = 'Ready to merge';
    public static final String STATUS_COMPLETED = 'Completed';
    public static final String STATUS_COMPLETED_WITH_ERRORS = 'Completed with errors';
    public static final String STATUS_FAILED = 'Failed';

    /** How many letters one merge file carries. Beyond this, run it again for the rest. */
    public static final Integer LETTER_LIMIT = 2000;

    private static final String CONTEXT_EMAIL = 'AcknowledgmentRunService.startEmailRun';
    private static final String CONTEXT_LETTER = 'AcknowledgmentRunService.runLetterMerge';

    public class AcknowledgmentRunException extends Exception {
    }

    /**
     * Starts the email send and returns its run record.
     *
     * The run record is written before the batch is queued, so a run that never got as far as
     * being queued still leaves something behind saying it was asked for.
     */
    public static Acknowledgment_Run__c startEmailRun() {
        AcknowledgmentService.requireSendPermission();
        Acknowledgment_Run__c run = newRun(AcknowledgmentRuleService.CHANNEL_EMAIL);
        AcknowledgmentWriter.insertRun(run);
        try {
            run.Async_Job_Id__c = Database.executeBatch(
                new AcknowledgmentBatch(run.Id),
                AcknowledgmentBatch.SCOPE
            );
            run.Status__c = STATUS_RUNNING;
            run.Started__c = System.now();
        } catch (Exception queueFailure) {
            run.Status__c = STATUS_FAILED;
            run.Finished__c = System.now();
            ErrorLogger.log(queueFailure, CONTEXT_EMAIL, run.Id);
        }
        AcknowledgmentWriter.updateRun(run);
        return run;
    }

    /**
     * Gathers the gifts whose rule says Letter, claims them, and writes the merge file.
     *
     * It is synchronous and capped, because the administrator is waiting for a download. The rows
     * are left Queued: they become Sent when a person says the letters went (R-AK11).
     */
    public static Acknowledgment_Run__c runLetterMerge() {
        AcknowledgmentService.requireSendPermission();
        Acknowledgment_Run__c run = newRun(AcknowledgmentRuleService.CHANNEL_LETTER);
        run.Started__c = System.now();
        run.Status__c = STATUS_RUNNING;
        AcknowledgmentWriter.insertRun(run);

        try {
            List<Gift__c> queued = AcknowledgmentSelector.queuedGifts(LETTER_LIMIT);
            List<Acknowledgment_Rule__c> rules = AcknowledgmentSelector.activeRules();
            Set<String> earlierDonors = AcknowledgmentRuleService.donorsWithEarlierGifts(
                queued,
                new Set<Id>()
            );

            // An email gift whose donor opted out of email is thanked by letter (R-AK13).
            Set<Id> optedOut = AcknowledgmentService.optedOutOfEmail(queued);

            List<Gift__c> letters = new List<Gift__c>();
            List<AcknowledgmentRuleService.RuleMatch> matches = new List<AcknowledgmentRuleService.RuleMatch>();
            for (Gift__c gift : queued) {
                AcknowledgmentRuleService.RuleMatch match = AcknowledgmentRuleService.matchFor(
                    gift,
                    rules,
                    earlierDonors
                );
                if (match == null) {
                    continue;
                }
                if (
                    AcknowledgmentRuleService.CHANNEL_LETTER.equals(match.channel) ||
                    (AcknowledgmentRuleService.CHANNEL_EMAIL.equals(match.channel) &&
                    optedOut.contains(gift.Id))
                ) {
                    letters.add(gift);
                    matches.add(match);
                }
            }
            run.Gifts_Processed__c = queued.size();

            if (letters.isEmpty()) {
                run.Status__c = STATUS_COMPLETED;
                run.Finished__c = System.now();
                AcknowledgmentWriter.updateRun(run);
                return run;
            }

            List<Acknowledgment__c> rows = new List<Acknowledgment__c>();
            for (Integer index = 0; index < letters.size(); index++) {
                rows.add(
                    new Acknowledgment__c(
                        Gift__c = letters[index].Id,
                        Rule__c = matches[index].ruleId,
                        Channel__c = AcknowledgmentRuleService.CHANNEL_LETTER,
                        Status__c = AcknowledgmentService.STATUS_QUEUED,
                        Recipient_Contact__c = letters[index].Donor_Contact__c,
                        Run__c = run.Id,
                        Gift_Key__c = String.valueOf(letters[index].Id)
                    )
                );
            }
            List<Database.SaveResult> claimed = AcknowledgmentWriter.claim(rows);

            // Only the gifts this run actually claimed go in the file. A gift somebody else
            // claimed while this ran is theirs, and printing it here would be the second letter
            // R-AK7 exists to prevent.
            List<Gift__c> inFile = new List<Gift__c>();
            List<AcknowledgmentRuleService.RuleMatch> inFileMatches = new List<AcknowledgmentRuleService.RuleMatch>();
            for (Integer index = 0; index < claimed.size(); index++) {
                if (claimed[index].isSuccess()) {
                    inFile.add(letters[index]);
                    inFileMatches.add(matches[index]);
                }
            }
            run.Acknowledgments_Sent__c = inFile.size();
            // A gift another run claimed while this one was working is not an error: it is
            // somebody else's letter, and leaving it out of this file is the correct outcome.
            run.Errors__c = 0;

            if (!inFile.isEmpty()) {
                run.Merge_File_Document_Id__c = AcknowledgmentWriter.storeMergeFile(
                    String.format(
                        Label.Giving_Acknowledgments_MergeFileTitle,
                        new List<String>{ String.valueOf(Date.today()) }
                    ),
                    AcknowledgmentLetterMerge.csvFor(inFile, inFileMatches),
                    run.Id
                );
            }
            run.Status__c = STATUS_READY_TO_MERGE;
            AcknowledgmentWriter.updateRun(run);
            AcknowledgmentService.recordLastRun(
                String.format(
                    Label.Giving_Acknowledgment_LetterRunSummary,
                    new List<String>{ String.valueOf(inFile.size()) }
                )
            );
            return run;
        } catch (Exception failure) {
            run.Status__c = STATUS_FAILED;
            run.Finished__c = System.now();
            AcknowledgmentWriter.updateRun(run);
            ErrorLogger.log(failure, CONTEXT_LETTER, run.Id);
            throw new AcknowledgmentRunException(Label.Giving_Acknowledgment_LetterRunFailed);
        }
    }

    /**
     * Marks a letter run's letters as sent: the rows, and the gifts they thank for (R-AK11).
     *
     * The keys are kept. A letter that was printed and posted is a thank you that happened, and
     * the gift is not coming back into the queue unless a person puts it there.
     */
    public static Acknowledgment_Run__c markLetterRunSent(Id runId) {
        AcknowledgmentService.requireSendPermission();
        Acknowledgment_Run__c run = AcknowledgmentSelector.runById(runId);
        if (run == null) {
            throw new AcknowledgmentRunException(Label.Giving_Acknowledgment_RunNotFound);
        }
        if (!STATUS_READY_TO_MERGE.equals(run.Status__c)) {
            throw new AcknowledgmentRunException(Label.Giving_Acknowledgment_RunNotWaiting);
        }

        List<Acknowledgment__c> rows = AcknowledgmentSelector.forRun(runId);
        List<Acknowledgment__c> settled = new List<Acknowledgment__c>();
        List<Gift__c> stamped = new List<Gift__c>();
        for (Acknowledgment__c row : rows) {
            if (!AcknowledgmentService.STATUS_QUEUED.equals(row.Status__c)) {
                continue;
            }
            row.Status__c = AcknowledgmentService.STATUS_SENT;
            row.Sent_On__c = System.now();
            settled.add(row);
            stamped.add(
                new Gift__c(
                    Id = row.Gift__c,
                    Acknowledgment_Status__c = AcknowledgmentRuleService.STATUS_ACKNOWLEDGED,
                    Acknowledgment_Date__c = Date.today()
                )
            );
        }
        AcknowledgmentWriter.updateAcknowledgments(settled);
        AcknowledgmentWriter.stampGifts(stamped);

        run.Status__c = STATUS_COMPLETED;
        run.Finished__c = System.now();
        AcknowledgmentWriter.updateRun(run);
        return run;
    }

    /** Counts written as an email run goes, so a run that is still going shows real progress. */
    public static void recordProgress(
        Id runId,
        Integer processed,
        Integer sent,
        Integer errorCount
    ) {
        AcknowledgmentWriter.updateRun(
            new Acknowledgment_Run__c(
                Id = runId,
                Gifts_Processed__c = processed,
                Acknowledgments_Sent__c = sent,
                Errors__c = errorCount
            )
        );
    }

    /**
     * Closes an email run. A run with any failure ends Completed with errors, never Completed:
     * the distinction is the whole reason the count is kept (R-AK10).
     */
    public static void finish(Id runId, Integer processed, Integer sent, Integer errorCount) {
        AcknowledgmentWriter.updateRun(
            new Acknowledgment_Run__c(
                Id = runId,
                Gifts_Processed__c = processed,
                Acknowledgments_Sent__c = sent,
                Errors__c = errorCount,
                Status__c = errorCount > 0 ? STATUS_COMPLETED_WITH_ERRORS : STATUS_COMPLETED,
                Finished__c = System.now()
            )
        );
        AcknowledgmentService.recordLastRun(
            String.format(
                Label.Giving_Acknowledgment_EmailRunSummary,
                new List<String>{ String.valueOf(sent), String.valueOf(errorCount) }
            )
        );
    }

    private static Acknowledgment_Run__c newRun(String channel) {
        return new Acknowledgment_Run__c(
            Channel__c = channel,
            Status__c = STATUS_QUEUED,
            Gifts_Processed__c = 0,
            Acknowledgments_Sent__c = 0,
            Errors__c = 0
        );
    }
}
