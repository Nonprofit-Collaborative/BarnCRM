/**
 * Reads and writes the org's settings.
 *
 * Core's settings live in the settings store (`SettingStore`, ADR-0238 settings as custom
 * metadata): the default on each Setting Definition row, a changed value in a Setting Value
 * record. They keep their `BarnCRM_Settings__c` field names as keys, and `getSettings()` returns
 * a `BarnCRM_Settings__c` built in memory from the store, so readers are unchanged. Until the org
 * carries its settings over, a value it saved in the legacy custom setting is read ahead of the
 * default. Core run state is not a setting: its keys are rows of `SettingsState`.
 *
 * Every module registered in `Setting_Module__mdt` keeps its settings in the same store
 * (`ModuleSettings`, phase 2), reading its legacy custom setting only until carry-over. Every
 * write is validated against the shipped rows and is audited as a Setting Change record
 * (canonical model Section 12, R-N3; R-STV2), once the save is deployed.
 */
@NamespaceAccessible
public with sharing class SettingsService {
	/**
	 * Core's own settings object, used when a caller or a row does not name one. Read from
	 * describe rather than written as a literal, so it stays correct once a namespace is
	 * registered.
	 */
	@NamespaceAccessible
	public static final String CORE_SETTINGS_OBJECT = BarnCRM_Settings__c.SObjectType.getDescribe(
			SObjectDescribeOptions.DEFERRED
		)
		.getLocalName();

	private static final String SETUP_OWNER = 'setupownerid';
	private static final String PICKLIST = 'Picklist';
	private static final String NUMBER_TYPE = 'Number';
	private static final String TEXT_TYPE = 'Text';
	public static final String RECORD = 'Record';
	public static final String RECORD_TYPE = 'RecordType';
	public static final String RECORD_TYPE_LIST = 'RecordTypeList';
	public static final String FIELD_LIST = 'FieldList';
	public static final String PICKLIST_FROM_FIELD = 'PicklistFromField';

	private static BarnCRM_Settings__c cachedSettings;
	private static BarnCRM_Settings__c cachedLegacy;
	private static Map<String, Setting_Definition__mdt> cachedCoreDefinitions;
	/** The deployment the last Core save in this transaction sent, for the console to follow. */
	private static Id lastDeployment;
	private static Map<String, SObject> cachedOrgDefaults = new Map<String, SObject>();
	private static Map<String, Map<String, Schema.SObjectField>> cachedFields = new Map<String, Map<String, Schema.SObjectField>>();

	/** Raised when a setting does not exist, is not editable here, or the value cannot be read. */
	@NamespaceAccessible
	public class SettingsException extends Exception {
	}

	/**
	 * Core's settings as one record, built in memory once per transaction from the settings
	 * store: each key's saved value, else (before carry-over) the legacy value, else its
	 * default. Never null and never saved: it has no Id. A checkbox is never null. Run state is
	 * not on it (`SettingsState`). Costs no query.
	 */
	@NamespaceAccessible
	public static BarnCRM_Settings__c getSettings() {
		if (cachedSettings == null) {
			BarnCRM_Settings__c record = new BarnCRM_Settings__c();
			for (String key : fieldsByLocalName(BarnCRM_Settings__c.SObjectType).keySet()) {
				Schema.SObjectField token = fieldsByLocalName(BarnCRM_Settings__c.SObjectType).get(key);
				if (key.endsWith('__c') && !SettingsState.isStateKey(key)) {
					record.put(token, coreEffective(token));
				}
			}
			cachedSettings = record;
		}
		return cachedSettings;
	}

	/** The Core Setting Definition rows that hold a value, by key in lower case (shipped rows). */
	private static Map<String, Setting_Definition__mdt> coreDefinitions() {
		if (cachedCoreDefinitions == null) {
			cachedCoreDefinitions = new Map<String, Setting_Definition__mdt>();
			for (Setting_Definition__mdt definition : SettingStore.definitions().values()) {
				Boolean core = objectName(definition.Settings_Object__c).equalsIgnoreCase(CORE_SETTINGS_OBJECT);
				if (core && String.isNotBlank(definition.Setting_Key__c)) {
					cachedCoreDefinitions.put(definition.Setting_Key__c.trim().toLowerCase(), definition);
				}
			}
		}
		return cachedCoreDefinitions;
	}

	/**
	 * The store name of a Core key: its shipped definition's, else the row the console was given
	 * (a test's stand-in, SettingDefinitionSelector), else null.
	 */
	private static String coreName(Schema.SObjectField token) {
		String key = token.getDescribe().getLocalName().toLowerCase();
		Setting_Definition__mdt definition = coreDefinitions().get(key);
		if (definition == null) {
			// A test's stand-in rows; read without a query, which the read path must not spend.
			for (Setting_Definition__mdt row : SettingDefinitionSelector.getAllShortFields()) {
				Boolean core = objectName(row.Settings_Object__c).equalsIgnoreCase(CORE_SETTINGS_OBJECT);
				if (core && String.isNotBlank(row.Setting_Key__c) && row.Setting_Key__c.trim().equalsIgnoreCase(key)) {
					definition = row;
				}
			}
		}
		return definition == null ? null : definition.DeveloperName;
	}

	/**
	 * What the org saved for a Core key, typed, or null when it saved nothing: the store's value;
	 * before carry-over, with no store record, the legacy custom setting's (R-STV1).
	 */
	private static Object coreStored(Schema.SObjectField token) {
		String name = coreName(token);
		if (name != null && SettingStore.has(name)) {
			return typed(SettingStore.parse(SettingStore.saved(name)), token);
		}
		if (SettingStore.isCarriedOver()) {
			return null;
		}
		BarnCRM_Settings__c legacy = legacySettings();
		Object value = legacy.Id == null ? null : legacy.get(token);
		return value instanceof String && String.isBlank((String) value) ? null : value;
	}

	/**
	 * The shipped default of a Core key, typed, or null (a checkbox: false). A Core key whose
	 * definition ships in a module that is not installed (Org Optimizer's) falls back to the
	 * field's declared default, which the CI check keeps equal to the definition's.
	 */
	private static Object coreDefault(Schema.SObjectField token) {
		String key = token.getDescribe().getLocalName().toLowerCase();
		Object value = coreDefinitions().containsKey(key)
			? typed(SettingStore.parse(SettingStore.defaultOf(coreDefinitions().get(key).DeveloperName)), token)
			: declaredField(token);
		return value == null && token.getDescribe().getType() == Schema.DisplayType.BOOLEAN ? false : value;
	}

	private static SObject declaredCore;

	private static Object declaredField(Schema.SObjectField token) {
		if (declaredCore == null) {
			declaredCore = BarnCRM_Settings__c.SObjectType.newSObject(null, true);
		}
		return declaredCore.get(token);
	}

	private static Object coreEffective(Schema.SObjectField token) {
		Object stored = coreStored(token);
		return stored != null ? stored : coreDefault(token);
	}

	/** The legacy custom setting's org-level record, read once per transaction, never null. */
	private static BarnCRM_Settings__c legacySettings() {
		if (cachedLegacy == null) {
			BarnCRM_Settings__c stored = BarnCRM_Settings__c.getOrgDefaults();
			cachedLegacy = stored == null ? new BarnCRM_Settings__c() : stored;
		}
		return cachedLegacy;
	}

	/** A value parsed from JSON in the field's own type, or null when it cannot be. */
	private static Object typed(Object value, Schema.SObjectField token) {
		if (value == null || value instanceof Datetime || value instanceof Boolean) {
			return value;
		}
		Schema.DisplayType kind = token.getDescribe().getType();
		String text = String.valueOf(value);
		try {
			if (kind == Schema.DisplayType.BOOLEAN) {
				return value instanceof Boolean ? value : Boolean.valueOf(text);
			}
			if (kind == Schema.DisplayType.INTEGER) {
				return Integer.valueOf(text);
			}
			if (isNumeric(kind)) {
				return Decimal.valueOf(text);
			}
			if (kind == Schema.DisplayType.DATETIME) {
				return (Datetime) JSON.deserialize(JSON.serialize(text), Datetime.class);
			}
			if (kind == Schema.DisplayType.DATE) {
				return (Date) JSON.deserialize(JSON.serialize(text), Date.class);
			}
		} catch (Exception unreadable) {
			return null;
		}
		return text;
	}

	/**
	 * Puts a Core setting in the store for a test, as if it were deployed (ADR-0238 settings as
	 * custom metadata: tests cannot deploy metadata). Keyed by the field name, as readers name it.
	 */
	@NamespaceAccessible
	public static void setForTest(String key, Object value) {
		Setting_Definition__mdt definition = coreDefinitions().get(key.trim().toLowerCase());
		if (definition == null) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
		}
		SettingStore.setForTest(definition.DeveloperName, value);
		clearCaches();
	}

	/** The deployment the last store save in this transaction sent, or null (none, or a test). */
	@NamespaceAccessible
	public static Id lastDeploymentId() {
		return lastDeployment;
	}

	/** Store changes held back by `collectSaves`, sent as one deployment by `sendCollected`. */
	private static List<SettingStore.Change> collected;
	private static Boolean collectedAudit = true;

	/**
	 * Holds back every store save that follows until `sendCollected`, so one page save that
	 * touches Core and modules sends one deployment, and the page follows one outcome.
	 */
	@NamespaceAccessible
	public static void collectSaves() {
		collected = new List<SettingStore.Change>();
		collectedAudit = true;
	}

	/** Sends what `collectSaves` held back as one deployment and returns its Id (null when nothing). */
	@NamespaceAccessible
	public static Id sendCollected() {
		List<SettingStore.Change> changes = collected;
		Boolean audit = collectedAudit;
		stopCollecting();
		if (changes == null || changes.isEmpty()) {
			return null;
		}
		sendStoreChanges(changes, audit);
		return lastDeployment;
	}

	/** Stops holding saves back, dropping anything not sent (a save that failed part way). */
	@NamespaceAccessible
	public static void stopCollecting() {
		collected = null;
		collectedAudit = true;
	}

	/** True when Core's settings object actually has the given key. */
	@NamespaceAccessible
	public static Boolean hasKey(String key) {
		return hasKey(CORE_SETTINGS_OBJECT, key);
	}

	/** True when the named settings object actually has the given key. */
	@NamespaceAccessible
	public static Boolean hasKey(String settingsObject, String key) {
		if (String.isBlank(key)) {
			return false;
		}
		if (ModuleSettings.isStoreObject(settingsObject)) {
			return ModuleSettings.definitionFor(settingsObject, key) != null;
		}
		// Called once per Setting Definition row by SettingsController.toSetting, so the type
		// and its fields come from the per-transaction caches, never a fresh describe.
		Schema.SObjectType type = typeByName(objectName(settingsObject));
		return type != null && fieldsByLocalName(type).containsKey(key.trim().toLowerCase());
	}

	/** The current value of one Core setting, or null. Throws when the key does not exist. */
	@NamespaceAccessible
	public static Object getValue(String key) {
		return getValue(CORE_SETTINGS_OBJECT, key);
	}

	/** The current value of one setting on the named settings object, or null. */
	@NamespaceAccessible
	public static Object getValue(String settingsObject, String key) {
		if (ModuleSettings.isStoreObject(settingsObject)) {
			return ModuleSettings.stored(storeName(settingsObject, key));
		}
		Schema.SObjectType type = settingsType(settingsObject);
		Schema.SObjectField token = fieldFor(type, key);
		if (!isCoreSettings(type)) {
			return orgDefault(type).get(token);
		}
		// Core: what the org saved (null when nothing), or the run state under the key.
		return SettingsState.isStateKey(key) ? typed(SettingsState.get(key.trim()), token) : coreStored(token);
	}

	// Typed readers (D-200 S8): every module reads its settings through these, so the shipped
	// value is the field's declared default and the range is its Setting Definition's, each
	// stated once. None throws: a setting that cannot be read is treated as never saved.

	/** A checkbox setting: the stored value, else the field's declared default, else false. */
	@NamespaceAccessible
	public static Boolean flag(String settingsObject, String key) {
		if (ModuleSettings.isStoreObject(settingsObject)) {
			return ModuleSettings.flag(knownStoreName(settingsObject, key));
		}
		Object value = storedValue(settingsObject, key);
		value = value == null ? declaredValue(settingsObject, key) : value;
		return value == null ? false : Boolean.valueOf(String.valueOf(value));
	}

	/**
	 * A number setting: the stored value, or the field's declared default when it is blank,
	 * not a number, or outside the Min and Max of its Setting Definition row.
	 */
	@NamespaceAccessible
	public static Decimal number(String settingsObject, String key) {
		if (ModuleSettings.isStoreObject(settingsObject)) {
			return ModuleSettings.number(knownStoreName(settingsObject, key));
		}
		Decimal value = toNumber(storedValue(settingsObject, key));
		Setting_Definition__mdt row = value == null
			? null
			: definitionsByKey(objectName(settingsObject)).get(key.trim().toLowerCase());
		Boolean outside =
			row != null &&
			((row.Min_Value__c != null && value < row.Min_Value__c) ||
			(row.Max_Value__c != null &&
			value > row.Max_Value__c));
		return value == null || outside ? toNumber(declaredValue(settingsObject, key)) : value;
	}

	/** A text setting, trimmed: the stored value, or the field's declared default when blank. */
	@NamespaceAccessible
	public static String text(String settingsObject, String key) {
		if (ModuleSettings.isStoreObject(settingsObject)) {
			return asText(ModuleSettings.text(knownStoreName(settingsObject, key)));
		}
		String value = asText(storedValue(settingsObject, key)).trim();
		return String.isBlank(value) ? asText(declaredValue(settingsObject, key)).trim() : value;
	}

	/** A Core number setting as stored, or null when it is blank, unknown or not a number. */
	@NamespaceAccessible
	public static Decimal storedNumber(String key) {
		return hasKey(key) ? toNumber(getValue(key)) : null;
	}

	/**
	 * Any value as a number, trimmed, or null when it is null, blank or not a number. The one
	 * lenient parser every package uses for setting, record and input values (`?? fallback`
	 * for a default).
	 */
	@NamespaceAccessible
	public static Decimal toNumber(Object value) {
		try {
			return value == null ? null : Decimal.valueOf(String.valueOf(value).trim());
		} catch (TypeException notANumber) {
			return null;
		}
	}

	/** The store name (definition DeveloperName) of a module key; throws when it has no definition. */
	private static String storeName(String settingsObject, String key) {
		String name = knownStoreName(settingsObject, key);
		if (name == null) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
		}
		return name;
	}

	private static String knownStoreName(String settingsObject, String key) {
		Setting_Definition__mdt row = ModuleSettings.definitionFor(settingsObject, key);
		return row == null ? null : row.DeveloperName;
	}

	private static Object storedValue(String settingsObject, String key) {
		try {
			return getValue(settingsObject, key);
		} catch (Exception unreadable) {
			return null;
		}
	}

	/** The declared defaults of each settings object, built once per transaction. */
	private static Map<String, SObject> declaredDefaults = new Map<String, SObject>();

	private static Object declaredValue(String settingsObject, String key) {
		try {
			Schema.SObjectType type = settingsType(settingsObject);
			if (isCoreSettings(type)) {
				return coreDefault(fieldFor(type, key));
			}
			String name = String.valueOf(type);
			if (!declaredDefaults.containsKey(name)) {
				declaredDefaults.put(name, type.newSObject(null, true));
			}
			return declaredDefaults.get(name).get(fieldFor(type, key));
		} catch (Exception unknown) {
			return null;
		}
	}

	/**
	 * The Core settings whose blank means "nobody has chosen yet", so the stored value has to
	 * stay blank (CoexistenceService reads a blank coexistence mode as unconfirmed and a blank
	 * membership mode as the only one detection may change; see `blanksKeptBlank`).
	 * Coexistence mode is still shown with the recommended mode selected (see
	 * `getEffectiveValue`), nothing stored. The membership mode is shown as stored here:
	 * `SettingsController.toSetting` shows `householdMembershipMode()` for a blank one, display
	 * only. Lower-case field names.
	 */
	private static final String COEXISTENCE_FIELD = 'coexistence_mode__c';
	private static final Set<String> SHOWN_AS_STORED = new Set<String>{ 'household_membership_mode__c' };
	/**
	 * Text settings that show the org's My Domain address while blank, as `object.field` in
	 * lower case: the address is known only at run time, so no declared default can hold it.
	 * A module's install fills the stored value too; this covers an org it never ran in.
	 */
	private static final Set<String> SHOWN_AS_MY_DOMAIN = new Set<String>{
		'projects_settings__c.invoice_return_url__c'
	};

	/**
	 * What the console should show for a setting: the stored value, or, when nothing is stored,
	 * the default the org is running on. An org that has never saved a module's settings has no
	 * row at all, and a first save keeps blanks blank (`blanksKeptBlank`), so a picklist or a
	 * number with a declared default read as empty and looked like "no default" even though
	 * every reader treats a blank as that default. Nothing is written: this only changes what
	 * is displayed, and saving still stores only what the administrator changed.
	 *
	 * Picklist, Number and Text rows are filled in (a setting shows its default until changed,
	 * never an empty box; every reader treats a blank in these as the default). A checkbox is
	 * never blank (its shipped value is already on the record, ADR-0035). Coexistence mode,
	 * whose stored blank means "not confirmed", is shown as the mode detection recommends;
	 * the stored value stays blank until somebody saves it. A row in `SHOWN_AS_STORED` is shown
	 * as stored. A SetupValue row never comes here: Setup holds its value and it has no default
	 * of BarnCRM's (ADR-0135), so `SettingsController.toSetting` reads it first and returns.
	 */
	@NamespaceAccessible
	public static Object getEffectiveValue(String settingsObject, String key, String dataType) {
		if (ModuleSettings.isStoreObject(settingsObject)) {
			return storeEffectiveValue(settingsObject, key);
		}
		Schema.SObjectType type = settingsType(settingsObject);
		Schema.SObjectField field = fieldFor(type, key);
		Boolean core = isCoreSettings(type);
		Object stored = core ? coreStored(field) : orgDefault(type).get(field);
		Boolean blank = stored == null || (stored instanceof String && String.isBlank((String) stored));
		Boolean fillable =
			PICKLIST.equalsIgnoreCase(dataType) ||
			PICKLIST_FROM_FIELD.equalsIgnoreCase(dataType) ||
			NUMBER_TYPE.equalsIgnoreCase(dataType) ||
			TEXT_TYPE.equalsIgnoreCase(dataType);
		if (!blank) {
			return stored;
		}
		if (!fillable) {
			// A Core checkbox nothing saved shows its shipped default (R-STV1).
			return core ? coreDefault(field) : stored;
		}
		String name = field.getDescribe().getLocalName().toLowerCase();
		if (isCoreSettings(type) && COEXISTENCE_FIELD.equals(name)) {
			return OrgShapeDetector.recommendedCoexistenceMode();
		}
		if (isCoreSettings(type) && SHOWN_AS_STORED.contains(name)) {
			return stored;
		}
		if (SHOWN_AS_MY_DOMAIN.contains(type.getDescribe().getLocalName().toLowerCase() + '.' + name)) {
			return Url.getOrgDomainUrl().toExternalForm();
		}
		Object declared = core ? coreDefault(field) : type.newSObject(null, true).get(field);
		return declared == null ? stored : declared;
	}

	/**
	 * `getEffectiveValue` for a module whose settings are in the store: what the org saved, else
	 * the definition's default (a checkbox with none reads false), else, for a My Domain row, the
	 * org's address. Needs no settings object, so it works once the legacy object is removed.
	 */
	private static Object storeEffectiveValue(String settingsObject, String key) {
		String name = storeName(settingsObject, key);
		Object stored = ModuleSettings.stored(name);
		if (stored != null && !(stored instanceof String && String.isBlank((String) stored))) {
			return stored;
		}
		Object shipped = ModuleSettings.defaultValue(name);
		Setting_Definition__mdt row = ModuleSettings.definition(name);
		if (shipped == null && 'Checkbox'.equalsIgnoreCase(row.Data_Type__c)) {
			return false;
		}
		String qualified = (settingsObject.trim() + '.' + key.trim()).toLowerCase();
		if (shipped == null && SHOWN_AS_MY_DOMAIN.contains(qualified)) {
			return Url.getOrgDomainUrl().toExternalForm();
		}
		return shipped;
	}

	/**
	 * Saves the given Core values, keyed by the API name of the BarnCRM Settings field.
	 * Only keys that exist on the object and are listed in a Setting Definition row are
	 * accepted. Returns the refreshed Core settings.
	 */
	@NamespaceAccessible
	public static BarnCRM_Settings__c saveValues(Map<String, Object> values) {
		applyValues(CORE_SETTINGS_OBJECT, values, true, true);
		return getSettings();
	}

	/**
	 * Saves the given values on the named settings object. The object has to be a hierarchy
	 * custom setting named by at least one shipped Setting Definition row. Returns the saved
	 * org-level record, or null for a module whose settings are in the store (`Setting_Module__mdt`):
	 * those save in one deployment (`lastDeploymentId`).
	 */
	@NamespaceAccessible
	public static SObject saveValues(String settingsObject, Map<String, Object> values) {
		return applyValues(settingsObject, values, true, true);
	}

	/**
	 * Saves one value the package itself owns, such as the modules turned off, which has no
	 * Setting Definition row because it is not edited on the settings page. Audited.
	 */
	@NamespaceAccessible
	public static BarnCRM_Settings__c saveSystemValue(String key, Object value) {
		applyValues(CORE_SETTINGS_OBJECT, new Map<String, Object>{ key => value }, false, true);
		return getSettings();
	}

	/**
	 * Saves values a module writes itself on the named settings object, audited, Hidden rows
	 * included (ModuleSettings.saveSystem). In the store, a key still needs a Setting Definition.
	 */
	@NamespaceAccessible
	public static void saveSystemValues(String settingsObject, Map<String, Object> values) {
		applyValues(settingsObject, values, false, true);
	}

	/**
	 * Saves the package's own bookkeeping, such as how far the setup checklist has got, in one
	 * write and with no audit row (ADMIN-20). A checklist click is not a settings change, and
	 * auditing it pushed real changes out of the Recent changes list.
	 */
	@NamespaceAccessible
	public static void saveBookkeeping(Map<String, Object> values) {
		applyValues(CORE_SETTINGS_OBJECT, values, false, false);
	}

	/**
	 * Validates the given values, then saves only the ones that differ from what is stored.
	 *
	 * The comparison is made against the stored record, read under a lock that holds until this
	 * transaction ends, not against the cached copy: a cached copy can predate another person's
	 * save, and comparing against it would audit the wrong old value. Only the changed keys are
	 * written (OrgSettingsSystemWriter), so a key another person saved in the meantime is never
	 * written back as this transaction first read it.
	 */
	private static SObject applyValues(
		String settingsObject,
		Map<String, Object> values,
		Boolean requireDefinition,
		Boolean audit
	) {
		if (ModuleSettings.isStoreObject(settingsObject)) {
			applyStoreValues(settingsObject.trim(), values, requireDefinition, audit);
			return null;
		}
		Schema.SObjectType type = settingsType(settingsObject);
		if (isCoreSettings(type)) {
			applyCoreValues(values, requireDefinition, audit);
			return getSettings();
		}
		// Unreachable: every module is in the store. Removed with the legacy objects' destructive step.
		if (values == null || values.isEmpty()) {
			return orgDefault(type);
		}
		String objectName = localName(type);
		Map<String, Setting_Definition__mdt> rows = definitionsByKey(objectName);
		SObject storedRecord = OrgSettingsSystemWriter.lockStored(type);
		SObject record = storedRecord != null ? storedRecord : orgDefault(type);
		Map<Schema.SObjectField, Object> changed = new Map<Schema.SObjectField, Object>();
		List<Setting_Change__c> changes = new List<Setting_Change__c>();
		Datetime changedAt = System.now();
		for (String key : values.keySet()) {
			Schema.SObjectField token = fieldFor(type, key);
			Schema.DescribeFieldResult field = token.getDescribe();
			String localName = field.getLocalName();
			Setting_Definition__mdt definition = rows.get(localName.toLowerCase());
			if (requireDefinition && definition == null) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
			}
			Object oldValue = record.get(token);
			// A blank stored value is shown as the declared default, so that value saves as is.
			Object shownValue = oldValue != null ? oldValue : type.newSObject(null, true).get(token);
			Object newValue = checkedValue(values.get(key), field, definition, shownValue);
			String oldText = asText(oldValue);
			String newText = asText(newValue);
			if (oldText.equals(newText)) {
				continue;
			}
			refuseIfMembershipDataWouldBeStranded(token, oldText, newText);
			refuseIfDigestRecipientsAreNotUsers(token, newText);
			refuseIfNoRecordTypeCannotWork(token, newText);
			changed.put(token, newValue);
			if (!audit) {
				continue;
			}
			changes.add(
				new Setting_Change__c(
					Setting_Name__c = objectName + '.' + localName,
					Old_Value__c = stored(oldText),
					New_Value__c = stored(newText),
					Changed_By__c = UserInfo.getUserId(),
					Changed_At__c = changedAt
				)
			);
		}
		if (changed.isEmpty()) {
			return record;
		}
		refuseIfAddressWouldBeIncomplete(type, record, changed);
		SettingsWriter.saveOrgDefault(type, storedRecord, changed);
		if (!changes.isEmpty()) {
			Database.insert(changes, AccessLevel.USER_MODE);
		}
		clearCaches();
		// Core's own side effects follow its store saves (afterSaved); a module hands its keys on.
		Set<String> keys = new Set<String>();
		for (Schema.SObjectField token : changed.keySet()) {
			keys.add(token.getDescribe().getLocalName());
		}
		notifyRollupEngine(objectName, keys);
		return orgDefault(type);
	}

	/**
	 * Validates Core values as `applyValues` does, then saves run-state keys as state rows at
	 * once and every changed setting in one store deployment (ADR-0238 settings as custom
	 * metadata). Compared against what the org saved, so keeping a shown default saves it. The
	 * save's side effects run when the deployment succeeds (`afterSaved`).
	 */
	private static void applyCoreValues(Map<String, Object> values, Boolean requireDefinition, Boolean audit) {
		if (values == null || values.isEmpty()) {
			return;
		}
		Schema.SObjectType type = BarnCRM_Settings__c.SObjectType;
		// Compared against what is stored now, not a copy read earlier in this transaction, so
		// the audit's old value is the one really stored.
		clearCaches();
		Map<String, Setting_Definition__mdt> rows = definitionsByKey(CORE_SETTINGS_OBJECT);
		Map<String, Object> state = new Map<String, Object>();
		Map<Schema.SObjectField, Object> changed = new Map<Schema.SObjectField, Object>();
		List<SettingStore.Change> changes = new List<SettingStore.Change>();
		for (String key : values.keySet()) {
			Schema.SObjectField token = fieldFor(type, key);
			Schema.DescribeFieldResult field = token.getDescribe();
			String localName = field.getLocalName();
			if (SettingsState.isStateKey(localName)) {
				state.put(localName, coerce(values.get(key), field));
				continue;
			}
			Setting_Definition__mdt definition = rows.get(localName.toLowerCase());
			Setting_Definition__mdt shipped = coreDefinitions().get(localName.toLowerCase());
			Setting_Definition__mdt row = definition != null ? definition : shipped;
			Boolean consoleRow = definition != null && !TYPE_HIDDEN.equalsIgnoreCase(definition.Data_Type__c);
			if (row == null || (requireDefinition && !consoleRow)) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
			}
			Object oldValue = coreStored(token);
			Object shownValue = oldValue != null ? oldValue : coreDefault(token);
			Object newValue = checkedValue(values.get(key), field, row, shownValue);
			String oldText = asText(oldValue);
			String newText = asText(newValue);
			if (oldText.equals(newText)) {
				continue;
			}
			refuseIfMembershipDataWouldBeStranded(token, oldText, newText);
			refuseIfDigestRecipientsAreNotUsers(token, newText);
			refuseIfNoRecordTypeCannotWork(token, newText);
			SettingStore.Change change = new SettingStore.Change();
			change.name = shipped != null ? shipped.DeveloperName : definition.DeveloperName;
			change.settingName = CORE_SETTINGS_OBJECT + '.' + localName;
			change.oldText = stored(oldText);
			change.newText = stored(newText);
			change.json = SettingStore.toJson(newValue);
			if (change.json.length() > STORE_VALUE_LIMIT) {
				throw new SettingsException(
					String.format(
						System.Label.Core_Format_Pair,
						new List<Object>{ row.MasterLabel, BarnHelp.text('Core', 'Core_Settings_InvalidValueError') }
					)
				);
			}
			changed.put(token, newValue);
			changes.add(change);
		}
		if (!changed.isEmpty()) {
			refuseIfAddressWouldBeIncomplete(type, getSettings(), changed);
		}
		SettingsState.put(state);
		sendStoreChanges(changes, audit);
	}

	/**
	 * Validates a module's values as `applyCoreValues` does, from its Setting Definition rows
	 * alone (no settings object is described, so this works once the legacy object is removed),
	 * then saves every changed one in one store deployment. The module's run state is not saved
	 * here: it goes to `SettingsState`.
	 */
	private static void applyStoreValues(
		String settingsObject,
		Map<String, Object> values,
		Boolean requireDefinition,
		Boolean audit
	) {
		if (values == null || values.isEmpty()) {
			return;
		}
		clearCaches();
		List<SettingStore.Change> changes = new List<SettingStore.Change>();
		for (String key : values.keySet()) {
			Setting_Definition__mdt row = ModuleSettings.definitionFor(settingsObject, key);
			if (row == null || (requireDefinition && TYPE_HIDDEN.equalsIgnoreCase(row.Data_Type__c))) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
			}
			Object oldValue = ModuleSettings.stored(row.DeveloperName);
			Object shownValue = oldValue != null ? oldValue : ModuleSettings.defaultValue(row.DeveloperName);
			Object newValue = checkedStoreValue(values.get(key), row, shownValue);
			String oldText = asText(oldValue);
			String newText = asText(newValue);
			if (oldText.equals(newText)) {
				continue;
			}
			SettingStore.Change change = new SettingStore.Change();
			change.name = row.DeveloperName;
			change.settingName = settingsObject + '.' + row.Setting_Key__c.trim();
			change.oldText = stored(oldText);
			change.newText = stored(newText);
			change.json = SettingStore.toJson(newValue);
			if (change.json.length() > STORE_VALUE_LIMIT) {
				throw new SettingsException(
					String.format(
						System.Label.Core_Format_Pair,
						new List<Object>{ row.MasterLabel, BarnHelp.text('Core', 'Core_Settings_InvalidValueError') }
					)
				);
			}
			changes.add(change);
		}
		sendStoreChanges(changes, audit);
	}

	/**
	 * A module value read in its row's type (Checkbox a Boolean, Number a Decimal, DateTime a
	 * Datetime, anything else trimmed text, blank null) and checked against the row, refused
	 * with the setting's name as `checkedValue` does.
	 */
	private static Object checkedStoreValue(Object rawValue, Setting_Definition__mdt row, Object oldValue) {
		try {
			Object newValue = storeTyped(rawValue, row.Data_Type__c);
			checkAllowedValue(row, newValue, oldValue);
			return newValue;
		} catch (SettingsException refused) {
			if (refused.getMessage() != BarnHelp.text('Core', 'Core_Settings_InvalidValueError')) {
				throw refused;
			}
			throw new SettingsException(
				String.format(System.Label.Core_Format_Pair, new List<Object>{ row.MasterLabel, refused.getMessage() })
			);
		}
	}

	private static Object storeTyped(Object raw, String dataType) {
		String text = raw == null ? null : asText(raw).trim();
		if ('Checkbox'.equalsIgnoreCase(dataType)) {
			return raw instanceof Boolean ? (Boolean) raw : 'true'.equalsIgnoreCase(text);
		}
		if (String.isBlank(text)) {
			return null;
		}
		if (NUMBER_TYPE.equalsIgnoreCase(dataType)) {
			Decimal parsed = toNumber(text);
			if (parsed == null) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
			}
			return parsed;
		}
		if ('DateTime'.equalsIgnoreCase(dataType)) {
			if (raw instanceof Datetime) {
				return raw;
			}
			try {
				return (Datetime) JSON.deserialize(JSON.serialize(text), Datetime.class);
			} catch (Exception unreadable) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
			}
		}
		return text;
	}

	/**
	 * Sends store changes as one deployment, or holds them for `sendCollected`. Saving a setting
	 * needs Manage BarnCRM Settings, whoever calls.
	 */
	private static void sendStoreChanges(List<SettingStore.Change> changes, Boolean audit) {
		if (changes.isEmpty()) {
			return;
		}
		if (!BarnCRMPermissions.canSaveSettings()) {
			throw new SettingsWriter.PermissionException(
				BarnHelp.text('Core', 'Core_Settings_PermissionRequiredError')
			);
		}
		if (collected != null) {
			collected.addAll(changes);
			collectedAudit = collectedAudit && audit;
			return;
		}
		try {
			lastDeployment = SettingStore.save(changes, audit);
		} catch (SettingStore.SettingStoreException refused) {
			throw new SettingsException(refused.getMessage());
		}
		clearCaches();
	}

	/**
	 * What a Core save does once its deployment has succeeded (SettingValueDeployCallback): the
	 * apps and account tabs people see follow their settings (ADR-0137, C-73), brand sharing
	 * follows either brand switch (R-BR7), the seasonal job follows its switch, the rollup
	 * engine hears of every change (ADR-0125), and organization flags follow the organization
	 * record type (ADR-0238 settings as custom metadata, decision 8).
	 */
	public static void afterSaved(List<SettingStore.Change> changes) {
		clearCaches();
		// Each change's settings group and key: `Group.Key`, or a bare name (the carry-over marker).
		Map<String, Set<String>> keysByObject = new Map<String, Set<String>>();
		Map<String, String> jsonByKey = new Map<String, String>();
		for (SettingStore.Change change : changes) {
			String settingName = change.settingName == null ? change.name : change.settingName;
			String objectName = settingName.contains('.') ? settingName.substringBefore('.') : CORE_SETTINGS_OBJECT;
			String key = settingName.contains('.') ? settingName.substringAfter('.') : settingName;
			if (!keysByObject.containsKey(objectName)) {
				keysByObject.put(objectName, new Set<String>());
			}
			keysByObject.get(objectName).add(key);
			if (objectName.equalsIgnoreCase(CORE_SETTINGS_OBJECT)) {
				jsonByKey.put(key.toLowerCase(), change.json);
			}
		}
		if (jsonByKey.containsKey('account_tabs__c')) {
			TabAccessService.requestSync();
		}
		if (jsonByKey.containsKey('brand_visibility__c') || jsonByKey.containsKey('brand_management__c')) {
			BrandShareJob.requestFull();
		}
		if (jsonByKey.containsKey('organization_record_type__c')) {
			try {
				OrganizationFlagBatch.run();
			} catch (Exception busy) {
				// Logged; the next save of an account sets its flag, and the next install re-runs it.
				ErrorLogger.log(busy, 'OrganizationFlagBatch');
			}
		}
		if (jsonByKey.containsKey('seasonal_addresses_enabled__c')) {
			SeasonalAddressScheduler.applySwitch(jsonByKey.get('seasonal_addresses_enabled__c') == 'true');
		}
		for (String objectName : keysByObject.keySet()) {
			notifyRollupEngine(objectName, keysByObject.get(objectName));
		}
	}

	private static final String TYPE_HIDDEN = 'Hidden';
	private static final Integer STORE_VALUE_LIMIT = 255;

	/**
	 * Tells the rollup engine, when its module is installed, which settings a save changed, so a
	 * setting that times a scheduled job (the nightly rollup run's hour) moves the job in the
	 * same save, as Seasonal Addresses does. Core cannot name the module's settings, so it hands
	 * over every change and the engine picks its own (ADR-0125 decision 4, ADR-0136). A failure
	 * is logged and the saved setting stands. Then every module that registers
	 * `SettingsSavedExtension` hears of it the same way (Fundraising keeps each fund's Is Default
	 * in line with Default Fund).
	 */
	private static void notifyRollupEngine(String objectName, Set<String> keys) {
		RollupEngineExtension engine = RollupEngineExtensions.find();
		if (engine != null) {
			try {
				engine.afterSettingsSaved(objectName, keys);
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'SettingsService.notifyRollupEngine');
			}
		}
		for (Object found : ModuleExtensions.all(SettingsSavedExtension.class)) {
			try {
				((SettingsSavedExtension) found).afterSettingsSaved(objectName, keys);
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'SettingsService.notifyModules');
			}
		}
	}

	/**
	 * How people belong to a household is the one setting whose change can destroy data:
	 * there is no migration between the two ways of belonging, so the records one way keeps
	 * are invisible to the other. The guard lives here because this is the only place the
	 * value is written, whether from the console, the Setup Assistant, or Health Check, and
	 * it runs before anything is saved, so a refused change leaves the org exactly as it was.
	 * CoexistenceService owns the reasoning and the wording.
	 */
	private static void refuseIfMembershipDataWouldBeStranded(
		Schema.SObjectField token,
		String oldText,
		String newText
	) {
		if (token != BarnCRM_Settings__c.Household_Membership_Mode__c) {
			return;
		}
		String refusal = CoexistenceService.membershipChangeRefusal(oldText, newText);
		if (refusal != null) {
			throw new SettingsException(refusal);
		}
	}

	/**
	 * The organization address is all or nothing (R-OA1): blank, or street, city, state and
	 * postal code all present. The check is made on the address as it would be stored after this
	 * save, the new values over the stored ones, so a save that touches one part cannot leave the
	 * rest incomplete. It lives here because this is the one place the parts are written, whether
	 * from the console, the Setup Assistant or a direct call. Nothing is saved when it refuses.
	 */
	private static void refuseIfAddressWouldBeIncomplete(
		Schema.SObjectType type,
		SObject record,
		Map<Schema.SObjectField, Object> changed
	) {
		if (!isCoreSettings(type)) {
			return;
		}
		Boolean touched = false;
		BarnCRM_Settings__c candidate = new BarnCRM_Settings__c();
		for (Schema.SObjectField part : OrganizationAddress.partFields()) {
			touched = touched || changed.containsKey(part);
			candidate.put(part, changed.containsKey(part) ? changed.get(part) : record.get(part));
		}
		String refusal = touched ? OrganizationAddress.refusal(candidate) : null;
		if (refusal != null) {
			throw new SettingsException(refusal);
		}
	}

	/**
	 * The error digest goes only to active users of the org (R-E5), so an address that is not
	 * one is refused here, where every write of the setting passes, with the addresses named.
	 */
	private static void refuseIfDigestRecipientsAreNotUsers(Schema.SObjectField token, String newText) {
		if (token != BarnCRM_Settings__c.Error_Digest_Recipients__c) {
			return;
		}
		String refusal = ErrorDigestRecipients.refusal(newText);
		if (refusal != null) {
			throw new SettingsException(refusal);
		}
	}

	/**
	 * "No record type" for organizations works only in an org with no Account record type to
	 * offer (AccountKinds.noRecordTypeAllowed), so choosing it anywhere else is refused. Checked
	 * only when the value changes, so a section saved with an older stored `Master` still saves.
	 */
	private static void refuseIfNoRecordTypeCannotWork(Schema.SObjectField token, String newText) {
		if (
			token == BarnCRM_Settings__c.Organization_Record_Type__c &&
			AccountKinds.NO_RECORD_TYPE.equalsIgnoreCase(newText) &&
			!AccountKinds.noRecordTypeAllowed()
		) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_NoRecordTypeNotAllowed'));
		}
	}

	/**
	 * The value read in the field's type and checked against its row. A value that cannot be
	 * used is refused with a message that names the setting, as the admin guide promises
	 * (ADMIN-21): with a whole section saved at once, "one of the values" is not enough.
	 */
	private static Object checkedValue(
		Object rawValue,
		Schema.DescribeFieldResult field,
		Setting_Definition__mdt definition,
		Object oldValue
	) {
		try {
			Object newValue = coerce(rawValue, field);
			checkAllowedValue(definition, newValue, oldValue);
			return newValue;
		} catch (SettingsException refused) {
			if (refused.getMessage() != BarnHelp.text('Core', 'Core_Settings_InvalidValueError')) {
				throw refused;
			}
			String name = definition != null && String.isNotBlank(definition.MasterLabel)
				? definition.MasterLabel
				: field.getLabel();
			throw new SettingsException(
				String.format(System.Label.Core_Format_Pair, new List<Object>{ name, refused.getMessage() })
			);
		}
	}

	/**
	 * A picklist row may only be set to one of the choices it ships, so a direct call to the
	 * controller cannot store a value the console would never offer.
	 */
	private static void checkAllowedValue(Setting_Definition__mdt definition, Object newValue, Object oldValue) {
		if (definition == null || newValue == null) {
			return;
		}
		if (PICKLIST_FROM_FIELD.equalsIgnoreCase(definition.Data_Type__c)) {
			checkFieldPicklist(definition, String.valueOf(newValue), asText(oldValue));
			return;
		}
		if (RECORD.equalsIgnoreCase(definition.Data_Type__c)) {
			checkRecord(definition, String.valueOf(newValue));
			return;
		}
		if (RECORD_TYPE.equalsIgnoreCase(definition.Data_Type__c)) {
			checkRecordType(definition, String.valueOf(newValue));
			return;
		}
		if (RECORD_TYPE_LIST.equalsIgnoreCase(definition.Data_Type__c)) {
			checkRecordTypes(definition, String.valueOf(newValue));
			return;
		}
		if (FIELD_LIST.equalsIgnoreCase(definition.Data_Type__c)) {
			checkFields(definition, String.valueOf(newValue));
			return;
		}
		if (NUMBER_TYPE.equalsIgnoreCase(definition.Data_Type__c)) {
			checkRange(definition, newValue);
			return;
		}
		if (
			!PICKLIST.equalsIgnoreCase(definition.Data_Type__c) ||
			String.isBlank(definition.Picklist_Values__c) ||
			newValue == null
		) {
			return;
		}
		String candidate = String.valueOf(newValue);
		for (String pair : definition.Picklist_Values__c.split(';')) {
			String allowed = pair.trim();
			Integer separator = allowed.indexOf(':');
			if (separator >= 0) {
				allowed = allowed.substring(0, separator).trim();
			}
			if (allowed.equals(candidate)) {
				return;
			}
		}
		throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
	}

	/**
	 * A number row is refused outside the range its definition ships, whoever saves it, so the
	 * console never shows a value as saved that its reader would clamp (ADMIN-27).
	 */
	private static void checkRange(Setting_Definition__mdt definition, Object newValue) {
		Decimal candidate;
		try {
			candidate = Decimal.valueOf(String.valueOf(newValue));
		} catch (TypeException notANumber) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
		}
		Decimal low = definition.Min_Value__c;
		Decimal high = definition.Max_Value__c;
		if ((low != null && candidate < low) || (high != null && candidate > high)) {
			throw new SettingsException(
				String.format(
					BarnHelp.text('Core', 'Core_Settings_NumberOutOfRange'),
					new List<Object>{
						definition.MasterLabel,
						low == null ? '' : low.stripTrailingZeros().toPlainString(),
						high == null ? '' : high.stripTrailingZeros().toPlainString()
					}
				)
			);
		}
	}

	/**
	 * A Picklist From Field row holds one of its field's active values, or the value already
	 * stored (kept, so a section still saves after the org retires it). While the org does not
	 * have the field, the row is a text box and any text saves.
	 */
	private static void checkFieldPicklist(Setting_Definition__mdt definition, String candidate, String stored) {
		List<Schema.PicklistEntry> active = activeFieldValues(definition);
		// Exact case: the readers compare the stored value case-sensitively.
		if (active == null || (candidate != null && candidate.equals(stored))) {
			return;
		}
		for (Schema.PicklistEntry entry : active) {
			if (entry.getValue().equals(candidate)) {
				return;
			}
		}
		throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
	}

	/**
	 * The active values of the picklist field a Picklist From Field row names in Record Object
	 * as `Object.Field`, or null when this org has no such object or picklist field, which is
	 * when the console falls back to a text box.
	 */
	public static List<Schema.PicklistEntry> activeFieldValues(Setting_Definition__mdt definition) {
		String source = definition?.Record_Object__c;
		Integer dot = source == null ? -1 : source.indexOf('.');
		if (dot < 1) {
			return null;
		}
		Schema.SObjectType type = typeByName(source.substring(0, dot).trim());
		if (type == null) {
			return null;
		}
		Schema.SObjectField token = type.getDescribe(SObjectDescribeOptions.DEFERRED)
			.fields.getMap()
			.get(source.substring(dot + 1).trim());
		if (token == null) {
			return null;
		}
		Schema.DescribeFieldResult field = token.getDescribe();
		if (field.getType() != Schema.DisplayType.PICKLIST) {
			return null;
		}
		List<Schema.PicklistEntry> active = new List<Schema.PicklistEntry>();
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (entry.isActive()) {
				active.add(entry);
			}
		}
		return active;
	}

	/** A Record row holds the Id of a record of its own object, and nothing else (ADR-0074). */
	private static void checkRecord(Setting_Definition__mdt definition, String candidate) {
		Schema.SObjectType expected = recordObjectType(definition);
		Id recordId;
		try {
			recordId = Id.valueOf(candidate);
		} catch (Exception notAnId) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
		}
		if (expected == null || recordId.getSObjectType() != expected) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
		}
	}

	/**
	 * A Record Type row holds one of the record types it offers, or `Master` for "No record
	 * type" (ADR-0141). For Account that refuses a person record type and one named Household.
	 * A blank is not checked here: it means "not chosen", and the reader detects one.
	 */
	private static void checkRecordType(Setting_Definition__mdt definition, String candidate) {
		String name = candidate.trim();
		if (String.isBlank(name) || AccountKinds.NO_RECORD_TYPE.equalsIgnoreCase(name)) {
			return;
		}
		for (Schema.RecordTypeInfo info : recordTypeChoices(recordObjectType(definition))) {
			if (info.getDeveloperName() == name) {
				return;
			}
		}
		throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
	}

	/**
	 * The record types a Record Type row offers, besides "No record type": for Account, the
	 * organization candidates (AccountKinds, never a person or household type), with Core's own
	 * where the org has none (R-O4a); for any other object, its active record types.
	 */
	public static List<Schema.RecordTypeInfo> recordTypeChoices(Schema.SObjectType type) {
		if (type == Account.SObjectType) {
			return AccountKinds.organizationChoices();
		}
		return recordTypes(type);
	}

	/** A Record Type List row names only record types its object has (ADR-0074). */
	private static void checkRecordTypes(Setting_Definition__mdt definition, String candidate) {
		Set<String> known = new Set<String>();
		for (Schema.RecordTypeInfo info : recordTypes(recordObjectType(definition))) {
			known.add(info.getDeveloperName());
		}
		for (String name : candidate.split(',')) {
			if (String.isNotBlank(name) && !known.contains(name.trim())) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
			}
		}
	}

	/** A Field List row names only fields its object offers (R-AD10). */
	private static void checkFields(Setting_Definition__mdt definition, String candidate) {
		Set<String> known = new Set<String>();
		for (Schema.DescribeFieldResult field : fieldChoices(recordObjectType(definition))) {
			known.add(field.getName().toLowerCase());
		}
		for (String name : candidate.split(',')) {
			if (String.isNotBlank(name) && !known.contains(name.trim().toLowerCase())) {
				throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
			}
		}
	}

	/**
	 * The fields a Field List row offers: the object's custom fields and its Name that the
	 * administrator can read, by label (R-AD10).
	 */
	public static List<Schema.DescribeFieldResult> fieldChoices(Schema.SObjectType type) {
		Map<String, Schema.DescribeFieldResult> byLabel = new Map<String, Schema.DescribeFieldResult>();
		if (type == null) {
			return byLabel.values();
		}
		for (Schema.SObjectField token : type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values()) {
			Schema.DescribeFieldResult field = token.getDescribe();
			if ((field.isCustom() || field.isNameField()) && field.isAccessible()) {
				byLabel.put(field.getLabel() + '|' + field.getName(), field);
			}
		}
		List<String> labels = new List<String>(byLabel.keySet());
		labels.sort();
		List<Schema.DescribeFieldResult> chosen = new List<Schema.DescribeFieldResult>();
		for (String label : labels) {
			chosen.add(byLabel.get(label));
		}
		return chosen;
	}

	/** The object a Record or Record Type List row is about, or null when this org lacks it. */
	public static Schema.SObjectType recordObjectType(Setting_Definition__mdt definition) {
		return definition == null ? null : typeByName(definition.Record_Object__c);
	}

	/** The active record types of an object an administrator can choose, master excluded. */
	public static List<Schema.RecordTypeInfo> recordTypes(Schema.SObjectType type) {
		List<Schema.RecordTypeInfo> chosen = new List<Schema.RecordTypeInfo>();
		if (type == null) {
			return chosen;
		}
		for (Schema.RecordTypeInfo info : type.getDescribe(SObjectDescribeOptions.DEFERRED).getRecordTypeInfos()) {
			if (info.isActive() && !info.isMaster()) {
				chosen.add(info);
			}
		}
		return chosen;
	}

	/**
	 * The org-level record of the given settings object, never null, read once per transaction
	 * per object so a console holding many modules' settings does not query per row. A never
	 * saved object reads as its first save would store it, so a checkbox that ships on reads
	 * as on (ADMIN-4).
	 */
	private static SObject orgDefault(Schema.SObjectType type) {
		if (isCoreSettings(type)) {
			return getSettings();
		}
		String name = localName(type);
		if (cachedOrgDefaults.containsKey(name)) {
			return cachedOrgDefaults.get(name);
		}
		SObject record = SettingsRecordSelector.getOrgDefault(type);
		SObject resolved = record == null ? firstSaveRecord(type) : record;
		cachedOrgDefaults.put(name, resolved);
		return resolved;
	}

	/**
	 * The first save of the org's settings writes one key, but the platform fills every other
	 * blank field that declares a default as it creates the record. Two of those blanks mean
	 * something: a blank coexistence mode is one nobody has confirmed, and a blank membership
	 * mode is the only one detection may change (CoexistenceService). Saving, say, the legal
	 * name would otherwise confirm a mode and choose a way of belonging that nobody chose, and
	 * finish Setup Assistant steps nobody took.
	 *
	 * So the first save is followed by this: every custom field that was blank when the save
	 * was asked for is put back to blank, leaving the record exactly as it read before plus the
	 * keys that were saved. A checkbox is left out, because it is never blank: its shipped
	 * value is already on the record (ADR-0035). Every reader treats a blank as the shipped
	 * default, as it must on an org that has never saved at all.
	 */
	private static SObject blanksKeptBlank(Schema.SObjectType type, SObject saved) {
		SObject blanks = type.newSObject(saved.Id);
		for (Schema.SObjectField field : type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values()) {
			Schema.DescribeFieldResult describe = field.getDescribe();
			Boolean blank = saved.get(field) == null;
			if (describe.isCustom() && describe.getType() != Schema.DisplayType.BOOLEAN && blank) {
				blanks.put(field, null);
			}
		}
		return blanks;
	}

	/**
	 * The record a system mode writer creates when the org has never saved its legacy Core
	 * settings: owned by the org, with the checkbox defaults its field metadata declares
	 * (ADR-0035). Only tests and the legacy writers still save that record (ADR-0238 settings as
	 * custom metadata); it is removed with the object in phase 2.
	 */
	@NamespaceAccessible
	public static BarnCRM_Settings__c firstSaveRecord() {
		return (BarnCRM_Settings__c) firstSaveRecord(BarnCRM_Settings__c.SObjectType);
	}

	/**
	 * The same for any settings object. Each gets the
	 * checkbox defaults its own field metadata declares, because Core cannot name a module's
	 * fields (ADR-0059) and the module's readers already treat an unsaved checkbox as its
	 * shipped value. Without this, a module's first save (a nightly job recording its run, say)
	 * stored every checkbox nobody touched as false, and switched off the features that ship
	 * on (ADR-0035, "the second half of the same trap").
	 *
	 * Only checkboxes are taken from the declared defaults. Every other field is left unset, as
	 * it was before, so this changes nothing but the one value a record cannot leave blank.
	 */
	@NamespaceAccessible
	public static SObject firstSaveRecord(Schema.SObjectType type) {
		SObject record = type.newSObject();
		record.put(SETUP_OWNER, UserInfo.getOrganizationId());
		SObject declared = type.newSObject(null, true);
		for (Schema.SObjectField field : checkboxFields(type)) {
			Object shipped = declared.get(field);
			if (shipped != null) {
				record.put(field, shipped);
			}
		}
		return record;
	}

	/** The custom checkbox fields of a settings object, from the cached field map. */
	private static List<Schema.SObjectField> checkboxFields(Schema.SObjectType type) {
		List<Schema.SObjectField> checkboxes = new List<Schema.SObjectField>();
		for (Schema.SObjectField field : fieldsByLocalName(type).values()) {
			Schema.DescribeFieldResult describe = field.getDescribe();
			if (describe.isCustom() && describe.getType() == Schema.DisplayType.BOOLEAN) {
				checkboxes.add(field);
			}
		}
		return checkboxes;
	}

	/**
	 * The same correction as `blanksKeptBlank` for a writer outside this class that saves the
	 * org's settings for the first time: the record to save next, putting back to blank every
	 * field that was blank on `saved` before the platform filled its default
	 * (OrgSettingsSystemWriter).
	 */
	@NamespaceAccessible
	public static SObject blanksAfterFirstSave(SObject saved) {
		return blanksKeptBlank(saved.getSObjectType(), saved);
	}

	private static String localName(Schema.SObjectType type) {
		return type.getDescribe(SObjectDescribeOptions.DEFERRED).getLocalName();
	}

	private static Boolean isCoreSettings(Schema.SObjectType type) {
		return type == BarnCRM_Settings__c.SObjectType;
	}

	/**
	 * The settings object a caller named, checked: it has to exist, be a hierarchy custom
	 * setting, and either be Core's own or be named by a shipped Setting Definition row.
	 */
	private static Schema.SObjectType settingsType(String settingsObject) {
		String name = objectName(settingsObject);
		if (!CORE_SETTINGS_OBJECT.equalsIgnoreCase(name) && !registeredObjects().contains(name.toLowerCase())) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
		}
		Schema.SObjectType type = typeByName(name);
		if (type == null) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
		}
		if (checkedSettingsTypes.contains(type)) {
			return type;
		}
		Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
		if (!describe.isCustomSetting() || !describe.fields.getMap().containsKey(SETUP_OWNER)) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
		}
		checkedSettingsTypes.add(type);
		return type;
	}

	/** Settings objects already described and found to be hierarchy settings, this transaction. */
	private static Set<Schema.SObjectType> checkedSettingsTypes = new Set<Schema.SObjectType>();

	private static String objectName(String settingsObject) {
		return String.isBlank(settingsObject) ? CORE_SETTINGS_OBJECT : settingsObject.trim();
	}

	/**
	 * The object a metadata row names, BarnCRM's own before any other of the same name, cached
	 * per transaction. See `NamespaceUtil.objectType`.
	 */
	@NamespaceAccessible
	public static Schema.SObjectType typeByName(String apiName) {
		return NamespaceUtil.objectType(apiName);
	}

	/**
	 * The settings objects the shipped rows name. Read from the short fields, which costs no
	 * query, because a module's save asks this every time it reads one of its settings.
	 */
	private static Set<String> registeredObjects() {
		Set<String> names = new Set<String>();
		for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAllShortFields()) {
			names.add(objectName(definition.Settings_Object__c).toLowerCase());
		}
		return names;
	}

	/**
	 * Forgets the cached settings, so the next read in this transaction comes from the platform.
	 * Every writer of a settings object, in any package, calls this after it writes. Nothing is
	 * cached across transactions here: the platform's own custom settings cache already serves
	 * `getOrgDefaults()` without a query (ADR-0094).
	 */
	@NamespaceAccessible
	public static void clearCaches() {
		cachedSettings = null;
		cachedLegacy = null;
		cachedOrgDefaults.clear();
		SettingStore.clearCache();
		ModuleSettings.clearCache();
		cachedCoreDefinitions = null;
	}

	/** The shipped rows for one settings object, by the key each one edits. */
	private static Map<String, Setting_Definition__mdt> definitionsByKey(String objectName) {
		Map<String, Setting_Definition__mdt> rows = new Map<String, Setting_Definition__mdt>();
		for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
			Boolean sameObject = objectName(definition.Settings_Object__c).equalsIgnoreCase(objectName);
			if (sameObject && String.isNotBlank(definition.Setting_Key__c)) {
				rows.put(definition.Setting_Key__c.trim().toLowerCase(), definition);
			}
		}
		return rows;
	}

	private static Schema.SObjectField fieldFor(Schema.SObjectType type, String key) {
		Schema.SObjectField token = String.isBlank(key) ? null : fieldsByLocalName(type).get(key.trim().toLowerCase());
		if (token == null) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_UnknownKeyError'));
		}
		return token;
	}

	private static Map<String, Schema.SObjectField> fieldsByLocalName(Schema.SObjectType type) {
		// The token's own name, so a cached object is answered without describing it again.
		String name = String.valueOf(type);
		if (cachedFields.containsKey(name)) {
			return cachedFields.get(name);
		}
		Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
		Map<String, Schema.SObjectField> fields = new Map<String, Schema.SObjectField>();
		for (Schema.SObjectField token : describe.fields.getMap().values()) {
			fields.put(token.getDescribe().getLocalName().toLowerCase(), token);
		}
		cachedFields.put(name, fields);
		return fields;
	}

	private static Object coerce(Object raw, Schema.DescribeFieldResult field) {
		Schema.DisplayType kind = field.getType();
		String text = raw == null ? null : String.valueOf(raw).trim();
		if (kind == Schema.DisplayType.BOOLEAN) {
			return raw instanceof Boolean ? (Boolean) raw : (String.isBlank(text) ? false : Boolean.valueOf(text));
		}
		Object typed = alreadyTyped(kind, raw);
		if (typed != null) {
			return typed;
		}
		if (String.isBlank(text)) {
			return null;
		}
		Object parsed = parse(kind, text);
		if (parsed != null) {
			return parsed;
		}
		Integer maximum = field.getLength();
		if (maximum > 0 && text.length() > maximum) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
		}
		return text;
	}

	/**
	 * The value exactly as the caller handed it in, when its Apex type is already the field's
	 * own type, or null when it is not.
	 *
	 * A caller inside the package passes a real Datetime, not text: `SetupAssistantService`
	 * records when setup started. `String.valueOf(Datetime)` produces `yyyy-MM-dd HH:mm:ss`,
	 * which is not the ISO 8601 form `parse` reads back, so putting every value through text
	 * refused the package's own writes and took the whole Setup Assistant with it.
	 *
	 * Only the two date types are named here. A number handed in as an Integer or a Decimal
	 * already survives the round trip through text, and `parse` returns the Decimal the field
	 * takes, so naming numbers as well would add a second way to do what already works.
	 */
	private static Object alreadyTyped(Schema.DisplayType kind, Object raw) {
		if (raw == null) {
			return null;
		}
		if (kind == Schema.DisplayType.DATETIME && raw instanceof Datetime) {
			return raw;
		}
		if (kind == Schema.DisplayType.DATE && raw instanceof Date) {
			return raw;
		}
		return null;
	}

	/** The value a non-text setting holds, or null when the setting is text after all. */
	private static Object parse(Schema.DisplayType kind, String text) {
		try {
			if (kind == Schema.DisplayType.INTEGER) {
				return Integer.valueOf(text);
			}
			if (isNumeric(kind)) {
				return Decimal.valueOf(text);
			}
			if (kind == Schema.DisplayType.DATETIME) {
				return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
			}
			if (kind == Schema.DisplayType.DATE) {
				return (Date) JSON.deserialize('"' + text + '"', Date.class);
			}
		} catch (Exception e) {
			throw new SettingsException(BarnHelp.text('Core', 'Core_Settings_InvalidValueError'));
		}
		return null;
	}

	private static Boolean isNumeric(Schema.DisplayType kind) {
		return kind == Schema.DisplayType.DOUBLE ||
			kind == Schema.DisplayType.CURRENCY ||
			kind == Schema.DisplayType.PERCENT;
	}

	/**
	 * What an audit row holds for a value that is not set: nothing.
	 *
	 * `asText` answers `''` so that a setting that has never been set and one that was cleared
	 * compare equal and no audit row is written for a save that changed nothing. An audit row is
	 * a different question: an unset setting is null, and the platform stores an empty text field
	 * as null anyway, so writing `''` would have claimed something the record could never say
	 * back. Old and new go through the same call, so a value cleared reads the same as a value
	 * never set, which is what happened.
	 */
	private static String stored(String text) {
		return String.isEmpty(text) ? null : text;
	}

	/** One text form for every value type, so old and new can be compared and audited. */
	public static String asText(Object value) {
		if (value == null) {
			return '';
		}
		// A Date is also `instanceof Datetime` in Apex, so test for Date first: a date setting
		// reads as YYYY-MM-DD, the form a date input takes, not as a midnight GMT date-time.
		if (value instanceof Date) {
			return String.valueOf((Date) value);
		}
		if (value instanceof Datetime) {
			return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
		}
		return String.valueOf(value);
	}

	@NamespaceAccessible
	public static final String COEXISTENCE_MODE_DEFAULT = 'Standalone';
	@NamespaceAccessible
	public static final String MEMBERSHIP_MODE_DEFAULT = 'Contact';

	@TestVisible
	private static final Set<String> COEXISTENCE_MODES = new Set<String>{ 'Standalone', 'NPSP', 'NonprofitCloud' };
	@TestVisible
	private static final Set<String> MEMBERSHIP_MODES = new Set<String>{ 'Contact', 'Junction' };

	private static String storedOrDefault(String stored, Set<String> allowed, String fallback) {
		return String.isNotBlank(stored) && allowed.contains(stored) ? stored : fallback;
	}

	/**
	 * Writes one audit row. Callers write a row only when a value actually changed (rule R-S1).
	 */
	@NamespaceAccessible
	public static void logChange(String settingName, String oldValue, String newValue) {
		if (String.isBlank(settingName)) {
			return;
		}
		Setting_Change__c change = new Setting_Change__c(
			Setting_Name__c = settingName.left(255),
			Old_Value__c = stored(oldValue),
			New_Value__c = stored(newValue),
			Changed_By__c = UserInfo.getUserId(),
			Changed_At__c = System.now()
		);
		Database.insert(change, AccessLevel.USER_MODE);
	}

	@NamespaceAccessible
	public static String householdMembershipMode() {
		return storedOrDefault(getSettings().Household_Membership_Mode__c, MEMBERSHIP_MODES, MEMBERSHIP_MODE_DEFAULT);
	}
}
