/**
 * The daily job that extends the schedules of active recurring commitments up to the
 * org's generation horizon, so an open-ended schedule always has the next year of
 * expected payments in front of it without ever generating rows forever (R-CM2).
 *
 * It starts a batch rather than doing the work here, because the number of expected
 * payments an org implies is unbounded and a single transaction may not insert them all.
 * The batch records when it finished on Giving Settings, which is what the Hub shows.
 */
public with sharing class InstallmentTopUpSchedulable implements Schedulable {
	public void execute(SchedulableContext context) {
		try {
			AsyncStarter.batch(
				new InstallmentTopUpBatch(),
				InstallmentTopUpBatch.CHUNK_SIZE,
				'InstallmentTopUpSchedulable'
			);
		} catch (Exception jobFailure) {
			ErrorLogger.log(jobFailure, 'InstallmentTopUpSchedulable');
		}
	}
}
