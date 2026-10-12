/**
 * Reads and writes the org's settings.
 *
 * Each package owns a protected hierarchy custom setting (ADR-0017): Core's is
 * `Nonprofit_Settings__c` and a module ships its own, named on its Setting Definition rows.
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
    public static final String CORE_SETTINGS_OBJECT = Nonprofit_Settings__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getLocalName();

    private static final String CACHE_PARTITION = 'local.NonprofitSettings';
    private static final String CACHE_KEY = 'orgDefaults';
    private static final String SETUP_OWNER = 'setupownerid';
    private static final String PICKLIST = 'Picklist';

    /**
     * The Core checkbox settings that ship switched on, and the reason this map has to exist.
     *
     * A checkbox field can declare `<defaultValue>true</defaultValue>`, and that default is what
     * the platform applies when a record is created through the user interface. It is not what
     * Apex reads. `Nonprofit_Settings__c.getOrgDefaults()` on an org that has never saved its
     * settings returns a materialized record with every checkbox false, not null and not the
     * shipped default, so a feature that ships on reads as switched off on every fresh install
     * and does nothing at all, silently. That is what happened to the relationship reciprocal
     * upkeep: C-15 shipped a feature that wrote only the side the person entered.
     *
     * The default is applied to the record only while the org has never saved one. From the
     * first save onwards the stored value governs, including a deliberate false, and the first
     * save carries these defaults into the record it creates, because `applyValues` clones the
     * record this method returns. So an administrator who saves some unrelated setting does not
     * silently switch a shipped feature off.
     *
     * A field belongs here when it ships on. `scripts/ci/check-setting-defaults.py` fails the
     * build when a checkbox that ships on is missing from it (ADR-0035).
     */
    private static final Map<Schema.SObjectField, Boolean> SHIPPED_DEFAULTS = new Map<Schema.SObjectField, Boolean>{
        Nonprofit_Settings__c.Relationship_Auto_Reciprocal__c => true,
        Nonprofit_Settings__c.Auto_Create_Households__c => true
    };

    private static Nonprofit_Settings__c cachedSettings;
    private static Map<String, SObject> cachedOrgDefaults = new Map<String, SObject>();
    private static Map<String, Map<String, Schema.SObjectField>> cachedFields = new Map<String, Map<String, Schema.SObjectField>>();

    /** Raised when a setting does not exist, is not editable here, or the value cannot be read. */
    @NamespaceAccessible
    public class SettingsException extends Exception {
    }

    /**
     * The org-level Core settings record, from the static cache, then the org cache, then the
     * platform. Never null: an org that has never saved gets an empty record carrying the
     * shipped defaults (see `SHIPPED_DEFAULTS`).
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c getSettings() {
        if (cachedSettings != null) {
            return cachedSettings;
        }
        Nonprofit_Settings__c fromCache = readCache();
        if (fromCache != null) {
            cachedSettings = fromCache;
            return cachedSettings;
        }
        cachedSettings = withShippedDefaults(Nonprofit_Settings__c.getOrgDefaults());
        writeCache(cachedSettings);
        return cachedSettings;
    }

    /**
     * Puts the shipped defaults on a settings record the org has never saved, and leaves a saved
     * record exactly as the org left it. An unsaved hierarchy custom setting has no Id, which is
     * what tells the two apart.
     */
    private static Nonprofit_Settings__c withShippedDefaults(Nonprofit_Settings__c record) {
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
        Schema.SObjectType type = Schema.getGlobalDescribe().get(objectName(settingsObject));
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
     * Saves the given Core values, keyed by the API name of the Nonprofit Settings field.
     * Only keys that exist on the object and are listed in a Setting Definition row are
     * accepted. Returns the refreshed Core settings.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c saveValues(Map<String, Object> values) {
        applyValues(CORE_SETTINGS_OBJECT, values, true);
        return getSettings();
    }

    /**
     * Saves the given values on the named settings object. The object has to be a hierarchy
     * custom setting named by at least one shipped Setting Definition row. Returns the saved
     * org-level record.
     */
    @NamespaceAccessible
    public static SObject saveValues(String settingsObject, Map<String, Object> values) {
        return applyValues(settingsObject, values, true);
    }

    /**
     * Saves one value the package itself owns, such as the setup checklist progress,
     * which has no Setting Definition row because it is not an editable setting.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c saveSystemValue(String key, Object value) {
        applyValues(CORE_SETTINGS_OBJECT, new Map<String, Object>{ key => value }, false);
        return getSettings();
    }

    private static SObject applyValues(
        String settingsObject,
        Map<String, Object> values,
        Boolean requireDefinition
    ) {
        Schema.SObjectType type = settingsType(settingsObject);
        SObject record = orgDefault(type);
        if (values == null || values.isEmpty()) {
            return record;
        }
        String objectName = localName(type);
        Map<String, Setting_Definition__mdt> rows = definitionsByKey(objectName);
        record = record.clone(true, true, true, true);
        if (record.Id == null) {
            record.put(SETUP_OWNER, UserInfo.getOrganizationId());
        }
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
            Object newValue = coerce(values.get(key), field);
            checkAllowedValue(definition, newValue);
            String oldText = asText(oldValue);
            String newText = asText(newValue);
            if (oldText.equals(newText)) {
                continue;
            }
            refuseIfMembershipDataWouldBeStranded(token, oldText, newText);
            refuseIfDigestRecipientsAreNotUsers(token, newText);
            record.put(token, newValue);
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
        if (changes.isEmpty()) {
            return record;
        }
        Boolean firstSave = record.Id == null;
        SettingsWriter.saveOrgDefault(record);
        if (firstSave && isCoreSettings(type)) {
            SettingsWriter.saveOrgDefault(blanksKeptBlank(type, record));
        }
        Database.insert(changes, AccessLevel.USER_MODE);
        clearCaches();
        return record;
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
        if (token != Nonprofit_Settings__c.Household_Membership_Mode__c) {
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
        if (token != Nonprofit_Settings__c.Error_Digest_Recipients__c) {
            return;
        }
        String refusal = ErrorDigestRecipients.refusal(newText);
        if (refusal != null) {
            throw new SettingsException(refusal);
        }
    }

    /**
     * A picklist row may only be set to one of the choices it ships, so a direct call to the
     * controller cannot store a value the console would never offer.
     */
    private static void checkAllowedValue(Setting_Definition__mdt definition, Object newValue) {
        if (
            definition == null ||
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
     * The org-level record of the given settings object, never null, read once per transaction
     * per object so a console holding many modules' settings does not query per row.
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
        SObject resolved = record == null ? type.newSObject() : record;
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
    public static Nonprofit_Settings__c firstSaveRecord() {
        return withShippedDefaults(
            new Nonprofit_Settings__c(SetupOwnerId = UserInfo.getOrganizationId())
        );
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
        return type == Nonprofit_Settings__c.SObjectType;
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
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!describe.isCustomSetting() || !describe.fields.getMap().containsKey(SETUP_OWNER)) {
            throw new SettingsException(System.Label.Core_Settings_UnknownKeyError);
        }
        return type;
    }

    private static String objectName(String settingsObject) {
        return String.isBlank(settingsObject) ? CORE_SETTINGS_OBJECT : settingsObject.trim();
    }

    /**
     * The object with this API name, whether or not a namespace is in front of it. Metadata rows
     * name objects without a prefix, and a packaged org's describe keys carry one, so an exact
     * match is tried first and then a match on the part after the namespace.
     */
    @NamespaceAccessible
    public static Schema.SObjectType typeByName(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        Map<String, Schema.SObjectType> globals = Schema.getGlobalDescribe();
        String name = apiName.trim();
        Schema.SObjectType type = globals.get(name);
        if (type != null) {
            return type;
        }
        String suffix = '__' + name.toLowerCase();
        for (String key : globals.keySet()) {
            if (key.toLowerCase().endsWith(suffix)) {
                return globals.get(key);
            }
        }
        return null;
    }

    private static Set<String> registeredObjects() {
        Set<String> names = new Set<String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            names.add(objectName(definition.Settings_Object__c).toLowerCase());
        }
        return names;
    }

    /**
     * Forgets the cached settings, so the next read comes from the platform. Every writer of a
     * settings object, in any package, calls this after it writes.
     */
    @NamespaceAccessible
    public static void clearCaches() {
        cachedSettings = null;
        cachedOrgDefaults.clear();
        Cache.OrgPartition partition = partition();
        if (partition == null) {
            return;
        }
        try {
            partition.remove(CACHE_KEY);
        } catch (Exception e) {
            ErrorLogger.log(e, 'Open Impact Settings cache');
        }
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
        Schema.DescribeSObjectResult describe = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        String name = describe.getName();
        if (cachedFields.containsKey(name)) {
            return cachedFields.get(name);
        }
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
        if (value instanceof Datetime) {
            return ((Datetime) value).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        return String.valueOf(value);
    }

    private static Cache.OrgPartition partition() {
        try {
            return Cache.Org.getPartition(CACHE_PARTITION);
        } catch (Exception e) {
            return null;
        }
    }

    private static Nonprofit_Settings__c readCache() {
        Cache.OrgPartition partition = partition();
        if (partition == null) {
            return null;
        }
        try {
            return (Nonprofit_Settings__c) partition.get(CACHE_KEY);
        } catch (Exception e) {
            return null;
        }
    }

    private static void writeCache(Nonprofit_Settings__c record) {
        Cache.OrgPartition partition = partition();
        if (partition == null || record == null) {
            return;
        }
        try {
            partition.put(CACHE_KEY, record);
        } catch (Exception e) {
            ErrorLogger.log(e, 'Open Impact Settings cache');
        }
    }

    @NamespaceAccessible
    public static final String COEXISTENCE_MODE_DEFAULT = 'Standalone';
    @NamespaceAccessible
    public static final String MEMBERSHIP_MODE_DEFAULT = 'Contact';

    private static final Set<String> COEXISTENCE_MODES = new Set<String>{
        'Standalone',
        'NPSP',
        'AgentforceNonprofit'
    };
    private static final Set<String> MEMBERSHIP_MODES = new Set<String>{ 'Contact', 'Junction' };

    private static String storedOrDefault(String stored, Set<String> allowed, String fallback) {
        return String.isNotBlank(stored) && allowed.contains(stored) ? stored : fallback;
    }

    /**
     * A fresh copy of the org level settings to write to. Never the cached instance, so that a
     * failed write cannot leave a half-changed value in this transaction's cache.
     */
    @NamespaceAccessible
    public static Nonprofit_Settings__c getSettingsForUpdate() {
        return Nonprofit_Settings__c.getOrgDefaults();
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

    /**
     * Checks a value on its way in. Anything outside the allowed list is refused with a message
     * the console can show.
     */
    @NamespaceAccessible
    public static String validated(String value, Set<String> allowed) {
        if (allowed == null || String.isBlank(value) || !allowed.contains(value)) {
            throw new SettingsServiceException(Label.Core_Settings_ModeValueInvalid);
        }
        return value;
    }

    /**
     * Alias kept for callers written against the Core-only service (C-04). Clears every
     * cached settings record, whichever package owns the object.
     */
    @NamespaceAccessible
    public static void clearCache() {
        clearCaches();
    }

    @NamespaceAccessible
    public static Set<String> coexistenceModes() {
        return COEXISTENCE_MODES.clone();
    }

    @NamespaceAccessible
    public static Set<String> membershipModes() {
        return MEMBERSHIP_MODES.clone();
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

    @NamespaceAccessible
    public class SettingsServiceException extends Exception {
    }
}
