/**
 * Every read and write of the Archived Record big object (canonical model Section 29D1, R-ARC1,
 * ADR-NEXT archive rules and big object archive). One place, so tests replace it: a big object
 * cannot be written or read in an Apex test.
 *
 * Every read filters on the index fields in order, never skipping one: a filter with a gap aborts
 * the transaction and cannot be caught. Writes and deletes run in system mode after the caller
 * has checked the person; `page` and `rows` read in user mode, so only a person granted the object
 * (BarnCRM Admin) sees a row. No method here may follow ordinary DML in the same transaction.
 */
public virtual with sharing class ArchiveStore {
	@TestVisible
	private static ArchiveStore current;

	/** The store in use: the platform's, or a test's. */
	public static ArchiveStore get() {
		if (current == null) {
			current = new ArchiveStore();
		}
		return current;
	}

	/** A row's full key. */
	public class Key {
		@AuraEnabled
		public String objectName;
		@AuraEnabled
		public Datetime archivedAt;
		@AuraEnabled
		public String originalId;

		public Key(String objectName, Datetime archivedAt, String originalId) {
			this.objectName = objectName;
			this.archivedAt = archivedAt;
			this.originalId = originalId;
		}

		/** The row with only its index fields, as `deleteImmediate` needs it. */
		public Archived_Record__b row() {
			return new Archived_Record__b(
				Object_Name__c = objectName,
				Archived_At__c = archivedAt,
				Original_Id__c = originalId
			);
		}
	}

	/** Writes rows; the same key overwrites. Results are in the rows' order. */
	public virtual List<Boolean> insertRows(List<Archived_Record__b> rows) {
		List<Boolean> result = new List<Boolean>();
		if (rows.isEmpty() || !Schema.SObjectType.Archived_Record__b.isCreateable()) {
			for (Archived_Record__b row : rows) {
				result.add(false);
			}
			return result;
		}
		// NOPMD: ApexCRUDViolation, which does not see the isCreateable check above.
		// Access mode: system. insertImmediate takes no AccessLevel; create access is checked above.
		for (Database.SaveResult saved : Database.insertImmediate(rows)) { // NOPMD
			result.add(saved.isSuccess());
		}
		return result;
	}

	/** Deletes rows by key; returns how many went. */
	public virtual Integer deleteRows(List<Key> keys) {
		if (keys.isEmpty()) {
			return 0;
		}
		List<Archived_Record__b> rows = new List<Archived_Record__b>();
		for (Key key : keys) {
			rows.add(key.row());
		}
		Integer deleted = 0;
		// A big object grants only Read and Create, so there is no delete permission to check.
		// Callers are admin paths (rule runs, restore) or erasure. NOPMD: ApexCRUDViolation.
		// Access mode: system. deleteImmediate takes no AccessLevel.
		for (Database.DeleteResult result : Database.deleteImmediate(rows)) { // NOPMD
			deleted += result.isSuccess() ? 1 : 0;
		}
		return deleted;
	}

	/** Which of these Original Ids have a row at this object and time, read in system mode. */
	public virtual Set<String> present(String objectName, Datetime archivedAt, Set<String> originalIds) {
		Set<String> found = new Set<String>();
		if (originalIds.isEmpty()) {
			return found;
		}
		for (Archived_Record__b row : [
			SELECT Original_Id__c
			FROM Archived_Record__b
			WHERE Object_Name__c = :objectName AND Archived_At__c = :archivedAt AND Original_Id__c IN :originalIds
			WITH SYSTEM_MODE
		]) {
			found.add(row.Original_Id__c);
		}
		return found;
	}

	/** Whole rows by key, read in user mode. */
	public virtual List<Archived_Record__b> rows(String objectName, Datetime archivedAt, Set<String> originalIds) {
		return [
			SELECT
				Object_Name__c,
				Archived_At__c,
				Original_Id__c,
				Record_Name__c,
				Owner_Id__c,
				Record_JSON__c,
				Rule_Id__c,
				Rule_Name__c,
				CreatedById
			FROM Archived_Record__b
			WHERE Object_Name__c = :objectName AND Archived_At__c = :archivedAt AND Original_Id__c IN :originalIds
			WITH USER_MODE
		];
	}

	/**
	 * One page of an object's rows, newest first, between `fromAt` and `toAt`, in user mode and
	 * without the JSON. After a row (`afterAt`, `afterId`), the rest of its second come first,
	 * then older ones: two reads, each without a gap in the key.
	 */
	public virtual List<Archived_Record__b> page(
		String objectName,
		Datetime fromAt,
		Datetime toAt,
		Datetime afterAt,
		String afterId,
		Integer size
	) {
		List<Archived_Record__b> result = new List<Archived_Record__b>();
		Datetime newest = toAt;
		if (afterAt != null) {
			result.addAll(
				[
					SELECT Object_Name__c, Archived_At__c, Original_Id__c, Record_Name__c, Owner_Id__c, Rule_Name__c, CreatedById
					FROM Archived_Record__b
					WHERE Object_Name__c = :objectName AND Archived_At__c = :afterAt AND Original_Id__c > :afterId
					WITH USER_MODE
					LIMIT :size
				]
			);
			newest = afterAt.addSeconds(-1) < toAt ? afterAt.addSeconds(-1) : toAt;
		}
		Integer room = size - result.size();
		if (room > 0) {
			result.addAll(
				[
					SELECT Object_Name__c, Archived_At__c, Original_Id__c, Record_Name__c, Owner_Id__c, Rule_Name__c, CreatedById
					FROM Archived_Record__b
					WHERE Object_Name__c = :objectName AND Archived_At__c >= :fromAt AND Archived_At__c <= :newest
					WITH USER_MODE
					LIMIT :room
				]
			);
		}
		return result;
	}

	/**
	 * The keys and people of up to `size` rows of an object after a row, in system mode, for the
	 * erasure scan: the rest of the row's second, then older ones.
	 */
	public virtual List<Archived_Record__b> scan(String objectName, Datetime afterAt, String afterId, Integer size) {
		List<Archived_Record__b> result = new List<Archived_Record__b>();
		if (afterAt == null) {
			return [
				SELECT Object_Name__c, Archived_At__c, Original_Id__c, Person_Ids__c
				FROM Archived_Record__b
				WHERE Object_Name__c = :objectName
				WITH SYSTEM_MODE
				LIMIT :size
			];
		}
		result.addAll(
			[
				SELECT Object_Name__c, Archived_At__c, Original_Id__c, Person_Ids__c
				FROM Archived_Record__b
				WHERE Object_Name__c = :objectName AND Archived_At__c = :afterAt AND Original_Id__c > :afterId
				WITH SYSTEM_MODE
				LIMIT :size
			]
		);
		Integer room = size - result.size();
		if (room > 0) {
			result.addAll(
				[
					SELECT Object_Name__c, Archived_At__c, Original_Id__c, Person_Ids__c
					FROM Archived_Record__b
					WHERE Object_Name__c = :objectName AND Archived_At__c < :afterAt
					WITH SYSTEM_MODE
					LIMIT :room
				]
			);
		}
		return result;
	}

	/** The first archived object name after `afterName` (null for the first), or null. */
	public virtual String nextObject(String afterName) {
		List<Archived_Record__b> found = afterName == null
			? [SELECT Object_Name__c FROM Archived_Record__b WITH SYSTEM_MODE LIMIT 1]
			: [
					SELECT Object_Name__c
					FROM Archived_Record__b
					WHERE Object_Name__c > :afterName
					WITH SYSTEM_MODE
					LIMIT 1
				];
		return found.isEmpty() ? null : found[0].Object_Name__c;
	}
}
