/**
 * Deletes the archived rows that name an erased person (canonical model R-ARC6, ADR-0240 archive
 * rules and big object archive item 10), queued by `ArchiveErasureExtension`.
 *
 * - Scan links (no DML): run only when the person's Erasure record exists, so a preview or an
 *   erasure rolled back does nothing. Each walks the archived objects in index order, a page at a
 *   time, and `deleteImmediate`s the rows whose Original Id is one of the person's records or
 *   whose People names one of them.
 * - The final link (DML only, no immediate call) subtracts the rows deleted from
 *   `Archived_Record_Count__c`.
 *
 * Big object reads and deletes run in system mode: erasure is the organization's duty, whoever
 * erases, and the person erasing was checked by `PersonErasure`.
 */
public with sharing class ArchiveErasureJob implements Queueable {
	/** Rows read per page. */
	@TestVisible
	private static final Integer PAGE = 200;
	/** Pages read per scan link. */
	@TestVisible
	private static final Integer PAGES_PER_LINK = 10;
	private static final String LOG_CONTEXT = 'ArchiveErasureJob';

	private final Id personId;
	private Set<String> people;
	private Boolean started = false;
	private Boolean counting = false;
	private String objectName;
	private Datetime afterAt;
	private String afterId;
	private Integer deleted = 0;
	private String failure;

	public ArchiveErasureJob(Id personId) {
		this.personId = personId;
	}

	public void execute(QueueableContext context) {
		if (counting) {
			// The final link: DML only.
			if (failure != null) {
				ErrorLogger.logMessages(new List<String>{ failure }, LOG_CONTEXT,ErrorLogger.SEVERITY_ERROR);
			}
			BigObjectArchiveJob.addToCount(-deleted);
			return;
		}
		try {
			if (!started) {
				people = erasedRecords();
				if (people == null) {
					return;
				}
				started = true;
				objectName = ArchiveStore.get().nextObject(null);
			}
			scan();
		} catch (Exception failed) {
			// Logged by the final link: an Error Log insert may not share this transaction.
			failure = failed.getMessage();
			objectName = null;
		}
		counting = objectName == null;
		if (!counting || deleted > 0 || failure != null) {
			BigObjectArchiveJob.queue(this);
		}
	}

	/**
	 * The Ids the erasure covers, from the Erasure record: the erased record, and the contact
	 * or person account it names. Null when there is no Erasure record for the person.
	 */
	private Set<String> erasedRecords() {
		String id18 = String.valueOf(personId);
		List<Erasure__c> found = [
			SELECT Erased_Record_Id__c, Contact__c, Person_Account__c
			FROM Erasure__c
			WHERE Erased_Record_Id__c = :id18
			WITH SYSTEM_MODE
			LIMIT 1
		];
		if (found.isEmpty()) {
			return null;
		}
		Set<String> result = new Set<String>{ id18 };
		if (found[0].Contact__c != null) {
			result.add(String.valueOf(found[0].Contact__c));
		}
		if (found[0].Person_Account__c != null) {
			result.add(String.valueOf(found[0].Person_Account__c));
		}
		return result;
	}

	/** Reads up to `PAGES_PER_LINK` pages and deletes the rows naming the person. */
	private void scan() {
		List<ArchiveStore.Key> doomed = new List<ArchiveStore.Key>();
		// Apex names ignore case: the counter must not be called page, which would hide PAGE.
		for (Integer pagesRead = 0; pagesRead < PAGES_PER_LINK && objectName != null; pagesRead++) {
			List<Archived_Record__b> rows = ArchiveStore.get().scan(objectName, afterAt, afterId, PAGE);
			for (Archived_Record__b row : rows) {
				if (namesPerson(row)) {
					doomed.add(new ArchiveStore.Key(row.Object_Name__c, row.Archived_At__c, row.Original_Id__c));
				}
			}
			if (rows.size() < PAGE) {
				objectName = ArchiveStore.get().nextObject(objectName);
				afterAt = null;
				afterId = null;
			} else {
				Archived_Record__b last = rows[rows.size() - 1];
				afterAt = last.Archived_At__c;
				afterId = last.Original_Id__c;
			}
		}
		if (!doomed.isEmpty()) {
			deleted += ArchiveStore.get().deleteRows(doomed);
		}
	}

	private Boolean namesPerson(Archived_Record__b row) {
		if (people.contains(row.Original_Id__c)) {
			return true;
		}
		for (String one : people) {
			if (ArchiveRecordJson.names(row.Person_Ids__c, one)) {
				return true;
			}
		}
		return false;
	}
}
