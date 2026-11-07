/**
 * Files given with a form's answers (C-42c; canonical model R-FS7; ADR-0184 public forms on a
 * Salesforce Site, decision 11). A file question's answer is the file's name; the file comes
 * beside the answers as `{ key: { name, data } }`, `data` in base64. Read here, kept on the
 * submission as a Salesforce File, and shared with the person and organization processing writes.
 *
 * Inherited sharing: the intake keeps a guest's files in system mode, as it keeps the submission;
 * the staff runner and processing run in user mode.
 */
public inherited sharing class FormFiles {
	/**
	 * The most one submission's files may hold together: 1 MB. A file arrives as base64 text and is
	 * decoded beside it, which must fit the 6 MB a request's Apex may hold.
	 */
	public static final Integer MAX_BYTES = 1024 * 1024;

	/** One file, read and checked. */
	public class Upload {
		public String key;
		public String name;
		public Blob body;
	}

	/**
	 * The files for the file questions answered: each needs its file, named as answered, and
	 * together they fit MAX_BYTES. What is wrong goes in `problems` by field key (fileMissing,
	 * fileTooLarge); a file for a question not answered is ignored.
	 */
	public static List<Upload> read(
		Map<String, Object> definition,
		Map<String, Object> counted,
		Map<String, Object> files,
		Map<String, String> problems
	) {
		List<Upload> uploads = new List<Upload>();
		Integer total = 0;
		for (Map<String, Object> field : FormRules.allFields(definition)) {
			String key = String.valueOf(field.get('key'));
			if (field.get('type') != 'file' || !counted.containsKey(key)) {
				continue;
			}
			Upload upload = decoded(files == null ? null : files.get(key));
			if (upload == null || upload.name != String.valueOf(counted.get(key))) {
				problems.put(key, 'fileMissing');
				continue;
			}
			total += upload.body.size();
			if (total > MAX_BYTES) {
				problems.put(key, 'fileTooLarge');
				continue;
			}
			upload.key = key;
			uploads.add(upload);
		}
		return uploads;
	}

	private static Upload decoded(Object value) {
		if (!(value instanceof Map<String, Object>)) {
			return null;
		}
		Map<String, Object> file = (Map<String, Object>) value;
		if (!(file.get('name') instanceof String) || !(file.get('data') instanceof String)) {
			return null;
		}
		Upload upload = new Upload();
		upload.name = ((String) file.get('name')).trim();
		try {
			upload.body = EncodingUtil.base64Decode((String) file.get('data'));
		} catch (Exception notBase64) {
			return null;
		}
		return upload.body.size() == 0 ? null : upload;
	}

	/**
	 * Keeps the files on the submission as Salesforce Files: in system mode for the intake (a
	 * guest has no object access), else in user mode.
	 */
	public static void keep(Id submissionId, List<Upload> uploads, Boolean systemMode) {
		List<ContentVersion> versions = new List<ContentVersion>();
		for (Upload upload : uploads) {
			versions.add(
				new ContentVersion(
					Title = upload.name,
					PathOnClient = upload.name,
					VersionData = upload.body,
					FirstPublishLocationId = submissionId
				)
			);
		}
		if (versions.isEmpty()) {
			return;
		}
		if (systemMode) {
			Database.insert(versions, AccessLevel.SYSTEM_MODE);
		} else {
			Database.insert(versions, AccessLevel.USER_MODE);
		}
	}

	/**
	 * Shares the submission's files with the records given (the person and organization written),
	 * as the person processing, once each: processing again adds nothing twice.
	 */
	public static void share(Id submissionId, List<Id> recordIds) {
		Set<Id> targets = new Set<Id>(recordIds);
		targets.remove(null);
		if (targets.isEmpty()) {
			return;
		}
		Set<Id> documents = new Set<Id>();
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId
			FROM ContentDocumentLink
			WHERE LinkedEntityId = :submissionId
			WITH USER_MODE
		]) {
			documents.add(link.ContentDocumentId);
		}
		if (documents.isEmpty()) {
			return;
		}
		Set<String> linked = new Set<String>();
		for (ContentDocumentLink link : [
			SELECT ContentDocumentId, LinkedEntityId
			FROM ContentDocumentLink
			WHERE ContentDocumentId IN :documents AND LinkedEntityId IN :targets
			WITH USER_MODE
		]) {
			linked.add('' + link.ContentDocumentId + link.LinkedEntityId);
		}
		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		for (Id document : documents) {
			for (Id target : targets) {
				if (!linked.contains('' + document + target)) {
					links.add(
						new ContentDocumentLink(
							ContentDocumentId = document,
							LinkedEntityId = target,
							ShareType = 'V'
						)
					);
				}
			}
		}
		if (!links.isEmpty()) {
			insert as user links;
		}
	}
}
