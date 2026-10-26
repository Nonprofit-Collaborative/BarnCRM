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
    private static final String ERROR_CONTEXT = 'BarnCRM Settings console';
    /** The module a Setting Definition row belongs to when it names none. */
    private static final String CORE_MODULE = 'Core';
    /** The Setup prerequisites the console can check, by the key settingsSetupNotes reads. */
    @TestVisible
    private static final String CHECK_FISCAL_YEAR = 'fiscalYear';
    @TestVisible
    private static final String CHECK_EMAIL = 'emailDeliverability';

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
     * `saveSettings` and `getRecentChanges` for another package (ConsoleSaveAcrossModulesTest):
     * the platform rejects `@NamespaceAccessible` on an `@AuraEnabled` method.
     */
    @NamespaceAccessible
    public static ConsoleModel save(Map<String, Object> values) {
        return saveSettings(values);
    }

    @NamespaceAccessible
    public static List<ChangeModel> recentChanges(Integer limitCount) {
        return getRecentChanges(limitCount);
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
            for (Setting_Change__c record : SettingChangeSelector.getRecent(limitCount)) {
                ChangeModel change = new ChangeModel();
                change.id = record.Id;
                String stored = record.Setting_Name__c == null
                    ? ''
                    : record.Setting_Name__c.toLowerCase();
                change.settingName = labels.containsKey(stored)
                    ? labels.get(stored)
                    : record.Setting_Name__c;
                change.oldValue = record.Old_Value__c;
                change.newValue = record.New_Value__c;
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
            if (String.isBlank(definition.Setting_Key__c)) {
                continue;
            }
            String settingsObject = String.isBlank(definition.Settings_Object__c)
                ? SettingsService.CORE_SETTINGS_OBJECT
                : definition.Settings_Object__c.trim();
            labels.put(
                (settingsObject + '.' + definition.Setting_Key__c.trim()).toLowerCase(),
                definition.MasterLabel
            );
        }
        return labels;
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
        String settingsObject = String.isBlank(definition.Settings_Object__c)
            ? SettingsService.CORE_SETTINGS_OBJECT
            : definition.Settings_Object__c.trim();
        if (!isComponent && !SettingsService.hasKey(settingsObject, definition.Setting_Key__c)) {
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
        setting.section = String.isBlank(definition.Section__c) ? '' : definition.Section__c;
        setting.component = definition.Component__c;
        setting.navigationTarget = definition.Navigation_Target__c;
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
        Object value = SettingsService.getEffectiveValue(
            settingsObject,
            definition.Setting_Key__c,
            definition.Data_Type__c
        );
        setting.value = SettingsService.asText(value);
        setting.checked = TYPE_CHECKBOX.equalsIgnoreCase(definition.Data_Type__c) && value == true;
        return setting;
    }

    /**
     * Gives a Record row its object and a Record Type List row its choices, read from describe
     * (ADR-0074). False when the row names an object this org does not have, which leaves the
     * row out as a missing settings object does.
     */
    private static Boolean addRecordChoices(
        Setting_Definition__mdt definition,
        SettingModel setting
    ) {
        Boolean isRecord = SettingsService.RECORD.equalsIgnoreCase(definition.Data_Type__c);
        Boolean isRecordTypes = SettingsService.RECORD_TYPE_LIST.equalsIgnoreCase(
            definition.Data_Type__c
        );
        if (!isRecord && !isRecordTypes) {
            return true;
        }
        Schema.SObjectType type = SettingsService.recordObjectType(definition);
        if (type == null) {
            return false;
        }
        setting.objectApiName = type.getDescribe(SObjectDescribeOptions.DEFERRED).getName();
        if (isRecordTypes) {
            for (Schema.RecordTypeInfo info : SettingsService.recordTypes(type)) {
                Option option = new Option();
                option.value = info.getDeveloperName();
                option.label = info.getName();
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
     * Reads only what every user can read (the org's fiscal year, whether the org may send
     * email) and changes nothing. Not cacheable: an admin fixes Setup, then reloads.
     */
    @AuraEnabled
    public static Map<String, Boolean> getSetupChecks() {
        Map<String, Boolean> checks = new Map<String, Boolean>();
        try {
            Integer orgMonth = FiscalYearSelector.orgFiscalYearStartMonth();
            if (orgMonth != null) {
                checks.put(
                    CHECK_FISCAL_YEAR,
                    orgMonth == FiscalYearSelector.settingsFiscalYearStartMonth()
                );
            }
        } catch (Exception unreadable) {
            checks.remove(CHECK_FISCAL_YEAR);
        }
        Boolean emailAllowed = orgMaySendEmail();
        if (emailAllowed != null) {
            checks.put(CHECK_EMAIL, emailAllowed);
        }
        return checks;
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
