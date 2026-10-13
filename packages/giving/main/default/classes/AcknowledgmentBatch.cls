/**
 * The email send, one chunk at a time (feature G-12, R-AK10).
 *
 * The scope is 90 and that number is load bearing. Apex allows ten email invocations per
 * transaction and one hundred messages per invocation, so a chunk of 90 goes out in a single
 * `Messaging.sendEmail` call with room to spare, while a chunk of 200 could not be sent at all
 * without splitting it.
 *
 * A chunk that throws is written to the Error Log and counted, and the run carries on: a bad
 * address in the middle of the queue must not stop the thank yous behind it.
 */
public with sharing class AcknowledgmentBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Messages per chunk, bounded by the platform's one hundred per invocation. */
    public static final Integer SCOPE = 90;

    private static final String LOG_CONTEXT = 'AcknowledgmentBatch.execute';

    private final Id runId;
    private Integer processed = 0;
    private Integer sent = 0;
    private Integer errors = 0;
    /** Who pressed Send now, told when the send ends; null for the nightly send (Q-04). */
    private Id notifyUserId = JobNotifier.starter();

    public AcknowledgmentBatch(Id runId) {
        this.runId = runId;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return AcknowledgmentSelector.queuedGiftsLocator();
    }

    public void execute(Database.BatchableContext context, List<Gift__c> scope) {
        try {
            AcknowledgmentService.SendCounts counts = AcknowledgmentService.sendEmails(
                scope,
                runId
            );
            processed += counts.processed;
            sent += counts.sent;
            errors += counts.errors;
        } catch (Exception chunkFailure) {
            // The whole chunk is lost, not the run. Every gift in it is still To acknowledge and
            // still unclaimed, so the next run picks it up (R-AK7).
            processed += scope.size();
            errors += scope.size();
            ErrorLogger.log(chunkFailure, LOG_CONTEXT, runId);
        }
        AcknowledgmentRunService.recordProgress(runId, processed, sent, errors);
    }

    public void finish(Database.BatchableContext context) {
        AcknowledgmentRunService.finish(runId, processed, sent, errors);
        JobNotifier.aboutRecord(
            notifyUserId,
            Label.Giving_JobNotice_Acknowledgments,
            false,
            String.format(
                Label.Giving_JobNotice_AcknowledgmentsBody,
                new List<Object>{ processed.format(), sent.format(), errors.format() }
            ),
            runId
        );
    }
}
