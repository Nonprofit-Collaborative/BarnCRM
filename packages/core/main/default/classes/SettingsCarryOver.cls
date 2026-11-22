/**
 * The one-time carry-over of an org's settings into custom metadata (ADR-NEXT settings as custom
 * metadata, decision 9; canonical model R-SV1).
 *
 * Until it runs, a Core setting with no Setting Value record reads the legacy BarnCRM Settings
 * custom setting, so an upgraded org keeps working. The Carry Over action on the BarnCRM Settings
 * tab then, in one go:
 *
 * - deploys every legacy value that differs from its shipped default as a Setting Value record,
 *   with the `Settings_Carried_Over` marker, in one deployment (the marker lands with the values,
 *   so the legacy read stops exactly when they arrive);
 * - copies each run-state key that has no State row yet into one;
 * - copies a pause that has not ended onto the BarnCRM Automation Control org default;
 * - copies each person's What's New seen version into their Seen row.
 *
 * The legacy records are left in place; phase 2 removes the objects.
 *
 * Without sharing: the legacy records are protected custom settings and the rows written are
 * package-owned (ADR-0021). `SettingsController` checks Manage BarnCRM Settings before calling.
 */
public without sharing class SettingsCarryOver {
	private static final String CORE_OBJECT = 'barncrm_settings__c';
	private static final String PAUSE_KEY = 'automation_paused_until__c';
	private static final String SEEN_PREFIX = 'WhatsNew:';

	/** What the action did, for the console. */
	public class Result {
		@AuraEnabled
		public String deploymentId;
		@AuraEnabled
		public Integer settingCount = 0;
		@AuraEnabled
		public Integer stateCount = 0;
		@AuraEnabled
		public Integer seenCount = 0;
		/** Keys whose value is longer than a Setting Value holds: they read their default. */
		@AuraEnabled
		public List<String> tooLong = new List<String>();
	}

	/** True when the org has legacy settings and has not carried them over yet. */
	public static Boolean isNeeded() {
		if (SettingStore.isCarriedOver()) {
			return false;
		}
		BarnCRM_Settings__c legacy = BarnCRM_Settings__c.getOrgDefaults();
		return (legacy != null && legacy.Id != null) || !seenRows().isEmpty();
	}

	/** Carries the org's settings over; a second run, once the marker is deployed, does nothing. */
	public static Result run() {
		Result result = new Result();
		if (SettingStore.isCarriedOver()) {
			return result;
		}
		BarnCRM_Settings__c legacy = BarnCRM_Settings__c.getOrgDefaults();
		Boolean hasLegacy = legacy != null && legacy.Id != null;
		Map<String, Schema.SObjectField> fields = Schema.SObjectType.BarnCRM_Settings__c.fields.getMap();

		List<SettingStore.Change> changes = new List<SettingStore.Change>();
		if (hasLegacy) {
			changes.addAll(settingChanges(legacy, fields, result));
			result.stateCount = carryState(legacy, fields);
			carryPause(legacy);
		}
		result.seenCount = carrySeen();
		result.settingCount = changes.size();

		SettingStore.Change marker = new SettingStore.Change();
		marker.name = SettingStore.CARRIED_OVER;
		marker.settingName = SettingStore.CARRIED_OVER;
		marker.newText = 'true';
		marker.json = 'true';
		changes.add(marker);
		// Audited: each carried value is listed in Recent Changes, and the console's poll sees the
		// deployment end through those rows, as for any save.
		Id deploymentId = SettingStore.save(changes, true);
		result.deploymentId = deploymentId == null ? null : String.valueOf(deploymentId);
		return result;
	}

	/** The legacy values that differ from their defaults, one change per shipped definition. */
	private static List<SettingStore.Change> settingChanges(
		BarnCRM_Settings__c legacy,
		Map<String, Schema.SObjectField> fields,
		Result result
	) {
		List<SettingStore.Change> changes = new List<SettingStore.Change>();
		for (Setting_Definition__mdt definition : SettingStore.definitions().values()) {
			String key = definition.Setting_Key__c == null ? '' : definition.Setting_Key__c.trim().toLowerCase();
			Boolean core = definition.Settings_Object__c != null &&
				definition.Settings_Object__c.trim().toLowerCase().endsWith(CORE_OBJECT);
			if (!core || !fields.containsKey(key) || key == PAUSE_KEY || SettingsState.isStateKey(key)) {
				continue;
			}
			Object value = legacy.get(fields.get(key));
			if (isBlank(value) || SettingStore.has(definition.DeveloperName)) {
				continue;
			}
			if (sameValue(value, SettingStore.parse(SettingStore.defaultOf(definition.DeveloperName)))) {
				continue;
			}
			String json = SettingStore.toJson(value);
			if (json.length() > SettingStore.VALUE_LIMIT) {
				result.tooLong.add(definition.Setting_Key__c.trim());
				continue;
			}
			SettingStore.Change change = new SettingStore.Change();
			change.name = definition.DeveloperName;
			change.settingName = 'BarnCRM_Settings__c.' + fields.get(key).getDescribe().getLocalName();
			change.newText = String.valueOf(value);
			change.json = json;
			changes.add(change);
		}
		return changes;
	}

	/** Copies each run-state key with a legacy value and no State row; returns how many. */
	private static Integer carryState(BarnCRM_Settings__c legacy, Map<String, Schema.SObjectField> fields) {
		Set<String> existing = new Set<String>();
		for (Nightly_Job__c row : [
			SELECT Name
			FROM Nightly_Job__c
			WHERE Kind__c = :SettingsState.KIND_STATE
			WITH SYSTEM_MODE
			LIMIT 1000
		]) {
			existing.add(row.Name.toLowerCase());
		}
		Map<String, Object> values = new Map<String, Object>();
		for (String key : SettingsState.CORE_KEYS) {
			Schema.SObjectField token = fields.get(key.toLowerCase());
			Object value = token == null ? null : legacy.get(token);
			// An unchecked box reads the same with no row, so only a set value is copied.
			if (!isBlank(value) && value != false && !existing.contains(key.toLowerCase())) {
				values.put(key, value);
			}
		}
		SettingsState.put(values);
		return values.size();
	}

	/** A pause that has not ended moves to the Automation Control org default. */
	private static void carryPause(BarnCRM_Settings__c legacy) {
		Datetime pausedUntil = legacy.Automation_Paused_Until__c;
		if (pausedUntil == null || pausedUntil <= Datetime.now()) {
			return;
		}
		AutomationSettingsWriter.lockPause();
		BarnCRM_Automation_Control__c control = BarnCRM_Automation_Control__c.getOrgDefaults();
		if (control == null || control.Paused_Until__c == null) {
			AutomationSettingsWriter.savePausedUntil(pausedUntil);
		}
	}

	/** Each person's dismissed What's New version, as their Seen row when they have none. */
	private static Integer carrySeen() {
		List<Whats_New_Seen__c> legacyRows = seenRows();
		if (legacyRows.isEmpty()) {
			return 0;
		}
		Set<String> existing = new Set<String>();
		for (Nightly_Job__c row : [
			SELECT Name
			FROM Nightly_Job__c
			WHERE Kind__c = :SettingsState.KIND_SEEN
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			existing.add(row.Name);
		}
		List<Nightly_Job__c> rows = new List<Nightly_Job__c>();
		for (Whats_New_Seen__c seen : legacyRows) {
			String name = SEEN_PREFIX + seen.SetupOwnerId;
			if (!existing.contains(name)) {
				rows.add(
					new Nightly_Job__c(
						Name = name,
						Kind__c = SettingsState.KIND_SEEN,
						Value__c = SettingStore.toJson(seen.Last_Seen_Version__c)
					)
				);
			}
		}
		Database.insert(rows, AccessLevel.SYSTEM_MODE);
		return rows.size();
	}

	/** The per-user legacy seen records (the org default holds nobody's). */
	private static List<Whats_New_Seen__c> seenRows() {
		String userPrefix = User.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix();
		List<Whats_New_Seen__c> rows = new List<Whats_New_Seen__c>();
		for (Whats_New_Seen__c seen : [
			SELECT SetupOwnerId, Last_Seen_Version__c
			FROM Whats_New_Seen__c
			WHERE Last_Seen_Version__c != NULL
			WITH SYSTEM_MODE
			LIMIT 10000
		]) {
			if (String.valueOf(seen.SetupOwnerId).startsWith(userPrefix)) {
				rows.add(seen);
			}
		}
		return rows;
	}

	private static Boolean isBlank(Object value) {
		return value == null || (value instanceof String && String.isBlank((String) value));
	}

	/** Equal as values: 7 and 7.00 are the same number, a text compares exactly. */
	@TestVisible
	private static Boolean sameValue(Object stored, Object shipped) {
		if (shipped == null) {
			return stored == false;
		}
		Decimal storedNumber = asNumber(stored);
		Decimal shippedNumber = asNumber(shipped);
		if (storedNumber != null && shippedNumber != null) {
			return storedNumber == shippedNumber;
		}
		return String.valueOf(stored).equals(String.valueOf(shipped));
	}

	private static Decimal asNumber(Object value) {
		if (value instanceof Decimal || value instanceof Long) {
			return Decimal.valueOf(String.valueOf(value));
		}
		return null;
	}
}
