/**
 * The nightly donor level pass. Scheduled by `GivingScheduler` with the module's other daily jobs
 * so that Maria never opens Setup to schedule Apex (Principle 1).
 *
 * It runs after the rollups have settled and is safe to run twice on the same night: assignment
 * is idempotent, so a second run over unchanged data writes nothing (R-DL6).
 */
public with sharing class DonorLevelSchedulable implements Schedulable {
	/** Accounts per chunk. Placement is arithmetic on fields already queried, so the default is fine. */
	public static final Integer CHUNK_SIZE = 200;

	public void execute(SchedulableContext context) {
		// Donor scores are kept whether or not levels are on (the Automation page switches them);
		// the batch places levels only when they are enabled (G-19, R-DT5).
		AsyncStarter.batch(new DonorLevelBatch(), CHUNK_SIZE, 'DonorLevelSchedulable');
	}
}
