/**
 * The org's run state: last runs, summaries, watermarks and setup markers (ADR-NEXT settings as
 * custom metadata, decision 6). Not settings: nobody chooses them and they describe only this
 * org, so they are rows of `Nightly_Job__c` with `Kind__c` State, Name the key, and the value in
 * `Value__c` as a JSON literal, written synchronously in system mode by BarnCRM code (ADR-0021).
 *
 * Every state row is read in one query, once per transaction. A key that has no row yet is read
 * from the legacy custom setting field of the same name until the org carries its settings over,
 * so an upgraded org keeps its last runs and markers.
 */
@NamespaceAccessible
public without sharing class SettingsState {
	public static final String KIND_STATE = 'State';
	public static final String KIND_SEEN = 'Seen';
	private static final Integer NAME_LIMIT = 80;

	/**
	 * The Core run-state keys, by the field names they had on BarnCRM Settings. A key here is
	 * saved as state, never as a setting, whoever saves it (SettingsService.saveBookkeeping).
	 */
	@NamespaceAccessible
	public static final Set<String> CORE_KEYS = new Set<String>{
		'Error_Digest_Covered_Until__c',
		'Error_Digest_Last_Run__c',
		'Error_Digest_Last_Run_Summary__c',
		'Health_Check_Last_Result__c',
		'Health_Check_Last_Run__c',
		'Match_Keys_Filled__c',
		'Modules_Setup_Run__c',
		'Seasonal_Address_Last_Run__c',
		'Seasonal_Address_Last_Run_Summary__c',
		'Setup_Started_At__c',
		'Setup_Steps_Completed__c',
		'Setup_Steps_Skipped__c',
		'Shipped_Defaults_Applied__c'
	};

	private static Map<String, Nightly_Job__c> rowsByKey;

	/** True when the key is Core run state rather than a setting. */
	@NamespaceAccessible
	public static Boolean isStateKey(String key) {
		return String.isNotBlank(key) && lowerKeys().contains(key.trim().toLowerCase());
	}

	/** The value stored under the key (Boolean, Decimal, String...), or null. */
	@NamespaceAccessible
	public static Object get(String key) {
		Nightly_Job__c row = rows().get(normalized(key));
		if (row != null) {
			return SettingStore.parse(row.Value__c);
		}
		return legacy(key);
	}

	@NamespaceAccessible
	public static String text(String key) {
		Object value = get(key);
		return value == null ? null : String.valueOf(value);
	}

	@NamespaceAccessible
	public static Boolean flag(String key) {
		return get(key) == true;
	}

	@NamespaceAccessible
	public static Datetime moment(String key) {
		Object value = get(key);
		if (value == null || value instanceof Datetime) {
			return (Datetime) value;
		}
		try {
			return (Datetime) JSON.deserialize(JSON.serialize(String.valueOf(value)), Datetime.class);
		} catch (Exception unreadable) {
			return null;
		}
	}

	/** Saves the values, by key, in one write: a null value is kept as a blank row. */
	@NamespaceAccessible
	public static void put(Map<String, Object> values) {
		if (values == null || values.isEmpty()) {
			return;
		}
		List<Nightly_Job__c> changed = new List<Nightly_Job__c>();
		for (String key : values.keySet()) {
			Nightly_Job__c row = rows().get(normalized(key));
			if (row == null) {
				row = new Nightly_Job__c(Name = key.trim().left(NAME_LIMIT), Kind__c = KIND_STATE);
			}
			row.Value__c = SettingStore.toJson(values.get(key));
			rows().put(normalized(key), row);
			changed.add(row);
		}
		Database.upsert(changed, AccessLevel.SYSTEM_MODE);
	}

	/**
	 * Reads the rows of these keys under a lock that holds until this transaction ends, so two
	 * runs that each read a watermark and then move it cannot both act on the old one.
	 */
	@NamespaceAccessible
	public static void lock(Set<String> keys) {
		Set<String> names = new Set<String>();
		for (String key : keys) {
			names.add(key.trim());
		}
		for (Nightly_Job__c row : [
			SELECT Id, Name, Value__c
			FROM Nightly_Job__c
			WHERE Kind__c = :KIND_STATE AND Name IN :names
			WITH SYSTEM_MODE
			FOR UPDATE
		]) {
			rows().put(normalized(row.Name), row);
		}
	}

	/** Forgets the rows read, so the next read comes from the database. */
	@NamespaceAccessible
	public static void clearCache() {
		rowsByKey = null;
	}

	private static Map<String, Nightly_Job__c> rows() {
		if (rowsByKey == null) {
			rowsByKey = new Map<String, Nightly_Job__c>();
			for (Nightly_Job__c row : [
				SELECT Id, Name, Value__c
				FROM Nightly_Job__c
				WHERE Kind__c = :KIND_STATE
				WITH SYSTEM_MODE
				ORDER BY LastModifiedDate
				LIMIT 1000
			]) {
				rowsByKey.put(normalized(row.Name), row);
			}
		}
		return rowsByKey;
	}

	/** Until carry-over, a Core key with no row reads the legacy field of the same name. */
	private static Object legacy(String key) {
		if (!isStateKey(key) || SettingStore.isCarriedOver()) {
			return null;
		}
		BarnCRM_Settings__c stored = BarnCRM_Settings__c.getOrgDefaults();
		if (stored == null || stored.Id == null) {
			return null;
		}
		try {
			return stored.get(key.trim());
		} catch (Exception notAField) {
			return null;
		}
	}

	private static Set<String> lowerKeys;

	private static Set<String> lowerKeys() {
		if (lowerKeys == null) {
			lowerKeys = new Set<String>();
			for (String key : CORE_KEYS) {
				lowerKeys.add(key.toLowerCase());
			}
		}
		return lowerKeys;
	}

	private static String normalized(String key) {
		return key == null ? '' : key.trim().toLowerCase();
	}
}
