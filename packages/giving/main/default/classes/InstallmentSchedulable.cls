/**
 * The nightly job that marks unpaid installments Overdue once the org's grace period has
 * passed (R-IN2). Scheduled from the Nightly Jobs page of the BarnCRM Settings console
 * (ADR-0038), which is also where its last run is read.
 *
 * Every run records itself, including a run that found nothing to mark. An empty stamp then
 * means the pass has never run, which is the state an org is in until somebody schedules it,
 * and is a different sentence on the page from "ran last night and marked nothing" (R-IN5).
 */
public with sharing class InstallmentSchedulable implements Schedulable {
    private static final String LOG_CONTEXT = 'Installment overdue pass';

    public void execute(SchedulableContext context) {
        String summary;
        try {
            Integer marked = CommitmentService.markOverdue();
            summary = marked == 0
                ? System.Label.Giving_NightlyJobs_OverdueNoneFound
                : String.format(
                      System.Label.Giving_NightlyJobs_OverdueSummaryFormat,
                      new List<String>{ String.valueOf(marked) }
                  );
        } catch (Exception jobFailure) {
            ErrorLogger.log(jobFailure, LOG_CONTEXT);
            summary = System.Label.Giving_NightlyJobs_RunFailed;
        }
        try {
            CommitmentService.recordOverdueRun(System.now(), summary);
        } catch (Exception recordFailure) {
            // A pass that worked and could not say so is still a pass that worked, so this is
            // logged rather than thrown. It is also the failure that would otherwise make the
            // settings page quietly claim the job has never run.
            ErrorLogger.log(recordFailure, LOG_CONTEXT);
        }
    }
}
