/**
 * The BarnCRM Settings console's Apex surface: what to render, what the values are,
 * whether this user may change them, what a search matches, and what changed recently.
 */
@NamespaceAccessible
public with sharing class SettingsController {
    private static final String EDIT_PERMISSION = 'Manage_BarnCRM_Settings';
    private static final String HELP_BASE = 'https://github.com/Nonprofit-Collaborative/BarnCRM/blob/main/docs/admin-guide/';
    private static final String TYPE_COMPONENT = 'Component';
    private static final String TYPE_CHECKBOX = 'Checkbox';
    private static final String TYPE_PICKLIST = 'Picklist';
    /** A value Setup holds, shown read only and never saved (ADR-0135). */
    private static final String TYPE_SETUP_VALUE = 'SetupValue';
    private static final String ERROR_CONTEXT = 'BarnCRM Settings console';
    /** The module a Setting Definition row belongs to when it names none. */
    private static final String CORE_MODULE = 'Core';
    /** The Setup prerequisites the console can check, by the key settingsSetupNotes reads. */
    @TestVisible
    private static final String CHECK_EMAIL = 'emailDeliverability';
    @TestVisible
    private static final String CHECK_METADATA = 'metadata';
    private static final String METADATA_PERMISSION = 'Manage_BarnCRM_Metadata';

    /**
     * Core picklist settings whose blank means a choice, by key in lower case, with the value
     * a blank is shown as. Every reader already treats the blank as that choice, so the console
     * shows it rather than an empty box (Address Updates, ADR-0140). A blank that means
     * "nobody has chosen yet", such as the coexistence mode, is not listed here.
     */
    private static final Map<String, String> BLANK_SHOWS_AS = new Map<String, String>{
        'contact_address_change_behavior__c' => 'Update household'
    };

    /** Injected by the tests: Deliverability cannot be changed from Apex. */
    @TestVisible
    private static Boolean emailAllowedOverride;

    // A module test saves across modules (ConsoleSaveAcrossModulesTest), so the two models it
    // reads are reachable from another package; an @AuraEnabled field is read by its getter.
    @NamespaceAccessible
    public class ConsoleModel {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<SectionModel> sections;

        @NamespaceAccessible
        public Boolean getCanEdit() {
            return canEdit;
        }
    }

    public class SectionModel {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<SettingModel> settings;
    }

    public class SettingModel {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String dataType;
        @AuraEnabled
        public String section;
        @AuraEnabled
        public String settingsObject;
        /** The module the row belongs to (Core when the row names none), for a module's page. */
        @AuraEnabled
        public String module;
        @AuraEnabled
        public String component;
        @AuraEnabled
        public String navigationTarget;
        /** The name of the page the target opens, for the button's label. */
        @AuraEnabled
        public String navigationLabel;
        @AuraEnabled
        public String helpUrl;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public Boolean checked;
        @AuraEnabled
        public List<Option> options;
        /** The object a Record row picks from, with this org's namespace (ADR-0074). */
        @AuraEnabled
        public String objectApiName;
        /** A Number row's range, which the console marks and the server enforces (ADMIN-27). */
        @AuraEnabled
        public Decimal minValue;
        @AuraEnabled
        public Decimal maxValue;
        /**
         * True when the value shown is a default nobody has saved: nothing is stored, so the
         * console offers to keep the shown value as a saved choice. Saving it stores exactly
         * that value through `saveSettings`, a real change from the stored blank.
         */
        @AuraEnabled
        public Boolean unsavedDefault;
        /**
         * True when an unsaved default is one BarnCRM's own detection would replace (the
         * household membership mode on an org with Person Accounts or Nonprofit Cloud), so the
         * console shows the note but offers no one-click keep.
         */
        @AuraEnabled
        public Boolean detectionMayChange;
        /**
         * What a blank Text row means, shown in the empty box with the Default badge: "Not set"
         * for an organization detail nothing fills in, or what the blank does (the error digest
         * goes to every settings administrator). It is not a value: nothing is offered to keep.
         */
        @AuraEnabled
        public String defaultText;
        /**
         * A value Salesforce's Company Information holds for a blank row (the legal name), which
         * the console offers to fill in. Nothing uses it until it is saved.
         */
        @AuraEnabled
        public String suggestedValue;
    }

    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    public class SearchHit {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String section;
    }

    @NamespaceAccessible
    public class ChangeModel {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String settingName;
        @AuraEnabled
        public String oldValue;
        @AuraEnabled
        public String newValue;
        @AuraEnabled
        public String changedBy;
        @AuraEnabled
        public Datetime changedAt;

        @NamespaceAccessible
        public String getSettingName() {
            return settingName;
        }
    }

    // Not cacheable: the console calls it again after a save, and a cached answer would show
    // the values from before the save (ADR-0093, record reads through Lightning Data Service).
    @AuraEnabled
    public static ConsoleModel getConsoleModel() {
        try {
            return buildModel();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_Settings_LoadErrorMessage);
        }
    }

    /**
     * `saveSettings` for another package (ConsoleSaveAcrossModulesTest): the platform rejects
     * `@NamespaceAccessible` on an `@AuraEnabled` method.
     */
    @NamespaceAccessible
    public static ConsoleModel save(Map<String, Object> values) {
        return saveSettings(values);
    }

    @AuraEnabled
    public static ConsoleModel saveSettings(Map<String, Object> values) {
        if (values == null || values.isEmpty()) {
            return getConsoleModel();
        }
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
        try {
            Map<String, Map<String, Object>> byObject = groupByObject(values);
            for (String settingsObject : byObject.keySet()) {
                SettingsService.saveValues(settingsObject, byObject.get(settingsObject));
            }
            return buildModel();
        } catch (SettingsService.SettingsException e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_Settings_SaveErrorMessage);
        }
    }

    /**
     * The saved organization address, one entry per part keyed by its settings field name, for
     * the address block in the console (a Component row). Saving goes through `saveSettings`.
     * Not cacheable, for the reason `getConsoleModel` is not.
     */
    @AuraEnabled
    public static Map<String, String> getOrganizationAddress() {
        try {
            return OrganizationAddress.savedParts();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_OrganizationAddress_LoadError);
        }
    }

    /** Where a link to a console section goes: the settings tab and the section state key. */
    public class SettingsLink {
        @AuraEnabled
        public String tabApiName;
        @AuraEnabled
        public String sectionKey;
    }

    /**
     * The names a page reference to a console section needs, qualified for this org, so no
     * component writes a literal tab name or `c__section` (the key is `<ns>__section` once
     * a namespace exists).
     */
    @AuraEnabled(cacheable=true)
    public static SettingsLink getSettingsLink() {
        SettingsLink link = new SettingsLink();
        link.tabApiName = NamespaceUtil.qualify(HealthCheckService.SETTINGS_TAB);
        link.sectionKey = NamespaceUtil.stateKey(HealthCheckService.SECTION_STATE_PARAMETER);
        return link;
    }

    @AuraEnabled(cacheable=true)
    public static List<SearchHit> search(String term) {
        List<SearchHit> hits = new List<SearchHit>();
        if (String.isBlank(term)) {
            return hits;
        }
        String needle = term.trim().toLowerCase();
        try {
            for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
                if (!matches(definition, needle)) {
                    continue;
                }
                // The console's own test for showing a row, so search never lists a row the
                // page hides (ADMIN-21).
                SettingModel shown = toSetting(definition);
                if (shown == null) {
                    continue;
                }
                SearchHit hit = new SearchHit();
                hit.key = shown.key;
                hit.label = shown.label;
                hit.section = shown.section;
                hits.add(hit);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_Settings_LoadErrorMessage);
        }
        return hits;
    }

    // Not cacheable: the console calls it again right after a save, and a cached answer would
    // show the rows from before the save (ADMIN-14).

    @AuraEnabled
    public static List<ChangeModel> getRecentChanges(Integer limitCount) {
        List<ChangeModel> changes = new List<ChangeModel>();
        try {
            Map<String, String> labels = labelsByStoredName();
            Map<String, Map<String, String>> choices = choiceLabelsByStoredName();
            List<Setting_Change__c> recent = SettingChangeSelector.getRecent(limitCount);
            Set<String> recordSettings = recordSettingsByStoredName();
            Map<Id, String> recordNames = recordNamesFor(recent, recordSettings);
            for (Setting_Change__c record : recent) {
                ChangeModel change = new ChangeModel();
                change.id = record.Id;
                String stored = record.Setting_Name__c == null
                    ? ''
                    : record.Setting_Name__c.toLowerCase();
                change.settingName = labels.containsKey(stored)
                    ? labels.get(stored)
                    : record.Setting_Name__c;
                change.oldValue = shownValue(record.Old_Value__c, choices.get(stored));
                change.newValue = shownValue(record.New_Value__c, choices.get(stored));
                if (stored == featuresStoredName()) {
                    change.settingName = System.Label.Core_Settings_FeaturesTurnedOn;
                    change.oldValue = shownFeatures(record.Old_Value__c);
                    change.newValue = shownFeatures(record.New_Value__c);
                }
                if (recordSettings.contains(stored)) {
                    change.oldValue = shownRecordName(record.Old_Value__c, recordNames);
                    change.newValue = shownRecordName(record.New_Value__c, recordNames);
                }
                if (String.isNotBlank(change.oldValue) && change.oldValue == change.newValue) {
                    // Both sides read the same on screen (for example two raw values that both
                    // show as "No features"), so the row would look like a change that did not happen.
                    continue;
                }
                change.changedBy = record.Changed_By__r == null ? null : record.Changed_By__r.Name;
                change.changedAt = record.Changed_At__c;
                changes.add(change);
            }
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_Settings_LoadErrorMessage);
        }
        return changes;
    }

    /**
     * Each setting's label by the name an audit row stores ("BarnCRM_Settings__c.Key__c",
     * lower case), so Recent changes reads "Household naming pattern", not an API name
     * (ADMIN-20). A row that names something else, such as a Health Check fix, is shown as stored.
     */
    private static Map<String, String> labelsByStoredName() {
        Map<String, String> labels = new Map<String, String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            if (String.isNotBlank(definition.Setting_Key__c)) {
                labels.put(storedNameOf(definition), definition.MasterLabel);
            }
        }
        return labels;
    }

    /**
     * Each choice setting's labels by stored value (lower case), keyed like
     * `labelsByStoredName`, so Recent Changes shows what the setting's own picker shows: the
     * Edition row reads "Nonprofit Edition", not the stored code "Nonprofit". Translated when read,
     * so rows logged before a label changed read the current label too.
     */
    private static Map<String, Map<String, String>> choiceLabelsByStoredName() {
        Map<String, Map<String, String>> choices = new Map<String, Map<String, String>>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            Map<String, String> byValue = new Map<String, String>();
            for (Option option : toOptions(definition)) {
                byValue.put(option.value.toLowerCase(), option.label);
            }
            if (String.isNotBlank(definition.Setting_Key__c) && !byValue.isEmpty()) {
                choices.put(storedNameOf(definition), byValue);
            }
        }
        // The Edition row is a component with its own picker, which names the stored codes with
        // these labels (editionSetting). Rows logged before ADR-0143 hold the old codes, which
        // read as the editions that replaced them.
        Map<String, String> editionLabels = new Map<String, String>{
            ModuleDetectionService.SUITE_STANDARD.toLowerCase() => System.Label.Core_SuiteChoice_StandardName,
            ModuleDetectionService.SUITE_NONPROFIT.toLowerCase() => System.Label.Core_SuiteChoice_NonprofitName
        };
        for (String oldValue : ModuleDetectionService.SUITE_BY_OLD_VALUE.keySet()) {
            String renamed = ModuleDetectionService.SUITE_BY_OLD_VALUE.get(oldValue);
            editionLabels.put(oldValue, editionLabels.get(renamed.toLowerCase()));
        }
        choices.put(
            (SettingsService.CORE_SETTINGS_OBJECT + '.Suite__c').toLowerCase(),
            editionLabels
        );
        // A Record Type row logs the record type's API name; it reads as the record type's label.
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            if (
                String.isBlank(definition.Setting_Key__c) ||
                !SettingsService.RECORD_TYPE.equalsIgnoreCase(definition.Data_Type__c)
            ) {
                continue;
            }
            Schema.SObjectType type = SettingsService.recordObjectType(definition);
            if (type == null) {
                continue;
            }
            Map<String, String> byName = new Map<String, String>{
                AccountKinds.NO_RECORD_TYPE.toLowerCase() => System.Label.Core_Settings_NoRecordType
            };
            for (
                Schema.RecordTypeInfo info : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .getRecordTypeInfos()
            ) {
                if (!info.isMaster()) {
                    byName.put(info.getDeveloperName().toLowerCase(), info.getName());
                }
            }
            choices.put(storedNameOf(definition), byName);
        }
        return choices;
    }

    /** The stored names (lower case) of the settings that hold one record's Id, such as the default fund. */
    private static Set<String> recordSettingsByStoredName() {
        Set<String> stored = new Set<String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            if (
                String.isNotBlank(definition.Setting_Key__c) &&
                SettingsService.RECORD.equalsIgnoreCase(definition.Data_Type__c)
            ) {
                stored.add(storedNameOf(definition));
            }
        }
        return stored;
    }

    /**
     * The names of the records that Record settings logged, by Id, read now so a renamed record
     * reads its current name. A record the user cannot read, or that is gone, is left out and
     * shows as the plain fallback (Core_Settings_RecordUnavailable).
     */
    private static Map<Id, String> recordNamesFor(
        List<Setting_Change__c> changes,
        Set<String> recordSettings
    ) {
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();
        for (Setting_Change__c change : changes) {
            if (
                change.Setting_Name__c == null ||
                !recordSettings.contains(change.Setting_Name__c.toLowerCase())
            ) {
                continue;
            }
            for (String value : new List<String>{ change.Old_Value__c, change.New_Value__c }) {
                Id recordId = asId(value);
                if (recordId != null) {
                    Schema.SObjectType type = recordId.getSobjectType();
                    if (!idsByType.containsKey(type)) {
                        idsByType.put(type, new Set<Id>());
                    }
                    idsByType.get(type).add(recordId);
                }
            }
        }
        Map<Id, String> names = new Map<Id, String>();
        for (Schema.SObjectType type : idsByType.keySet()) {
            try {
                String query =
                    'SELECT Id, Name FROM ' +
                    type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
                    ' WHERE Id IN :ids';
                for (
                    SObject record : Database.queryWithBinds(
                        query,
                        new Map<String, Object>{ 'ids' => idsByType.get(type) },
                        AccessLevel.USER_MODE
                    )
                ) {
                    names.put(record.Id, (String) record.get('Name'));
                }
            } catch (Exception e) {
                // An object with no Name field or no read access: its rows show the plain fallback.
                continue;
            }
        }
        return names;
    }

    /**
     * A logged Id as its record's name when the record is still readable, otherwise a plain
     * fallback: never a raw Id.
     */
    private static String shownRecordName(String stored, Map<Id, String> names) {
        Id recordId = asId(stored);
        if (recordId == null) {
            return stored;
        }
        return names.containsKey(recordId)
            ? names.get(recordId)
            : System.Label.Core_Settings_RecordUnavailable;
    }

    private static Id asId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value.trim());
        } catch (Exception e) {
            return null;
        }
    }

    /** The name an audit row stores for a definition's setting, in lower case. */
    private static String storedNameOf(Setting_Definition__mdt definition) {
        String settingsObject = String.isBlank(definition.Settings_Object__c)
            ? SettingsService.CORE_SETTINGS_OBJECT
            : definition.Settings_Object__c.trim();
        return (settingsObject + '.' + definition.Setting_Key__c.trim()).toLowerCase();
    }

    /** The name an audit row stores for the features-turned-on list, in lower case. */
    private static String featuresStoredName() {
        String field = '.Features_Turned_On__c';
        return (SettingsService.CORE_SETTINGS_OBJECT + field).toLowerCase();
    }

    /**
     * The Features row logs the stored key list ("DataManager,Addresses", or "None" before
     * first-run setup). It reads as the features' names, or "No features" for none.
     */
    private static String shownFeatures(String stored) {
        if (String.isBlank(stored)) {
            return stored;
        }
        List<String> names = new List<String>();
        for (String part : stored.split(',')) {
            String key = part.trim();
            if (
                String.isBlank(key) ||
                key == FeatureSwitchService.NONE_ON ||
                key == FeatureSwitchService.NONE_CHOSEN
            ) {
                continue;
            }
            names.add(FeatureController.nameOf(key));
        }
        return names.isEmpty() ? System.Label.Core_Settings_NoFeaturesOn : String.join(names, ', ');
    }

    /** A logged value as its choice's label when it is one, otherwise as stored. */
    private static String shownValue(String stored, Map<String, String> byValue) {
        if (stored == null || byValue == null) {
            return stored;
        }
        String label = byValue.get(stored.trim().toLowerCase());
        return label == null ? stored : label;
    }

    /**
     * Splits what the page sent into one map per settings object, because each package owns
     * its own settings object (ADR-0017). A key with no shipped row is left with Core, whose
     * service refuses it by name.
     */
    private static Map<String, Map<String, Object>> groupByObject(Map<String, Object> values) {
        Map<String, String> objectByKey = new Map<String, String>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            if (String.isNotBlank(definition.Setting_Key__c)) {
                objectByKey.put(
                    definition.Setting_Key__c.trim().toLowerCase(),
                    String.isBlank(definition.Settings_Object__c)
                        ? SettingsService.CORE_SETTINGS_OBJECT
                        : definition.Settings_Object__c.trim()
                );
            }
        }
        Map<String, Map<String, Object>> byObject = new Map<String, Map<String, Object>>();
        for (String key : values.keySet()) {
            String settingsObject = objectByKey.get(key == null ? '' : key.trim().toLowerCase());
            if (settingsObject == null) {
                settingsObject = SettingsService.CORE_SETTINGS_OBJECT;
            }
            if (!byObject.containsKey(settingsObject)) {
                byObject.put(settingsObject, new Map<String, Object>());
            }
            byObject.get(settingsObject).put(key, values.get(key));
        }
        return byObject;
    }

    private static Boolean matches(Setting_Definition__mdt definition, String needle) {
        List<String> parts = new List<String>();
        for (
            String part : new List<String>{
                definition.MasterLabel,
                definition.Description__c,
                definition.Section__c,
                // The page the row shows on, when its section names a sub-section (P1).
                SettingSections.pageFor(definition.Section__c),
                definition.Setting_Key__c
            }
        ) {
            if (String.isNotBlank(part)) {
                parts.add(part);
            }
        }
        return String.join(parts, ' ').toLowerCase().contains(needle);
    }

    private static ConsoleModel buildModel() {
        ConsoleModel model = new ConsoleModel();
        model.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        model.sections = new List<SectionModel>();
        Map<String, SectionModel> sectionsByName = new Map<String, SectionModel>();
        for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
            SettingModel setting;
            try {
                setting = toSetting(definition);
            } catch (Exception e) {
                // A module's settings object this user cannot read costs the console that row,
                // not the page (plan Section 9.4, degrade gracefully when a module is off).
                ErrorLogger.log(e, ERROR_CONTEXT);
                continue;
            }
            if (setting == null) {
                continue;
            }
            SectionModel section = sectionsByName.get(setting.section);
            if (section == null) {
                section = new SectionModel();
                section.name = setting.section;
                section.settings = new List<SettingModel>();
                sectionsByName.put(section.name, section);
                model.sections.add(section);
            }
            section.settings.add(setting);
        }
        model.sections = inShippedOrder(model.sections);
        return model;
    }

    /**
     * Sections in the order SettingSections.all() gives, so the console opens on General
     * (ADMIN-6). A section no package declared there keeps its place after the known ones.
     */
    private static List<SectionModel> inShippedOrder(List<SectionModel> sections) {
        Map<String, Integer> rank = new Map<String, Integer>();
        List<String> shipped = SettingSections.all();
        for (Integer i = 0; i < shipped.size(); i++) {
            rank.put(shipped[i].deleteWhitespace().toLowerCase(), i);
        }
        List<List<SectionModel>> slots = new List<List<SectionModel>>();
        for (Integer i = 0; i <= shipped.size(); i++) {
            slots.add(new List<SectionModel>());
        }
        for (SectionModel section : sections) {
            String name = section.name == null ? '' : section.name.deleteWhitespace().toLowerCase();
            Integer slot = rank.containsKey(name) ? rank.get(name) : shipped.size();
            slots[slot].add(section);
        }
        List<SectionModel> ordered = new List<SectionModel>();
        for (List<SectionModel> slot : slots) {
            ordered.addAll(slot);
        }
        return ordered;
    }

    /**
     * A row naming a custom permission is only for those who hold it (ADR-0038 point 3). The name
     * is stored without a prefix: tried as given, then with this package's namespace, and a name
     * found neither way hides the row.
     */
    private static Boolean isVisible(Setting_Definition__mdt definition) {
        if (String.isBlank(definition.Required_Permission__c)) {
            return true;
        }
        String name = definition.Required_Permission__c.trim();
        if (FeatureManagement.checkPermission(name)) {
            return true;
        }
        String prefix = NamespaceUtil.prefix();
        return !name.contains('__') &&
            String.isNotBlank(prefix) &&
            FeatureManagement.checkPermission(prefix + name);
    }

    /** The rows of the Core features that are off, read once per transaction (ADR-0124). */
    private static Set<String> hiddenByFeature;

    private static Boolean isHiddenByFeature(Setting_Definition__mdt definition) {
        if (hiddenByFeature == null) {
            hiddenByFeature = FeatureSwitchService.hiddenSettingRows();
        }
        return hiddenByFeature.contains(definition.DeveloperName);
    }

    private static SettingModel toSetting(Setting_Definition__mdt definition) {
        if (!isVisible(definition) || isHiddenByFeature(definition)) {
            return null;
        }
        Boolean isComponent = TYPE_COMPONENT.equalsIgnoreCase(definition.Data_Type__c);
        Boolean isSetupValue = TYPE_SETUP_VALUE.equalsIgnoreCase(definition.Data_Type__c);
        String settingsObject = String.isBlank(definition.Settings_Object__c)
            ? SettingsService.CORE_SETTINGS_OBJECT
            : definition.Settings_Object__c.trim();
        Boolean exists = isSetupValue
            ? SetupValueSelector.supports(settingsObject, definition.Setting_Key__c)
            : isComponent || SettingsService.hasKey(settingsObject, definition.Setting_Key__c);
        if (!exists) {
            return null;
        }
        SettingModel setting = new SettingModel();
        setting.settingsObject = settingsObject;
        setting.module = String.isBlank(definition.Module__c)
            ? CORE_MODULE
            : definition.Module__c.trim();
        setting.key = isComponent ? definition.DeveloperName : definition.Setting_Key__c;
        setting.label = definition.MasterLabel;
        setting.description = definition.Description__c;
        setting.dataType = definition.Data_Type__c;
        setting.minValue = definition.Min_Value__c;
        setting.maxValue = definition.Max_Value__c;
        // A row that still names the old Households or Relationships page shows on People and
        // Households (P1), so a module or a row not yet moved never makes a page of its own.
        setting.section = String.isBlank(definition.Section__c)
            ? ''
            : SettingSections.pageFor(definition.Section__c);
        setting.component = definition.Component__c;
        setting.navigationTarget = definition.Navigation_Target__c;
        setting.navigationLabel = definition.Navigation_Label__c;
        setting.helpUrl = String.isBlank(definition.Help_Path__c)
            ? null
            : HELP_BASE + definition.Help_Path__c;
        setting.options = toOptions(definition);
        if (!addRecordChoices(definition, setting)) {
            return null;
        }
        if (isCoexistenceMode(settingsObject, definition.Setting_Key__c)) {
            setting.options = offeredModesOnly(setting.options);
        }
        if (isComponent) {
            setting.checked = false;
            return setting;
        }
        if (isSetupValue) {
            // Shown, never saved: Setup holds it and BarnCRM keeps no copy (ADR-0135).
            setting.value = SetupValueSelector.valueOf(settingsObject, definition.Setting_Key__c);
            setting.checked = false;
            return setting;
        }
        Object value = SettingsService.getEffectiveValue(
            settingsObject,
            definition.Setting_Key__c,
            definition.Data_Type__c
        );
        setting.value = SettingsService.asText(value);
        if (isOrganizationRecordType(settingsObject, definition.Setting_Key__c)) {
            // Never blank: the stored record type, or the one detection picks while nothing
            // usable is stored (R-O5). Showing it is not saving it; install stores it.
            setting.value = AccountKinds.organizationRecordTypeName();
        } else if (isMembershipMode(settingsObject, definition.Setting_Key__c)) {
            // Blank means nobody has chosen yet, and every reader treats it as the simple way,
            // so the console shows that way as selected. Showing it is not saving it: the
            // stored value stays blank, which is what lets detection still propose the
            // flexible way for an org with Person Accounts or Nonprofit Cloud.
            setting.value = SettingsService.householdMembershipMode();
        } else if (
            String.isBlank(setting.value) &&
            SettingsService.CORE_SETTINGS_OBJECT.equalsIgnoreCase(settingsObject)
        ) {
            String key = definition.Setting_Key__c == null
                ? ''
                : definition.Setting_Key__c.toLowerCase();
            setting.value = BLANK_SHOWS_AS.containsKey(key)
                ? BLANK_SHOWS_AS.get(key)
                : setting.value;
        }
        Boolean isCheckbox = TYPE_CHECKBOX.equalsIgnoreCase(definition.Data_Type__c);
        setting.checked = isCheckbox && value == true;
        // A checkbox is never blank (its shipped value is on the record, ADR-0035).
        setting.unsavedDefault =
            !isCheckbox &&
            String.isNotBlank(setting.value) &&
            String.isBlank(
                SettingsService.asText(
                    SettingsService.getValue(settingsObject, definition.Setting_Key__c)
                )
            );
        String detected = setting.unsavedDefault
            ? detectedValue(settingsObject, definition.Setting_Key__c)
            : null;
        setting.detectionMayChange = detected != null && !detected.equals(setting.value);
        describeBlankText(definition, settingsObject, setting);
        return setting;
    }

    private static final String TYPE_TEXT = 'Text';
    private static final String DIGEST_RECIPIENTS = 'Error_Digest_Recipients__c';
    private static final String LEGAL_NAME = 'Organization_Legal_Name__c';

    /**
     * Never a blank box with nothing said: a blank Text row of BarnCRM's own settings, or of the
     * Organization page, shows what the blank means as its default. Only those rows: a module's
     * other blank rows mean something of their own, which only that module can say.
     */
    private static void describeBlankText(
        Setting_Definition__mdt definition,
        String settingsObject,
        SettingModel setting
    ) {
        Boolean organizationPage = SettingSections.ORGANIZATION.equalsIgnoreCase(
            definition.Section__c == null ? '' : definition.Section__c.trim()
        );
        if (
            !TYPE_TEXT.equalsIgnoreCase(definition.Data_Type__c) ||
            String.isNotBlank(setting.value) ||
            !(organizationPage ||
            SettingsService.CORE_SETTINGS_OBJECT.equalsIgnoreCase(settingsObject))
        ) {
            return;
        }
        String key = definition.Setting_Key__c;
        setting.unsavedDefault = true;
        setting.defaultText = DIGEST_RECIPIENTS.equalsIgnoreCase(key)
            ? System.Label.Core_Settings_DigestRecipientsDefault
            : System.Label.Core_Settings_NotSet;
        if (LEGAL_NAME.equalsIgnoreCase(key)) {
            setting.suggestedValue = CompanyInformation.name();
        }
    }

    /**
     * The Company Information address as organization address parts, offered by the address
     * panel while no organization address is saved; empty unless it is complete (R-OA1).
     */
    @AuraEnabled
    public static Map<String, String> getCompanyAddress() {
        try {
            return CompanyInformation.addressParts();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_OrganizationAddress_LoadError);
        }
    }

    /**
     * What BarnCRM's own detection would write for an unsaved row, or null for a row detection
     * never writes. The coexistence mode is shown as the recommended mode, which is what
     * detection writes; the membership mode is shown as the simple way, which detection
     * replaces on an org with Person Accounts or Nonprofit Cloud.
     */
    private static String detectedValue(String settingsObject, String key) {
        if (isCoexistenceMode(settingsObject, key)) {
            return OrgShapeDetector.recommendedCoexistenceMode();
        }
        if (isMembershipMode(settingsObject, key)) {
            return CoexistenceService.membershipDetectionWouldChoose();
        }
        return null;
    }

    /**
     * Gives a Record row its object and a Record Type, Record Type List or Field List row its
     * choices, read from describe (ADR-0074, R-AD10, ADR-0141). False when the row names an
     * object this org does not have, which leaves the row out as a missing settings object does.
     */
    private static Boolean addRecordChoices(
        Setting_Definition__mdt definition,
        SettingModel setting
    ) {
        Boolean isRecord = SettingsService.RECORD.equalsIgnoreCase(definition.Data_Type__c);
        Boolean isRecordType = SettingsService.RECORD_TYPE.equalsIgnoreCase(
            definition.Data_Type__c
        );
        Boolean isRecordTypes = SettingsService.RECORD_TYPE_LIST.equalsIgnoreCase(
            definition.Data_Type__c
        );
        Boolean isFields = SettingsService.FIELD_LIST.equalsIgnoreCase(definition.Data_Type__c);
        if (!isRecord && !isRecordType && !isRecordTypes && !isFields) {
            return true;
        }
        Schema.SObjectType type = SettingsService.recordObjectType(definition);
        if (type == null) {
            return false;
        }
        setting.objectApiName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (isRecordType) {
            // One choice: the record types the row offers, then "No record type" (Master).
            for (Schema.RecordTypeInfo info : SettingsService.recordTypeChoices(type)) {
                Option option = new Option();
                option.value = info.getDeveloperName();
                option.label = info.getName();
                setting.options.add(option);
            }
            if (offersNoRecordType(type)) {
                Option none = new Option();
                none.value = AccountKinds.NO_RECORD_TYPE;
                none.label = System.Label.Core_Settings_NoRecordType;
                setting.options.add(none);
            }
        }
        if (isRecordTypes) {
            for (Schema.RecordTypeInfo info : SettingsService.recordTypes(type)) {
                Option option = new Option();
                option.value = info.getDeveloperName();
                option.label = info.getName();
                setting.options.add(option);
            }
        }
        if (isFields) {
            for (Schema.DescribeFieldResult field : SettingsService.fieldChoices(type)) {
                Option option = new Option();
                option.value = field.getName();
                option.label = field.getLabel();
                setting.options.add(option);
            }
        }
        return true;
    }

    private static List<Option> toOptions(Setting_Definition__mdt definition) {
        List<Option> options = new List<Option>();
        if (
            !TYPE_PICKLIST.equalsIgnoreCase(definition.Data_Type__c) ||
            String.isBlank(definition.Picklist_Values__c)
        ) {
            return options;
        }
        for (String pair : definition.Picklist_Values__c.split(';')) {
            String trimmed = pair.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            Option option = new Option();
            Integer separator = trimmed.indexOf(':');
            option.value = separator < 0 ? trimmed : trimmed.substring(0, separator).trim();
            option.label = separator < 0 ? trimmed : trimmed.substring(separator + 1).trim();
            options.add(option);
        }
        return options;
    }

    private static Boolean isCoexistenceMode(String settingsObject, String key) {
        return SettingsService.CORE_SETTINGS_OBJECT.equalsIgnoreCase(settingsObject) &&
            CoexistenceService.KEY_COEXISTENCE_MODE.equalsIgnoreCase(key);
    }

    /**
     * For organizations, "No record type" is offered only where it works: in an org with no
     * Account record type to offer (AccountKinds.noRecordTypeAllowed). It is also listed while
     * it is the value in force, so the row shows what is stored until the next upgrade replaces
     * it; saving it again changes nothing, and choosing it anew is refused (SettingsService).
     */
    private static Boolean offersNoRecordType(Schema.SObjectType type) {
        if (type != Account.SObjectType) {
            return true;
        }
        return AccountKinds.noRecordTypeAllowed() ||
            AccountKinds.NO_RECORD_TYPE.equalsIgnoreCase(AccountKinds.organizationRecordTypeName());
    }

    private static Boolean isOrganizationRecordType(String settingsObject, String key) {
        return SettingsService.CORE_SETTINGS_OBJECT.equalsIgnoreCase(settingsObject) &&
            AccountKinds.KEY_ORGANIZATION_RECORD_TYPE.equalsIgnoreCase(key);
    }

    private static Boolean isMembershipMode(String settingsObject, String key) {
        return SettingsService.CORE_SETTINGS_OBJECT.equalsIgnoreCase(settingsObject) &&
            CoexistenceService.KEY_MEMBERSHIP_MODE.equalsIgnoreCase(key);
    }

    /**
     * The coexistence options this org is offered: a mode named after another Salesforce
     * product appears only where that product is detected, or where it is already saved
     * (CoexistenceService.availableModes), in the order the definition lists them.
     */
    private static List<Option> offeredModesOnly(List<Option> options) {
        Set<String> offered = new Set<String>(CoexistenceService.availableModes());
        List<Option> kept = new List<Option>();
        for (Option option : options) {
            if (offered.contains(option.value)) {
                kept.add(option);
            }
        }
        return kept;
    }

    /**
     * Whether each Setup prerequisite a console section can check is already met: true or
     * false, and absent when it could not be read, so the note shows its instruction only.
     * Reads only what the person can read (whether the org may send email, their own custom
     * permission, the change history) and changes nothing. Not cacheable: an admin fixes
     * Setup, then reloads.
     */
    @AuraEnabled
    public static Map<String, Boolean> getSetupChecks() {
        Map<String, Boolean> checks = new Map<String, Boolean>();
        Boolean emailAllowed = orgMaySendEmail();
        if (emailAllowed != null) {
            checks.put(CHECK_EMAIL, emailAllowed);
        }
        Boolean metadataReady = metadataSavesReady();
        if (metadataReady != null) {
            checks.put(CHECK_METADATA, metadataReady);
        }
        return checks;
    }

    /**
     * Whether Custom Metadata saves can work for this person (owner QA, 2026-10-31). False
     * without Manage BarnCRM Metadata, which Apex reads directly. Apex cannot read the Apex
     * Settings option "Deploy Metadata from Non-Certified Package Versions via Apex" (Setup
     * and the Metadata API only), so the setting counts as on only once a Custom Metadata save
     * has finished: the audit row CustomMetadataDeployCallback writes for a succeeded
     * deployment. Null, can't confirm, when the permission is held and no save has worked yet.
     */
    private static Boolean metadataSavesReady() {
        if (!FeatureManagement.checkPermission(METADATA_PERMISSION)) {
            return false;
        }
        try {
            List<Setting_Change__c> saved = [
                SELECT Id
                FROM Setting_Change__c
                WHERE Deployment_Id__c != NULL
                WITH USER_MODE
                LIMIT 1
            ];
            return saved.isEmpty() ? null : true;
        } catch (Exception unreadable) {
            return null;
        }
    }

    /**
     * Salesforce refuses to reserve email capacity when Deliverability is not set to All
     * email, which is the one reading of that setting Apex has. Null when the answer is
     * something else (a daily limit reached says nothing about the setting).
     */
    private static Boolean orgMaySendEmail() {
        if (emailAllowedOverride != null) {
            return emailAllowedOverride;
        }
        try {
            Messaging.reserveSingleEmailCapacity(1);
            return true;
        } catch (NoAccessException blocked) {
            return false;
        } catch (Exception unknown) {
            return null;
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
