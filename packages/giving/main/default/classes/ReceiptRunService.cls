/**
 * Starting a generation run and keeping its record honest while it goes (canonical model 25C).
 *
 * A run record exists because a year end run over tens of thousands of donors takes long enough
 * that "did it finish" is a real question, and because a chunk that failed has to be visible
 * somewhere other than a log nobody opens.
 */
public with sharing class ReceiptRunService {
	public static final String STATUS_QUEUED = 'Queued';
	public static final String STATUS_RUNNING = 'Running';
	public static final String STATUS_COMPLETED = 'Completed';
	public static final String STATUS_COMPLETED_WITH_ERRORS = 'Completed with errors';
	public static final String STATUS_FAILED = 'Failed';

	public class ReceiptRunException extends Exception {
	}

	/**
	 * Starts a consolidated statement run for one year and returns its record.
	 *
	 * The run record is written before the batch is queued, so a run that fails to queue at all
	 * still leaves something behind saying it was asked for.
	 */
	public static Receipt_Run__c startStatementRun(Integer statementYear) {
		if (!ReceiptService.canIssueReceipts()) {
			throw new ReceiptRunException(BarnHelp.text('Giving', 'Giving_Receipt_NoPermission'));
		}
		Integer year = statementYear == null ? defaultStatementYear() : statementYear;

		Receipt_Run__c run = new Receipt_Run__c(
			Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
			Statement_Year__c = year,
			Status__c = STATUS_QUEUED,
			Donors_Processed__c = 0,
			Receipts_Issued__c = 0,
			Errors__c = 0
		);
		ReceiptWriter.insertRun(run);

		try {
			Id jobId = AsyncStarter.batch(
				new ReceiptStatementBatch(year, run.Id),
				ReceiptStatementBatch.SCOPE,
				'ReceiptRunService'
			);
			run.Async_Job_Id__c = jobId;
			run.Status__c = STATUS_RUNNING;
			run.Started__c = System.now();
		} catch (Exception queueFailure) {
			run.Status__c = STATUS_FAILED;
			run.Finished__c = System.now();
			ErrorLogger.log(queueFailure, 'ReceiptRunService.startStatementRun', run.Id);
		}
		ReceiptWriter.updateRun(run);
		return run;
	}

	/**
	 * The year an administrator most likely means: the one they set in settings, and last year if
	 * they have not, because a statement run happens in January for the year that just ended.
	 */
	public static Integer defaultStatementYear() {
		Decimal configured = Giving_Settings__c.getOrgDefaults().Receipt_Statement_Year__c;
		return configured == null ? Date.today().year() - 1 : configured.intValue();
	}

	/** Counts written as the run goes, so a run that is still going shows real progress (R-RR3). */
	public static void recordProgress(
		Id runId,
		Integer donorsProcessed,
		Integer receiptsIssued,
		Integer errors
	) {
		ReceiptWriter.updateRun(
			new Receipt_Run__c(
				Id = runId,
				Donors_Processed__c = donorsProcessed,
				Receipts_Issued__c = receiptsIssued,
				Errors__c = errors
			)
		);
	}

	/**
	 * Closes a run. A run with any failed chunk ends Completed with errors, never Completed: the
	 * distinction is the whole reason the count is kept (R-RR1).
	 */
	public static void finish(
		Id runId,
		Integer donorsProcessed,
		Integer receiptsIssued,
		Integer errors
	) {
		ReceiptWriter.updateRun(
			new Receipt_Run__c(
				Id = runId,
				Donors_Processed__c = donorsProcessed,
				Receipts_Issued__c = receiptsIssued,
				Errors__c = errors,
				Status__c = errors > 0 ? STATUS_COMPLETED_WITH_ERRORS : STATUS_COMPLETED,
				Finished__c = System.now()
			)
		);
	}
}
