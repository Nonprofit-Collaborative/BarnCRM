/**
 * The nightly reconciliation.
 *
 * One definition per batch chunk, because a full recalculation of a definition is itself a job
 * chain inside the vendored engine: giving the platform one definition at a time keeps each chunk
 * small and lets a definition that fails be logged and skipped without stopping the rest.
 *
 * Which definitions run is R-R4: Scheduled, and Both. A Real-time definition is already correct
 * when the transaction that changed a record ends, and re-running it nightly would be work for no
 * change; a Both definition is reconciled here precisely because real time can miss a change that
 * happened outside a trigger.
 */
public with sharing class RollupBatch implements Database.Batchable<SObject>, Database.Stateful {
    private static final String LOG_CONTEXT = 'RollupBatch';

    /** How many definitions completed, carried across chunks for the completion log. */
    @TestVisible
    private Integer completed = 0;

    /** How many failed, so a run that did nothing is visible rather than silent. */
    @TestVisible
    private Integer failed = 0;

    public Database.QueryLocator start(Database.BatchableContext context) {
        // System mode, stated because API 67.0 would otherwise read in user mode: this is the
        // engine's read of its definitions (as RollupSelector.selectAll is), and the job runs
        // as whoever scheduled it, whose access must not decide which totals are reconciled
        // (ADR-0021).
        return Database.getQueryLocator(
            [
                SELECT Id
                FROM Rollup_Definition__c
                WHERE Active__c = TRUE AND Mode__c IN ('Scheduled', 'Both')
                WITH SYSTEM_MODE
                ORDER BY Target_Object__c, Name
            ]
        );
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        for (SObject row : scope) {
            try {
                RollupService.recalculate(row.Id);
                this.completed++;
            } catch (Exception refused) {
                this.failed++;
                ErrorLogger.log(refused, LOG_CONTEXT, row.Id);
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        if (this.failed > 0) {
            ErrorLogger.logMessage(
                String.format(
                    System.Label.Core_Rollups_BatchIncomplete,
                    new List<String>{ String.valueOf(this.failed), String.valueOf(this.completed) }
                ),
                LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
        }
    }
}
