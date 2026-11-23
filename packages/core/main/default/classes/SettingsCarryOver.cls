/**
 * The one-time carry-over of an org's settings into custom metadata (ADR-0238 settings as custom
 * metadata, decision 9; canonical model R-STV1).
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
 * - copies each person's What's New seen version into their Seen row;
 * - does the same for every module with a `Setting_Module__mdt` record whose legacy custom
 *   setting the org still has and saved: each value with a Setting Definition row of that group
 *   joins the one deployment, and each field the record lists as state is copied into the state
 *   row `Prefix.Field`. Core names no module: the registry records say what to read.
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
		// A module's legacy settings are read only in an org that saved Core's (ModuleSettings
		// .legacyRecord), so Core's record also stands for theirs.
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
		Set<String> existing = stateRowNames();
		Map<String, Object> state = new Map<String, Object>();
		Datetime pausedUntil = null;
		if (hasLegacy) {
			changes.addAll(settingChanges(legacy, coreDefinitions(fields), CORE_SETTINGS_EXCLUDED, result));
			state.putAll(stateValues(legacy, SettingsState.CORE_KEYS, null, existing));
			pausedUntil = legacy.Automation_Paused_Until__c;
		}
		for (Setting_Module__mdt module : ModuleSettings.registry()) {
			SObject record = ModuleSettings.isStoreObject(module.Settings_Object__c)
				? ModuleSettings.legacyRecord(module.Settings_Object__c)
				: null;
			if (record == null) {
				continue;
			}
			Set<String> stateFields = ModuleSettings.stateFields(module);
			List<Setting_Definition__mdt> definitions = ModuleSettings.definitionsFor(module.Settings_Object__c)
				.values();
			changes.addAll(settingChanges(record, definitions, stateFields, result));
			state.putAll(stateValues(record, stateFields, module.Key_Prefix__c, existing));
		}
		List<Nightly_Job__c> seen = seenToCopy();
		result.stateCount = state.size();
		result.seenCount = seen.size();
		result.settingCount = changes.size();

		SettingStore.Change marker = new SettingStore.Change();
		marker.name = SettingStore.CARRIED_OVER;
		marker.settingName = SettingStore.CARRIED_OVER;
		marker.newText = 'true';
		marker.json = 'true';
		changes.add(marker);
		// Audited: each carried value is listed in Recent Changes, and the console's poll sees the
		// deployment end through those rows, as for any save.
		// The deployment goes first, with no record written before it in this transaction:
		// Salesforce refuses a deployment after any record change in the same transaction (mixed
		// DML), so the state rows, the seen rows and the pause are written by a queued job.
		Id deploymentId = SettingStore.save(changes, true);
		result.deploymentId = deploymentId == null ? null : String.valueOf(deploymentId);
		Boolean pauseRunning = pausedUntil != null && pausedUntil > Datetime.now();
		if (!state.isEmpty() || !seen.isEmpty() || pauseRunning) {
			System.enqueueJob(new CopyRunState(state, seen, pauseRunning ? pausedUntil : null));
		}
		return result;
	}

	/** Writes what the carry-over copies as records, in its own transaction after the deployment. */
	@TestVisible
	private without sharing class CopyRunState implements Queueable {
		private final Map<String, Object> state;
		private final List<Nightly_Job__c> seen;
		private final Datetime pausedUntil;

		CopyRunState(Map<String, Object> state, List<Nightly_Job__c> seen, Datetime pausedUntil) {
			this.state = state;
			this.seen = seen;
			this.pausedUntil = pausedUntil;
		}

		public void execute(QueueableContext context) {
			SettingsState.put(state);
			carryPause(pausedUntil);
			Database.insert(seen, AccessLevel.SYSTEM_MODE);
		}
	}

	/** Core's keys that are not carried as settings: the pause and the run state. */
	private static final Set<String> CORE_SETTINGS_EXCLUDED = coreExcluded();

	private static Set<String> coreExcluded() {
		Set<String> keys = new Set<String>{ PAUSE_KEY };
		for (String key : SettingsState.CORE_KEYS) {
			keys.add(key.toLowerCase());
		}
		return keys;
	}

	/** Core's shipped definitions whose key is a field of the legacy object. */
	private static List<Setting_Definition__mdt> coreDefinitions(Map<String, Schema.SObjectField> fields) {
		List<Setting_Definition__mdt> rows = new List<Setting_Definition__mdt>();
		for (Setting_Definition__mdt definition : SettingStore.definitions().values()) {
			Boolean core =
				definition.Settings_Object__c != null &&
				definition.Settings_Object__c.trim().toLowerCase().endsWith(CORE_OBJECT);
			if (
				core &&
				definition.Setting_Key__c != null &&
				fields.containsKey(definition.Setting_Key__c.trim().toLowerCase())
			) {
				rows.add(definition);
			}
		}
		return rows;
	}

	/**
	 * The legacy values that differ from their defaults, one change per definition whose key is a
	 * field of the record and not excluded (lower-case keys), audited as `Object.Field`.
	 */
	private static List<SettingStore.Change> settingChanges(
		SObject legacy,
		List<Setting_Definition__mdt> definitions,
		Set<String> excluded,
		Result result
	) {
		List<SettingStore.Change> changes = new List<SettingStore.Change>();
		Schema.SObjectType type = legacy.getSObjectType();
		String objectName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getLocalName();
		for (Setting_Definition__mdt definition : definitions) {
			String key = definition.Setting_Key__c == null ? '' : definition.Setting_Key__c.trim();
			Schema.SObjectField token = String.isBlank(key) || excluded.contains(key.toLowerCase())
				? null
				: NamespaceUtil.field(type, key);
			Object value = token == null ? null : legacy.get(token);
			if (isBlank(value) || SettingStore.has(definition.DeveloperName)) {
				continue;
			}
			if (sameValue(value, SettingStore.parse(definition.Default_Value__c))) {
				continue;
			}
			String json = SettingStore.toJson(value);
			if (json.length() > SettingStore.VALUE_LIMIT) {
				result.tooLong.add(key);
				continue;
			}
			SettingStore.Change change = new SettingStore.Change();
			change.name = definition.DeveloperName;
			change.settingName = objectName + '.' + token.getDescribe().getLocalName();
			change.newText = String.valueOf(value);
			change.json = json;
			changes.add(change);
		}
		return changes;
	}

	/** The names of the State rows the org already has, in lower case. */
	private static Set<String> stateRowNames() {
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
		return existing;
	}

	/**
	 * The run state to copy: each listed field with a legacy value and no State row yet, keyed by
	 * the field name (Core) or `Prefix.Field` (a module).
	 */
	private static Map<String, Object> stateValues(
		SObject legacy,
		Set<String> names,
		String prefix,
		Set<String> existing
	) {
		Map<String, Object> values = new Map<String, Object>();
		for (String name : names) {
			Schema.SObjectField token = NamespaceUtil.field(legacy.getSObjectType(), name);
			Object value = token == null ? null : legacy.get(token);
			String key = token == null ? name : token.getDescribe().getLocalName();
			key = prefix == null ? key : SettingsState.moduleKey(prefix, key);
			// An unchecked box reads the same with no row, so only a set value is copied.
			if (!isBlank(value) && value != false && !existing.contains(key.toLowerCase())) {
				values.put(key, value);
			}
		}
		return values;
	}

	/** A pause that has not ended moves to the Automation Control org default. */
	private static void carryPause(Datetime pausedUntil) {
		if (pausedUntil == null || pausedUntil <= Datetime.now()) {
			return;
		}
		AutomationSettingsWriter.lockPause();
		BarnCRM_Automation_Control__c control = BarnCRM_Automation_Control__c.getOrgDefaults();
		if (control == null || control.Paused_Until__c == null) {
			AutomationSettingsWriter.savePausedUntil(pausedUntil);
		}
	}

	/** Each person's dismissed What's New version, as the Seen row to write when they have none. */
	private static List<Nightly_Job__c> seenToCopy() {
		List<Whats_New_Seen__c> legacyRows = seenRows();
		List<Nightly_Job__c> rows = new List<Nightly_Job__c>();
		if (legacyRows.isEmpty()) {
			return rows;
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
		return rows;
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
