/**
 * How a module reads and saves its settings in the settings store (ADR-NEXT settings as custom
 * metadata, phase 2).
 *
 * A module declares its settings by shipping, in its own package, one `Setting_Module__mdt`
 * record (its settings group, its state key prefix, its legacy state fields) and one
 * `Setting_Definition__mdt` row per setting with its default in `Default_Value__c`. It reads a
 * setting by the row's DeveloperName with a typed getter here, which answers the org's Setting
 * Value when it has one, else (before carry-over) the legacy custom setting's value, else the
 * default. Core names no module: everything comes from the module's own records.
 *
 * Saves go through `SettingsService` (one validated, audited deployment, followed with
 * `SettingsController.getSaveOutcome`), so the console and a module's own page save the same
 * way. Run state is not a setting: it goes to `SettingsState` under `SettingsState.moduleKey`.
 */
@NamespaceAccessible
public with sharing class ModuleSettings {
	@TestVisible
	private static List<Setting_Module__mdt> stubbedModules;

	private static Map<String, Setting_Module__mdt> modulesByObject;
	private static Map<String, Map<String, Setting_Definition__mdt>> definitionsByObject;
	private static Map<String, Setting_Definition__mdt> definitionsByName;
	private static Map<String, SObject> legacyByObject = new Map<String, SObject>();

	/** Every registered module, by its settings group in lower case. */
	@NamespaceAccessible
	public static Map<String, Setting_Module__mdt> modules() {
		if (modulesByObject == null) {
			modulesByObject = new Map<String, Setting_Module__mdt>();
			List<Setting_Module__mdt> rows = stubbedModules != null
				? stubbedModules
				: Setting_Module__mdt.getAll().values();
			for (Setting_Module__mdt row : rows) {
				// Core's own settings have their own path (SettingsService), never a module's.
				Boolean core = SettingsService.CORE_SETTINGS_OBJECT.equalsIgnoreCase(row.Settings_Object__c?.trim());
				if (String.isNotBlank(row.Settings_Object__c) && !core) {
					modulesByObject.put(row.Settings_Object__c.trim().toLowerCase(), row);
				}
			}
		}
		return modulesByObject;
	}

	/**
	 * Every registered module with its whole `State_Fields__c` (`getAll` gives a long text only
	 * its first 255 characters), for the one-time carry-over.
	 */
	@NamespaceAccessible
	public static List<Setting_Module__mdt> registry() {
		if (stubbedModules != null) {
			return stubbedModules;
		}
		return [
			SELECT DeveloperName, Settings_Object__c, Key_Prefix__c, State_Fields__c
			FROM Setting_Module__mdt
			WITH SYSTEM_MODE
			ORDER BY DeveloperName
			LIMIT 200
		];
	}

	/** The state field names a registry record lists, trimmed and in lower case. */
	@NamespaceAccessible
	public static Set<String> stateFields(Setting_Module__mdt module) {
		Set<String> names = new Set<String>();
		for (String name : (module.State_Fields__c == null ? '' : module.State_Fields__c).split(',')) {
			if (String.isNotBlank(name)) {
				names.add(name.trim().toLowerCase());
			}
		}
		return names;
	}

	/** True when the settings group's settings live in the store (its module ships a registry record). */
	@NamespaceAccessible
	public static Boolean isStoreObject(String settingsObject) {
		return String.isNotBlank(settingsObject) && modules().containsKey(settingsObject.trim().toLowerCase());
	}

	/** The module whose state keys start with the prefix, or null. */
	@NamespaceAccessible
	public static Setting_Module__mdt moduleByPrefix(String prefix) {
		for (Setting_Module__mdt row : modules().values()) {
			if (String.isNotBlank(prefix) && prefix.trim().equalsIgnoreCase(row.Key_Prefix__c)) {
				return row;
			}
		}
		return null;
	}

	/** A setting's definition by DeveloperName, or null (a test's stand-in rows when it set them). */
	@NamespaceAccessible
	public static Setting_Definition__mdt definition(String name) {
		index();
		return String.isBlank(name) ? null : definitionsByName.get(name.trim().toLowerCase());
	}

	/** The definition a settings group gives a key (the legacy field name), or null. */
	@NamespaceAccessible
	public static Setting_Definition__mdt definitionFor(String settingsObject, String key) {
		index();
		Map<String, Setting_Definition__mdt> rows = String.isBlank(settingsObject)
			? null
			: definitionsByObject.get(settingsObject.trim().toLowerCase());
		return rows == null || String.isBlank(key) ? null : rows.get(key.trim().toLowerCase());
	}

	/** Every definition of a settings group, by key in lower case. */
	@NamespaceAccessible
	public static Map<String, Setting_Definition__mdt> definitionsFor(String settingsObject) {
		index();
		Map<String, Setting_Definition__mdt> rows = String.isBlank(settingsObject)
			? null
			: definitionsByObject.get(settingsObject.trim().toLowerCase());
		return rows == null ? new Map<String, Setting_Definition__mdt>() : rows;
	}

	private static void index() {
		if (definitionsByName != null) {
			return;
		}
		definitionsByName = new Map<String, Setting_Definition__mdt>();
		definitionsByObject = new Map<String, Map<String, Setting_Definition__mdt>>();
		for (Setting_Definition__mdt row : SettingDefinitionSelector.getAllShortFields()) {
			definitionsByName.put(row.DeveloperName.toLowerCase(), row);
			if (String.isBlank(row.Settings_Object__c) || String.isBlank(row.Setting_Key__c)) {
				continue;
			}
			String groupName = row.Settings_Object__c.trim().toLowerCase();
			if (!definitionsByObject.containsKey(groupName)) {
				definitionsByObject.put(groupName, new Map<String, Setting_Definition__mdt>());
			}
			definitionsByObject.get(groupName).put(row.Setting_Key__c.trim().toLowerCase(), row);
		}
	}

	// Reads. None throws: a setting that cannot be read reads as its default.

	/** The effective value: the org's, else the legacy value before carry-over, else the default. */
	@NamespaceAccessible
	public static Object value(String name) {
		Object stored = stored(name);
		return stored != null ? stored : defaultValue(name);
	}

	/**
	 * What the org saved: its Setting Value when that is set and parses, else, before carry-over,
	 * the legacy custom setting's value; null when neither.
	 */
	@NamespaceAccessible
	public static Object stored(String name) {
		Setting_Definition__mdt row = definition(name);
		String storeName = row == null ? name : row.DeveloperName;
		if (String.isBlank(storeName)) {
			return null;
		}
		Object saved = SettingStore.parse(SettingStore.saved(storeName));
		if (saved != null || row == null || SettingStore.has(storeName)) {
			return saved;
		}
		return legacyValue(row.Settings_Object__c, row.Setting_Key__c);
	}

	/** The definition's default, parsed, or null. */
	@NamespaceAccessible
	public static Object defaultValue(String name) {
		Setting_Definition__mdt row = definition(name);
		return row == null ? null : SettingStore.parse(row.Default_Value__c);
	}

	@NamespaceAccessible
	public static Boolean flag(String name) {
		Object value = value(name);
		return value instanceof Boolean ? (Boolean) value : 'true'.equalsIgnoreCase(String.valueOf(value));
	}

	/** A number, or the default when the saved one is not a number or is outside the row's range. */
	@NamespaceAccessible
	public static Decimal number(String name) {
		Decimal value = SettingsService.toNumber(stored(name));
		Setting_Definition__mdt row = definition(name);
		Boolean outside =
			value != null &&
			row != null &&
			((row.Min_Value__c != null && value < row.Min_Value__c) ||
			(row.Max_Value__c != null &&
			value > row.Max_Value__c));
		return value == null || outside ? SettingsService.toNumber(defaultValue(name)) : value;
	}

	@NamespaceAccessible
	public static Integer integerValue(String name) {
		Decimal value = number(name);
		return value == null ? null : value.intValue();
	}

	/** Text, trimmed, or null when blank. */
	@NamespaceAccessible
	public static String text(String name) {
		Object value = value(name);
		String text = value == null ? null : SettingsService.asText(value).trim();
		return String.isBlank(text) ? null : text;
	}

	/** A date held as `yyyy-MM-dd` (or the date part of a date and time), or null. */
	@NamespaceAccessible
	public static Date dateValue(String name) {
		Object value = value(name);
		if (value == null || value instanceof Date) {
			return (Date) value;
		}
		try {
			return Date.valueOf(String.valueOf(value).trim().left(10));
		} catch (Exception unreadable) {
			return null;
		}
	}

	/** A date and time held as ISO 8601 text, or null. */
	@NamespaceAccessible
	public static Datetime datetimeValue(String name) {
		Object value = value(name);
		if (value == null || value instanceof Datetime) {
			return (Datetime) value;
		}
		try {
			return (Datetime) JSON.deserialize(JSON.serialize(String.valueOf(value).trim()), Datetime.class);
		} catch (Exception unreadable) {
			return null;
		}
	}

	// Saves.

	/**
	 * Saves settings by DeveloperName, validated and audited, in one deployment; returns its Id
	 * for `SettingsController.getSaveOutcome` (null in a test). Only console rows (not Hidden).
	 */
	@NamespaceAccessible
	public static Id save(Map<String, Object> valuesByName) {
		return send(valuesByName, true);
	}

	/** The same for values the module writes itself (Hidden rows included). */
	@NamespaceAccessible
	public static Id saveSystem(Map<String, Object> valuesByName) {
		return send(valuesByName, false);
	}

	private static Id send(Map<String, Object> valuesByName, Boolean consoleOnly) {
		Map<String, Map<String, Object>> byGroup = new Map<String, Map<String, Object>>();
		for (String name : valuesByName.keySet()) {
			Setting_Definition__mdt row = definition(name);
			if (row == null || !isStoreObject(row.Settings_Object__c)) {
				throw new SettingsService.SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
			}
			String groupName = row.Settings_Object__c.trim();
			if (!byGroup.containsKey(groupName)) {
				byGroup.put(groupName, new Map<String, Object>());
			}
			byGroup.get(groupName).put(row.Setting_Key__c.trim(), valuesByName.get(name));
		}
		SettingsService.collectSaves();
		try {
			for (String groupName : byGroup.keySet()) {
				if (consoleOnly) {
					SettingsService.saveValues(groupName, byGroup.get(groupName));
				} else {
					SettingsService.saveSystemValues(groupName, byGroup.get(groupName));
				}
			}
			return SettingsService.sendCollected();
		} finally {
			SettingsService.stopCollecting();
		}
	}

	/** Puts a value in the store for a test, as if it were deployed. Does nothing outside a test. */
	@NamespaceAccessible
	public static void setForTest(String name, Object value) {
		Setting_Definition__mdt row = definition(name);
		SettingStore.setForTest(row == null ? name : row.DeveloperName, value);
	}

	// The legacy custom setting, read until carry-over.

	/**
	 * The value a field of a module's legacy custom setting holds, or null: after carry-over,
	 * when the group is not registered or the org has no such object or field, when the org never
	 * saved the record, or when Core's own legacy settings were never saved either (a fresh org
	 * has nothing to carry, so it spends no query here).
	 */
	@NamespaceAccessible
	public static Object legacyValue(String settingsObject, String field) {
		if (!isStoreObject(settingsObject) || String.isBlank(field) || SettingStore.isCarriedOver()) {
			return null;
		}
		SObject record = legacyRecord(settingsObject);
		if (record == null) {
			return null;
		}
		Schema.SObjectField token = NamespaceUtil.field(record.getSObjectType(), field.trim());
		Object value = token == null ? null : record.get(token);
		return value instanceof String && String.isBlank((String) value) ? null : value;
	}

	/** The org-level record of a registered module's legacy custom setting, or null. */
	@NamespaceAccessible
	public static SObject legacyRecord(String settingsObject) {
		String groupName = settingsObject.trim().toLowerCase();
		if (!legacyByObject.containsKey(groupName)) {
			legacyByObject.put(groupName, readLegacy(settingsObject.trim()));
		}
		return legacyByObject.get(groupName);
	}

	private static SObject readLegacy(String settingsObject) {
		BarnCRM_Settings__c core = BarnCRM_Settings__c.getOrgDefaults();
		if (core == null || core.Id == null) {
			return null;
		}
		Schema.SObjectType type = NamespaceUtil.objectType(settingsObject);
		if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isCustomSetting()) {
			return null;
		}
		return SettingsRecordSelector.getOrgDefault(type);
	}

	/** Forgets what was read, so the next read comes from the platform. */
	@NamespaceAccessible
	public static void clearCache() {
		modulesByObject = null;
		definitionsByName = null;
		definitionsByObject = null;
		legacyByObject.clear();
	}
}
