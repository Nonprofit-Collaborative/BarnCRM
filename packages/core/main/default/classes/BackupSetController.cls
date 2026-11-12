/**
 * The Backup Sets panel's controller (`backupSets`, C-66, canonical model R-SQ15): thin, plain
 * shapes; the rules and permission checks are in `BackupSetService`.
 */
public with sharing class BackupSetController {
	@AuraEnabled
	public static BackupSetService.Panel getPage() {
		try {
			return BackupSetService.page();
		} catch (Exception e) {
			throw wrapped(e, 'BackupSetController.getPage');
		}
	}

	/** The person's recent runs for Data Jobs, or null for someone who may not use Backup Sets. */
	@AuraEnabled
	public static List<BackupSetService.RunView> getRuns() {
		try {
			return BackupSetService.allowed() ? BackupSetService.runs() : null;
		} catch (Exception e) {
			throw wrapped(e, 'BackupSetController.getRuns');
		}
	}

	/** Adds one of the person's saved queries to Backup Sets, or takes it off. */
	@AuraEnabled
	public static BackupSetService.Panel setBackup(Id queryId, Boolean asSet) {
		try {
			BackupSetService.setBackup(queryId, asSet);
			return BackupSetService.page();
		} catch (Exception e) {
			throw wrapped(e, 'BackupSetController.setBackup');
		}
	}

	/** Starts a run now. */
	@AuraEnabled
	public static BackupSetService.Panel runNow(Id queryId) {
		try {
			BackupSetService.run(queryId);
			return BackupSetService.page();
		} catch (Exception e) {
			throw wrapped(e, 'BackupSetController.runNow');
		}
	}

	private static AuraHandledException wrapped(Exception e, String context) {
		return DataJobs.userError(e, context, e instanceof BackupSetService.BackupSetException);
	}
}
