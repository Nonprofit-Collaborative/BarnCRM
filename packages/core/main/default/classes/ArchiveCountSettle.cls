/**
 * Keeps `Archived_Record_Count__c` true when an archive, restore or erasure chain dies (canonical
 * model R-ARC5, ADR-0240 amendment of 2026-11-23, plan D-223). Big objects cannot COUNT, so the
 * count is a running total, and the rows an immediate call writes or removes are counted in a
 * later link. A link that may do DML therefore writes the rows the next immediate call will touch
 * into the job's definition (`Operation_JSON__c`, key `pending`) before that call, in the same
 * write as the rest of the job; whoever comes next settles them: the next DML link, the finalizer
 * of a link that died, or the nightly sweep for a chain that stopped with neither.
 *
 * Settling reads the rows back by key (the truth), changes the count by what it finds and clears
 * the list, under a lock on the job row, so settling twice changes nothing the second time.
 *
 * A pending change is `{ "sign": 1 or -1, "object", "at" (epoch ms), "ids" }`: +1 counts the rows
 * found (written), -1 subtracts the rows not found (removed). With no `ids`, +1 counts every row
 * of the object at that time archived by `rule` (a Copy's rows, whose Ids its Copy chooses).
 */
public with sharing class ArchiveCountSettle {
	public static final String PENDING = 'pending';
	/** A Committing job not written for this long has stopped without its finalizer. */
	@TestVisible
	private static Integer staleHours = 24;
	/** Jobs one sweep settles at most, for the query limits. */
	private static final Integer JOBS_PER_SWEEP = 10;
	private static final String CONTEXT = 'ArchiveCountSettle';

	/** What one settle found. */
	public class Settled {
		/** Rows written and found. */
		public Integer added = 0;
		/** Rows removed and gone. */
		public Integer removed = 0;
		/** Original Ids of rows meant to be removed but still there. */
		public List<String> kept = new List<String>();
	}

	/** The pending change for rows written at one time: Ids known, or (null) every row of the rule. */
	public static Map<String, Object> written(String objectName, Datetime at, Set<String> ids, Id ruleId) {
		Map<String, Object> change = new Map<String, Object>{
			'sign' => 1,
			'object' => objectName,
			'at' => at.getTime(),
			'rule' => ruleId
		};
		if (ids != null) {
			change.put('ids', new List<String>(ids));
		}
		return change;
	}

	/** The pending changes for rows about to be removed, one per object and time. */
	public static List<Object> removing(List<ArchiveStore.Key> keys) {
		Map<String, Map<String, Object>> byGroup = new Map<String, Map<String, Object>>();
		for (ArchiveStore.Key key : keys) {
			String slot = key.objectName + '|' + key.archivedAt.getTime();
			if (!byGroup.containsKey(slot)) {
				byGroup.put(
					slot,
					new Map<String, Object>{
						'sign' => -1,
						'object' => key.objectName,
						'at' => key.archivedAt.getTime(),
						'ids' => new List<String>()
					}
				);
			}
			((List<String>) byGroup.get(slot).get('ids')).add(key.originalId);
		}
		List<Object> result = new List<Object>();
		for (Map<String, Object> change : byGroup.values()) {
			result.add(change);
		}
		return result;
	}

	/** The job definition with these pending changes in place of any it had. */
	public static String withPending(String operationJson, List<Object> changes) {
		Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(operationJson);
		definition.remove(PENDING);
		if (changes != null && !changes.isEmpty()) {
			definition.put(PENDING, changes);
		}
		return JSON.serialize(definition);
	}

	/**
	 * Settles the job's pending changes: reads the rows back, changes the count, clears the list.
	 * Locks the job row first, so a second settle waits and then finds nothing to do. Big object
	 * reads, then DML: never call it before an immediate call in the same transaction.
	 */
	public static Settled settle(Id jobId) {
		Settled result = new Settled();
		List<Import_Batch__c> jobs = [
			SELECT Id, Operation_JSON__c
			FROM Import_Batch__c
			WHERE Id = :jobId
			WITH SYSTEM_MODE
			LIMIT 1
			FOR UPDATE
		];
		List<Object> changes = jobs.isEmpty() ? null : pendingOf(jobs[0].Operation_JSON__c);
		if (changes == null) {
			return result;
		}
		for (Object raw : changes) {
			read((Map<String, Object>) raw, result);
		}
		// The count and the cleared list together or not at all, even for a caller that catches.
		Savepoint before = Database.setSavepoint();
		try {
			BigObjectArchiveJob.addToCount(result.added - result.removed);
			Database.update(
				new Import_Batch__c(Id = jobId, Operation_JSON__c = withPending(jobs[0].Operation_JSON__c, null)),
				AccessLevel.SYSTEM_MODE
			);
		} catch (Exception failed) {
			Database.rollback(before);
			throw failed;
		}
		return result;
	}

	private static void read(Map<String, Object> change, Settled result) {
		String objectName = (String) change.get('object');
		Datetime at = Datetime.newInstance(Long.valueOf(String.valueOf(change.get('at'))));
		Object ids = change.get('ids');
		if (ids == null) {
			result.added += ArchiveStore.get().presentOfRule(objectName, at, (String) change.get('rule')).size();
			return;
		}
		Set<String> wanted = new Set<String>();
		for (Object one : (List<Object>) ids) {
			wanted.add((String) one);
		}
		Set<String> present = ArchiveStore.get().present(objectName, at, wanted);
		if (Integer.valueOf(change.get('sign')) > 0) {
			result.added += present.size();
		} else {
			result.removed += wanted.size() - present.size();
			result.kept.addAll(present);
		}
	}

	private static List<Object> pendingOf(String operationJson) {
		try {
			Object changes = ((Map<String, Object>) JSON.deserializeUntyped(operationJson)).get(PENDING);
			return changes instanceof List<Object> && !((List<Object>) changes).isEmpty()
				? (List<Object>) changes
				: null;
		} catch (Exception notJson) {
			return null;
		}
	}

	/**
	 * The nightly sweep (run by the Archive Rules step): settles the Archive jobs of the last 30
	 * days left with pending changes, Failed ones and Committing ones not written for a day
	 * (their chain stopped with no finalizer), and marks those Failed. Never throws.
	 */
	public static Integer sweep() {
		Integer settled = 0;
		Datetime stale = Datetime.now().addHours(-staleHours);
		try {
			for (Import_Batch__c job : [
				SELECT Id, Status__c, LastModifiedDate, Operation_JSON__c
				FROM Import_Batch__c
				WHERE
					Operation__c = :BigObjectArchiveJob.OPERATION_ARCHIVE
					AND Status__c != :ImportBatchService.STATUS_COMPLETE
					AND LastModifiedDate = LAST_N_DAYS:30
				WITH SYSTEM_MODE
				ORDER BY LastModifiedDate DESC
				LIMIT 200
			]) {
				Boolean stuck =
					ImportBatchService.STATUS_COMMITTING.equals(job.Status__c) && job.LastModifiedDate < stale;
				Boolean running = ImportBatchService.STATUS_COMMITTING.equals(job.Status__c) && !stuck;
				if (running || (!stuck && pendingOf(job.Operation_JSON__c) == null)) {
					continue;
				}
				if (settled >= JOBS_PER_SWEEP) {
					break;
				}
				settled++;
				try {
					settle(job.Id);
					if (stuck) {
						BigObjectArchiveJob.fail(job.Id, BarnHelp.text('Core', 'Core_ArchiveRules_LogSwept'), null);
					}
				} catch (Exception notSettled) {
					ErrorLogger.log(notSettled, CONTEXT, job.Id);
				}
			}
		} catch (Exception failed) {
			ErrorLogger.log(failed, CONTEXT);
		}
		return settled;
	}
}
