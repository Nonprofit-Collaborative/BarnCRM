/**
 * Reads and writes the org's settings.
 *
 * Each package owns a protected hierarchy custom setting (ADR-0017): Core's is
 * `BarnCRM_Settings__c` and a module ships its own, named on its Setting Definition rows.
 * Every write is validated against that object's own schema and against the shipped rows, is
 * audited as a Setting Change record, and clears the cached copy so the next transaction sees
 * the new value (canonical model Section 12, R-N3).
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
    public static final String RECORD_TYPE_LIST = 'RecordTypeList';

    /**
     * The Core checkbox settings that ship switched on, and the reason this map has to exist.
     *
     * A checkbox field can declare `<defaultValue>true</defaultValue>`, and that default is what
     * the platform applies when a record is created through the user interface. It is not what
     * Apex reads. `BarnCRM_Settings__c.getOrgDefaults()` on an org that has never saved its
     * settings returns a materialized record with every checkbox false, not null and not the
     * shipped default, so a feature that ships on reads as switched off on every fresh install
     * and does nothing at all, silently. That is what happened to the relationship reciprocal
     * upkeep: C-15 shipped a feature that wrote only the side the person entered.
     *
     * The default is applied to the record only while the org has never saved one. From the
     * first save onwards the stored value governs, including a deliberate false, and the first
     * save carries these defaults into the record it creates, because every first save starts
     * from `firstSaveRecord` (OrgSettingsSystemWriter). So an administrator who saves some
     * unrelated setting does not silently switch a shipped feature off.
     *
     * A field belongs here when it ships on. `scripts/ci/check-setting-defaults.py` fails the
     * build when a checkbox that ships on is missing from it (ADR-0035).
     */
    private static final Map<Schema.SObjectField, Boolean> SHIPPED_DEFAULTS = new Map<Schema.SObjectField, Boolean>{
        BarnCRM_Settings__c.Relationship_Auto_Reciprocal__c => true,
        BarnCRM_Settings__c.Auto_Create_Households__c => true,
        BarnCRM_Settings__c.Job_Notifications__c => true
    };

    private static BarnCRM_Settings__c cachedSettings;
    private static Map<String, SObject> cachedOrgDefaults = new Map<String, SObject>();
    private static Map<String, Map<String, Schema.SObjectField>> cachedFields = new Map<String, Map<String, Schema.SObjectField>>();

    /** Raised when a setting does not exist, is not editable here, or the value cannot be read. */
    @NamespaceAccessible
    public class SettingsException extends Exception {
    }

    /**
     * The org-level Core settings record, from the static cache, then the platform. Never null:
     * an org that has never saved gets an empty record carrying the shipped defaults (see
     * `SHIPPED_DEFAULTS`). `getOrgDefaults()` costs no query: the platform serves custom
     * settings from its own cache across transactions and refreshes it when a save commits.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c getSettings() {
        if (cachedSettings == null) {
            cachedSettings = withShippedDefaults(BarnCRM_Settings__c.getOrgDefaults());
        }
        return cachedSettings;
    }

    /**
     * Puts the shipped defaults on a settings record the org has never saved, and leaves a saved
     * record exactly as the org left it. An unsaved hierarchy custom setting has no Id, which is
     * what tells the two apart.
     */
    private static BarnCRM_Settings__c withShippedDefaults(BarnCRM_Settings__c record) {
        if (record == null || record.Id != null) {
            return record;
        }
        for (Schema.SObjectField field : SHIPPED_DEFAULTS.keySet()) {
            record.put(field, SHIPPED_DEFAULTS.get(field));
        }
        return record;
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
        Schema.SObjectType type = settingsType(settingsObject);
        return orgDefault(type).get(fieldFor(type, key));
    }

    /**
     * The Core settings whose blank means "nobody has chosen yet", so the stored value has to
     * stay blank (CoexistenceService reads a blank coexistence mode as unconfirmed and a blank
     * membership mode as the only one detection may change; see `blanksKeptBlank`).
     * Coexistence mode is still shown with the recommended mode selected (see
     * `getEffectiveValue`), nothing stored. The membership mode is shown as stored here: its
     * default is being decided on its own branch. Lower-case field names.
     */
    private static final String COEXISTENCE_FIELD = 'coexistence_mode__c';
    private static final Set<String> SHOWN_AS_STORED = new Set<String>{
        'household_membership_mode__c'
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
     * as stored.
     */
    @NamespaceAccessible
    public static Object getEffectiveValue(String settingsObject, String key, String dataType) {
        Schema.SObjectType type = settingsType(settingsObject);
        Schema.SObjectField field = fieldFor(type, key);
        Object stored = orgDefault(type).get(field);
        Boolean blank =
            stored == null || (stored instanceof String && String.isBlank((String) stored));
        Boolean fillable =
            PICKLIST.equalsIgnoreCase(dataType) ||
            NUMBER_TYPE.equalsIgnoreCase(dataType) ||
            TEXT_TYPE.equalsIgnoreCase(dataType);
        if (!blank || !fillable) {
            return stored;
        }
        String name = field.getDescribe(SObjectDescribeOptions.DEFERRED)
            .getLocalName()
            .toLowerCase();
        if (isCoreSettings(type) && COEXISTENCE_FIELD.equals(name)) {
            return OrgShapeDetector.recommendedCoexistenceMode();
        }
        if (isCoreSettings(type) && SHOWN_AS_STORED.contains(name)) {
            return stored;
        }
        Object declared = type.newSObject(null, true).get(field);
        return declared == null ? stored : declared;
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
     * org-level record.
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
        Schema.SObjectType type = settingsType(settingsObject);
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
                throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
            }
            Object oldValue = record.get(token);
            Object newValue = checkedValue(values.get(key), field, definition);
            String oldText = asText(oldValue);
            String newText = asText(newValue);
            if (oldText.equals(newText)) {
                continue;
            }
            refuseIfMembershipDataWouldBeStranded(token, oldText, newText);
            refuseIfDigestRecipientsAreNotUsers(token, newText);
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
        SettingsWriter.saveOrgDefault(type, storedRecord, changed);
        if (!changes.isEmpty()) {
            Database.insert(changes, AccessLevel.USER_MODE);
        }
        clearCaches();
        return orgDefault(type);
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
     * The error digest goes only to active users of the org (R-E5), so an address that is not
     * one is refused here, where every write of the setting passes, with the addresses named.
     */
    private static void refuseIfDigestRecipientsAreNotUsers(
        Schema.SObjectField token,
        String newText
    ) {
        if (token != BarnCRM_Settings__c.Error_Digest_Recipients__c) {
            return;
        }
        String refusal = ErrorDigestRecipients.refusal(newText);
        if (refusal != null) {
            throw new SettingsException(refusal);
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
        Setting_Definition__mdt definition
    ) {
        try {
            Object newValue = coerce(rawValue, field);
            checkAllowedValue(definition, newValue);
            return newValue;
        } catch (SettingsException refused) {
            if (refused.getMessage() != System.Label.Core_Settings_InvalidValueError) {
                throw refused;
            }
            String name = definition != null && String.isNotBlank(definition.MasterLabel)
                ? definition.MasterLabel
                : field.getLabel();
            throw new SettingsException(
                String.format(
                    System.Label.Core_Settings_ErrorForSetting,
                    new List<Object>{ name, refused.getMessage() }
                )
            );
        }
    }

    /**
     * A picklist row may only be set to one of the choices it ships, so a direct call to the
     * controller cannot store a value the console would never offer.
     */
    private static void checkAllowedValue(Setting_Definition__mdt definition, Object newValue) {
        if (definition == null || newValue == null) {
            return;
        }
        if (RECORD.equalsIgnoreCase(definition.Data_Type__c)) {
            checkRecord(definition, String.valueOf(newValue));
            return;
        }
        if (RECORD_TYPE_LIST.equalsIgnoreCase(definition.Data_Type__c)) {
            checkRecordTypes(definition, String.valueOf(newValue));
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
        throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
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
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
        }
        Decimal low = definition.Min_Value__c;
        Decimal high = definition.Max_Value__c;
        if ((low != null && candidate < low) || (high != null && candidate > high)) {
            throw new SettingsException(
                String.format(
                    System.Label.Core_Settings_NumberOutOfRange,
                    new List<Object>{
                        definition.MasterLabel,
                        low == null ? '' : low.stripTrailingZeros().toPlainString(),
                        high == null ? '' : high.stripTrailingZeros().toPlainString()
                    }
                )
            );
        }
    }

    /** A Record row holds the Id of a record of its own object, and nothing else (ADR-0074). */
    private static void checkRecord(Setting_Definition__mdt definition, String candidate) {
        Schema.SObjectType expected = recordObjectType(definition);
        Id recordId;
        try {
            recordId = Id.valueOf(candidate);
        } catch (Exception notAnId) {
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
        }
        if (expected == null || recordId.getSObjectType() != expected) {
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
        }
    }

    /** A Record Type List row names only record types its object has (ADR-0074). */
    private static void checkRecordTypes(Setting_Definition__mdt definition, String candidate) {
        Set<String> known = new Set<String>();
        for (Schema.RecordTypeInfo info : recordTypes(recordObjectType(definition))) {
            known.add(info.getDeveloperName());
        }
        for (String name : candidate.split(',')) {
            if (String.isNotBlank(name) && !known.contains(name.trim())) {
                throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
            }
        }
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
        for (
            Schema.RecordTypeInfo info : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfos()
        ) {
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
        for (
            Schema.SObjectField field : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            Boolean blank = saved.get(field) == null;
            if (describe.isCustom() && describe.getType() != Schema.DisplayType.BOOLEAN && blank) {
                blanks.put(field, null);
            }
        }
        return blanks;
    }

    /**
     * The record a system mode writer creates when the org has never saved its settings: owned
     * by the org, with the shipped checkbox defaults on it (ADR-0035). Starting from a raw
     * `getOrgDefaults()` instead would store every shipped-on feature as switched off.
     */
    @NamespaceAccessible
    public static BarnCRM_Settings__c firstSaveRecord() {
        return withShippedDefaults(
            new BarnCRM_Settings__c(SetupOwnerId = UserInfo.getOrganizationId())
        );
    }

    /**
     * The same for any settings object. Core's gets `SHIPPED_DEFAULTS`. A module's gets the
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
        if (isCoreSettings(type)) {
            return firstSaveRecord();
        }
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
        if (
            !CORE_SETTINGS_OBJECT.equalsIgnoreCase(name) &&
            !registeredObjects().contains(name.toLowerCase())
        ) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        Schema.SObjectType type = typeByName(name);
        if (type == null) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        if (checkedSettingsTypes.contains(type)) {
            return type;
        }
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!describe.isCustomSetting() || !describe.fields.getMap().containsKey(SETUP_OWNER)) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
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
        cachedOrgDefaults.clear();
    }

    /** The shipped rows for one settings object, by the key each one edits. */
    private static Map<String, Setting_Definition__mdt> definitionsByKey(String objectName) {
        Map<String, Setting_Definition__mdt> rows = new Map<String, Setting_Definition__mdt>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            Boolean sameObject = objectName(definition.Settings_Object__c)
                .equalsIgnoreCase(objectName);
            if (sameObject && String.isNotBlank(definition.Setting_Key__c)) {
                rows.put(definition.Setting_Key__c.trim().toLowerCase(), definition);
            }
        }
        return rows;
    }

    private static Schema.SObjectField fieldFor(Schema.SObjectType type, String key) {
        Schema.SObjectField token = String.isBlank(key)
            ? null
            : fieldsByLocalName(type).get(key.trim().toLowerCase());
        if (token == null) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
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
            return raw instanceof Boolean
                ? (Boolean) raw
                : (String.isBlank(text) ? false : Boolean.valueOf(text));
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
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
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
            throw new SettingsException(System.Label.Core_Settings_InvalidValueError);
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
    private static final Set<String> COEXISTENCE_MODES = new Set<String>{
        'Standalone',
        'NPSP',
        'NonprofitCloud'
    };
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
    public static String coexistenceMode() {
        return storedOrDefault(
            getSettings().Coexistence_Mode__c,
            COEXISTENCE_MODES,
            COEXISTENCE_MODE_DEFAULT
        );
    }

    @NamespaceAccessible
    public static String householdMembershipMode() {
        return storedOrDefault(
            getSettings().Household_Membership_Mode__c,
            MEMBERSHIP_MODES,
            MEMBERSHIP_MODE_DEFAULT
        );
    }
}
