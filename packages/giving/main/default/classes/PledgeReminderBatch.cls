/**
 * The pledge reminder run, one chunk at a time (G-30).
 *
 * The scope is 90 for the reason `AcknowledgmentBatch` gives: Apex allows one hundred messages
 * per email invocation, and a chunk of 90 goes out in a single call with room to spare.
 *
 * The run refuses to start its work when reminders are off: the switch is checked again here, in
 * `PledgeReminderService.process`, so a batch queued before an administrator turned the feature
 * off sends nothing. A chunk that throws is written to the Error Log and counted, and the run
 * carries on.
 */
public with sharing class PledgeReminderBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** Installments per chunk, bounded by the platform's one hundred messages per invocation. */
    public static final Integer SCOPE = 90;

    private static final String LOG_CONTEXT = 'PledgeReminderBatch.execute';
    /** The settings console section a finished run's notice opens, as the donor level run does. */
    private static final String GIVING_SECTION = 'Giving';

    private PledgeReminderService.Counts totals = new PledgeReminderService.Counts();
    /** Who pressed Send now, told when the run ends; null for the nightly run. */
    private Id notifyUserId = JobNotifier.starter();

    public Database.QueryLocator start(Database.BatchableContext context) {
        List<Pledge_Reminder_Step__c> steps = PledgeReminderSelector.activeSteps();
        Date today = Date.today();
        return PledgeReminderSelector.openInstallmentsLocator(
            PledgeReminderService.windowFrom(steps, today),
            PledgeReminderService.windowTo(steps, today)
        );
    }

    public void execute(Database.BatchableContext context, List<Installment__c> scope) {
        try {
            totals.add(PledgeReminderService.process(scope));
        } catch (Exception chunkFailure) {
            // The whole chunk is lost, not the run. Nothing in it was claimed that was not also
            // settled, so the next run picks the rest up.
            totals.processed += scope.size();
            totals.errors += scope.size();
            ErrorLogger.log(chunkFailure, LOG_CONTEXT);
        }
    }

    public void finish(Database.BatchableContext context) {
        String summary = String.format(
            Label.Giving_PledgeReminders_RunSummary,
            new List<String>{
                String.valueOf(totals.emails),
                String.valueOf(totals.letters),
                String.valueOf(totals.errors)
            }
        );
        PledgeReminderService.recordLastRun(summary);
        JobNotifier.aboutSettings(
            notifyUserId,
            Label.Giving_JobNotice_PledgeReminders,
            false,
            summary,
            GIVING_SECTION
        );
    }
}
