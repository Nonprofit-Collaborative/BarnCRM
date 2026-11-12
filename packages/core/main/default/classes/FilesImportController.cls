/**
 * The Import Files panel's controller (`filesImport`, C-70, canonical model 29FI): thin, plain
 * shapes; the rules and permission checks are in `FilesImportService`.
 */
public with sharing class FilesImportController {
	/** The record Ids among those given that name no record the person can see (R-FI2). */
	@AuraEnabled
	public static List<String> check(List<String> recordIds) {
		try {
			return FilesImportService.unseen(recordIds);
		} catch (Exception e) {
			throw wrapped(e, 'FilesImportController.check');
		}
	}

	/** Starts a load; returns the job's Id. */
	@AuraEnabled
	public static Id start(String fileName, Integer rowCount) {
		try {
			return FilesImportService.start(fileName, rowCount).Id;
		} catch (Exception e) {
			throw wrapped(e, 'FilesImportController.start');
		}
	}

	/** Saves one group of files. */
	@AuraEnabled
	public static FilesImportService.GroupResult addFiles(
		Id jobId,
		List<FilesImportService.IncomingFile> files
	) {
		try {
			return FilesImportService.addFiles(jobId, files);
		} catch (Exception e) {
			throw wrapped(e, 'FilesImportController.addFiles');
		}
	}

	/** Ends a load. */
	@AuraEnabled
	public static FilesImportService.JobView finish(Id jobId) {
		try {
			return FilesImportService.finish(jobId);
		} catch (Exception e) {
			throw wrapped(e, 'FilesImportController.finish');
		}
	}

	/** Undoes a load, after the person typed the number of files it saved. */
	@AuraEnabled
	public static FilesImportService.JobView undo(Id jobId, Integer confirmedFiles) {
		try {
			return FilesImportService.undo(jobId, confirmedFiles);
		} catch (Exception e) {
			throw wrapped(e, 'FilesImportController.undo');
		}
	}

	/** The newest files jobs, or null for someone who may not import files. */
	@AuraEnabled
	public static List<FilesImportService.JobView> getJobs() {
		try {
			return FilesImportService.allowed() ? FilesImportService.jobs() : null;
		} catch (Exception e) {
			throw wrapped(e, 'FilesImportController.getJobs');
		}
	}

	private static AuraHandledException wrapped(Exception e, String context) {
		return DataJobs.userError(e, context, e instanceof FilesImportService.FilesImportException);
	}
}
