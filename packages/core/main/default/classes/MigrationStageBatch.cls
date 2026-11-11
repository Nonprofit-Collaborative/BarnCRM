/**
 * Reads an import step's source records into its Import Batch, page by page, in the running
 * administrator's access, then starts the batch's dry run (MIG-01, canonical model R-MR2). Each
 * record becomes one staged row, or the rows the kit's extension returns. A failure stops the
 * staging and marks the batch Failed with the reason in its run log, so the step can be started
 * again; nothing outside the batch is written.
 */
public with sharing class MigrationStageBatch implements Database.Batchable<SObject>, Database.Stateful {
	private static final String CONTEXT = 'MigrationStageBatch';

	private Id batchId;
	private String kitKey;
	private String stepKey;
	/** The file row number of the next staged row: row 1 is a file's header. */
	private Integer nextRow = 2;
	private String failure;

	public MigrationStageBatch(Id batchId, String kitKey, String stepKey) {
		this.batchId = batchId;
		this.kitKey = kitKey;
		this.stepKey = stepKey;
	}

	public Database.QueryLocator start(Database.BatchableContext job) {
		try {
			return source().locator();
		} catch (Exception unreadable) {
			// Nothing to read; finish marks the batch Failed with the reason.
			failure = unreadable.getMessage();
			ErrorLogger.log(unreadable, CONTEXT);
			return Database.getQueryLocator(
				[SELECT Id FROM Migration_Run__c WHERE Id = NULL WITH USER_MODE]
			);
		}
	}

	public void execute(Database.BatchableContext job, List<SObject> records) {
		if (failure != null) {
			return;
		}
		try {
			Migration_Kit__mdt kit = MigrationKitService.kitNamed(kitKey);
			MigrationKitExtension extension = MigrationKitService.extensionFor(kit);
			List<Map<String, Object>> rows = extension == null
				? null
				: extension.rows(stepKey, records);
			if (rows == null) {
				rows = source().rows(records);
			}
			ImportBatchService.stageRows(batchId, rows, nextRow);
			nextRow += rows.size();
		} catch (Exception stopped) {
			failure = stopped.getMessage();
			ErrorLogger.log(stopped, CONTEXT);
		}
	}

	public void finish(Database.BatchableContext job) {
		if (failure == null) {
			try {
				ImportBatchService.startDryRun(batchId);
			} catch (Exception refused) {
				failure = refused.getMessage();
				ErrorLogger.log(refused, CONTEXT);
			}
		}
		if (failure != null) {
			ImportBatchService.finish(
				batchId,
				true,
				true,
				new List<String>{
					String.format(
						BarnHelp.text('Core', 'Core_Migration_StagingFailed'),
						new List<String>{ failure }
					)
				},
				null,
				null
			);
		}
	}

	private MigrationKitService.Source source() {
		Migration_Kit__mdt kit = MigrationKitService.kitNamed(kitKey);
		return new MigrationKitService.Source(MigrationKitService.stepNamed(kit, stepKey));
	}
}
