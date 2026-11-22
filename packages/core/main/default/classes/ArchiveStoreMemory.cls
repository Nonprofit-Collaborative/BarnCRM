/**
 * The Archived Record store held in memory, for tests: Apex tests cannot write or read a big object
 * (canonical model Section 29D1). It keeps the index order and the same-key overwrite the platform
 * has, so the archive, restore and erasure links behave as they do in an org.
 */
@IsTest
public class ArchiveStoreMemory extends ArchiveStore {
	public Map<String, Archived_Record__b> rowsByKey = new Map<String, Archived_Record__b>();
	/** Original Ids whose insert reports success but which are never stored. */
	public Set<String> lostOnInsert = new Set<String>();
	/** How many delete calls to refuse next, as the platform may. */
	public Integer deletesRefused = 0;

	/** Puts a memory store in place for this test and returns it. */
	public static ArchiveStoreMemory install() {
		ArchiveStoreMemory store = new ArchiveStoreMemory();
		ArchiveStore.current = store;
		return store;
	}

	private static String keyOf(String objectName, Datetime archivedAt, String originalId) {
		return objectName + '|' + archivedAt.getTime() + '|' + originalId;
	}

	public override List<Boolean> insertRows(List<Archived_Record__b> rows) {
		List<Boolean> result = new List<Boolean>();
		for (Archived_Record__b row : rows) {
			if (!lostOnInsert.contains(row.Original_Id__c)) {
				rowsByKey.put(keyOf(row.Object_Name__c, row.Archived_At__c, row.Original_Id__c), row);
			}
			result.add(true);
		}
		return result;
	}

	public override Integer deleteRows(List<ArchiveStore.Key> keys) {
		if (deletesRefused > 0) {
			deletesRefused--;
			throw new DmlException('Refused by the test');
		}
		Integer deleted = 0;
		for (ArchiveStore.Key key : keys) {
			if (rowsByKey.remove(keyOf(key.objectName, key.archivedAt, key.originalId)) != null) {
				deleted++;
			}
		}
		return deleted;
	}

	public override Set<String> present(String objectName, Datetime archivedAt, Set<String> originalIds) {
		Set<String> found = new Set<String>();
		for (String one : originalIds) {
			if (rowsByKey.containsKey(keyOf(objectName, archivedAt, one))) {
				found.add(one);
			}
		}
		return found;
	}

	public override List<Archived_Record__b> rows(String objectName, Datetime archivedAt, Set<String> originalIds) {
		List<Archived_Record__b> result = new List<Archived_Record__b>();
		for (String one : originalIds) {
			Archived_Record__b row = rowsByKey.get(keyOf(objectName, archivedAt, one));
			if (row != null) {
				result.add(row);
			}
		}
		return result;
	}

	/** One object's rows in index order: newest first, then Original Id. */
	public List<Archived_Record__b> ordered(String objectName) {
		List<String> keys = new List<String>();
		Map<String, Archived_Record__b> bySortKey = new Map<String, Archived_Record__b>();
		for (Archived_Record__b row : rowsByKey.values()) {
			if (row.Object_Name__c == objectName) {
				// Newest first: a smaller sort key for a later time.
				String sortKey =
					String.valueOf(9999999999999L - row.Archived_At__c.getTime()).leftPad(13, '0') + row.Original_Id__c;
				keys.add(sortKey);
				bySortKey.put(sortKey, row);
			}
		}
		keys.sort();
		List<Archived_Record__b> result = new List<Archived_Record__b>();
		for (String sortKey : keys) {
			result.add(bySortKey.get(sortKey));
		}
		return result;
	}

	public override List<Archived_Record__b> page(
		String objectName,
		Datetime fromAt,
		Datetime toAt,
		Datetime afterAt,
		String afterId,
		Integer size
	) {
		List<Archived_Record__b> result = new List<Archived_Record__b>();
		for (Archived_Record__b row : ordered(objectName)) {
			if (result.size() >= size) {
				break;
			}
			Boolean inRange = row.Archived_At__c >= fromAt && row.Archived_At__c <= toAt;
			Boolean afterCursor =
				afterAt == null ||
				row.Archived_At__c < afterAt ||
				(row.Archived_At__c == afterAt &&
				row.Original_Id__c > afterId);
			if (inRange && afterCursor) {
				result.add(row);
			}
		}
		return result;
	}

	public override List<Archived_Record__b> scan(String objectName, Datetime afterAt, String afterId, Integer size) {
		List<Archived_Record__b> result = new List<Archived_Record__b>();
		for (Archived_Record__b row : ordered(objectName)) {
			if (result.size() >= size) {
				break;
			}
			if (
				afterAt == null ||
				row.Archived_At__c < afterAt ||
				(row.Archived_At__c == afterAt &&
				row.Original_Id__c > afterId)
			) {
				result.add(row);
			}
		}
		return result;
	}

	public override String nextObject(String afterName) {
		String best;
		for (Archived_Record__b row : rowsByKey.values()) {
			String name = row.Object_Name__c;
			if ((afterName == null || name > afterName) && (best == null || name < best)) {
				best = name;
			}
		}
		return best;
	}
}
