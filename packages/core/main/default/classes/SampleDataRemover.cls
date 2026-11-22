/**
 * Sample data removal past sharing (SR-01, plan D-219; ADR-0233 amendment of 2026-11-21).
 *
 * Any admin who holds Manage BarnCRM Settings removes the whole sample set, not only the records
 * they own or loaded: a module admin set gives Delete without Modify All on most objects, and an
 * object whose default access is Read/Write or Private gives no delete on someone else's record,
 * so a removal in user mode left another admin's sample programs, cohorts and sessions behind.
 * This class finds and deletes in system mode, without sharing, and is still gated twice: every
 * method refuses a person without Manage BarnCRM Settings, and a search must name the
 * `Sample_Data__c` tracking the module set it was loaded with, so only records tracked as sample
 * data are found. Deletes keep the platform's own guards (a Restrict lookup, a validation rule,
 * a trigger), and a refused delete carries the platform's reason back to the caller.
 *
 * Callers: `SampleDataFile.RemoveStages` (every JSON module set), Core's people removal
 * (`SampleDataRemoveStages`), and the Giving and Volunteers removals. Listed in
 * docs/architecture/without-sharing-register.md.
 */
@NamespaceAccessible
public without sharing class SampleDataRemover {
	private static final String TRACKING_FIELD = 'SAMPLE_DATA__C';

	/** How many rows match a module's sample condition; 0 when the object is not installed. */
	@NamespaceAccessible
	public static Integer count(String objectName, String condition) {
		if (!allowed(objectName, condition)) {
			return 0;
		}
		// Access mode: system, without sharing, gated above (SR-01).
		return Database.countQueryWithBinds(
			'SELECT COUNT() FROM ' + objectName + ' WHERE ' + condition,
			new Map<String, Object>(),
			AccessLevel.SYSTEM_MODE
		);
	}

	/**
	 * The next chunk of a module's sample rows, leaving out the ones already kept. A clause with a
	 * semi-join is already a plain AND list (SOQL allows it only at the top level); any other is
	 * wrapped so an OR in it stays apart from the kept rows.
	 */
	@NamespaceAccessible
	public static List<Id> ids(String objectName, String condition, Set<Id> leaveOut, Integer chunk) {
		List<Id> found = new List<Id>();
		if (!allowed(objectName, condition)) {
			return found;
		}
		String clause = condition.toUpperCase().contains('SELECT ') ? condition : '(' + condition + ')';
		for (
			SObject row : Database.queryWithBinds(
				'SELECT Id FROM ' + objectName + ' WHERE ' + clause + ' AND Id NOT IN :leaveOut LIMIT :chunk',
				new Map<String, Object>{ 'leaveOut' => leaveOut ?? new Set<Id>(), 'chunk' => chunk },
				AccessLevel.SYSTEM_MODE
			)
		) {
			found.add(row.Id);
		}
		return found;
	}

	/**
	 * Deletes sample rows the caller found through a sample condition. With `allOrNone` false a
	 * refused row stays and its result says why; with true the first refusal throws, as the
	 * Giving removal expects.
	 */
	@NamespaceAccessible
	public static List<Database.DeleteResult> remove(List<Id> recordIds, Boolean allOrNone) {
		requirePermission();
		if (recordIds == null || recordIds.isEmpty()) {
			return new List<Database.DeleteResult>();
		}
		return Database.delete(recordIds, allOrNone, AccessLevel.SYSTEM_MODE);
	}

	/** The Name of each record, for the Warning that lists what removal kept. */
	@NamespaceAccessible
	public static Map<Id, String> names(String objectName, Set<Id> recordIds) {
		requirePermission();
		Map<Id, String> byId = new Map<Id, String>();
		for (
			SObject row : Database.queryWithBinds(
				'SELECT Id, Name FROM ' + objectName + ' WHERE Id IN :ids ORDER BY Name LIMIT 50',
				new Map<String, Object>{ 'ids' => recordIds },
				AccessLevel.SYSTEM_MODE
			)
		) {
			byId.put(row.Id, (String) row.get('Name'));
		}
		return byId;
	}

	/** Refuses anyone without Manage BarnCRM Settings, the permission removal needs. */
	private static void requirePermission() {
		if (!BarnCRMPermissions.canManageSettings()) {
			throw new SampleDataException(BarnHelp.text('Core', 'Core_SampleData_NoPermission'));
		}
	}

	/** Permission, an installed object, and a condition on the sample tracking. */
	private static Boolean allowed(String objectName, String condition) {
		requirePermission();
		if (String.isBlank(condition) || !condition.toUpperCase().contains(TRACKING_FIELD)) {
			throw new SampleDataException(BarnHelp.text('Core', 'Core_SampleData_NotTracked'));
		}
		return NamespaceUtil.describe(objectName) != null;
	}
}
