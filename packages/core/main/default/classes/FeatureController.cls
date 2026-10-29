/**
 * BarnCRM Settings, General, Features (ADR-0124): the eight Core features with their names,
 * descriptions and state, and the one-way Turn on. First-run setup lists the same rows.
 */
public with sharing class FeatureController {
    private static final String ERROR_CONTEXT = 'FeatureController';

    /** One feature as the page shows it. */
    public class FeatureRow {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean isOn;
        /** Extra sentence for the turn-on confirmation, or null. */
        @AuraEnabled
        public String confirmNote;
    }

    /** The feature list and whether this person may turn features on. */
    public class FeaturesModel {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<FeatureRow> features;
    }

    @AuraEnabled
    public static FeaturesModel getFeatures() {
        try {
            return model();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_Feature_LoadError);
        }
    }

    /** Turns one feature on, for good, after the page's confirmation. */
    @AuraEnabled
    public static FeaturesModel turnOn(String key) {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
        try {
            FeatureSwitchService.turnOn(key);
            return model();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            throw asAuraException(System.Label.Core_Feature_SaveError);
        }
    }

    /** Every feature in the order General lists them, with its state. */
    public static List<FeatureRow> rows() {
        Set<String> turnedOn = FeatureSwitchService.featuresOn();
        List<FeatureRow> rows = new List<FeatureRow>();
        for (FeatureSwitchService.Item item : FeatureSwitchService.all()) {
            FeatureRow row = new FeatureRow();
            row.key = item.key;
            row.name = nameOf(item.key);
            row.description = descriptionOf(item.key);
            row.isOn = turnedOn.contains(item.key.toLowerCase());
            row.confirmNote = item.key == FeatureSwitchService.HOUSEHOLD_UPKEEP
                ? System.Label.Core_Feature_HouseholdUpkeep_ConfirmNote
                : null;
            rows.add(row);
        }
        return rows;
    }

    private static FeaturesModel model() {
        FeaturesModel model = new FeaturesModel();
        model.canEdit = BarnCRMPermissions.canManageSettings();
        model.features = rows();
        return model;
    }

    @TestVisible
    private static String nameOf(String key) {
        switch on key {
            when 'DataManager' {
                return System.Label.Core_Feature_DataManager_Name;
            }
            when 'DuplicateReview' {
                return System.Label.Core_Feature_DuplicateReview_Name;
            }
            when 'OrgOptimizer' {
                return System.Label.Core_Feature_OrgOptimizer_Name;
            }
            when 'HouseholdUpkeep' {
                return System.Label.Core_Feature_HouseholdUpkeep_Name;
            }
            when 'Addresses' {
                return System.Label.Core_Feature_Addresses_Name;
            }
            when 'Relationships' {
                return System.Label.Core_Feature_Relationships_Name;
            }
            when 'Affiliations' {
                return System.Label.Core_Feature_Affiliations_Name;
            }
            when 'PreferredEmail' {
                return System.Label.Core_Feature_PreferredEmail_Name;
            }
            when else {
                return key;
            }
        }
    }

    private static String descriptionOf(String key) {
        switch on key {
            when 'DataManager' {
                return System.Label.Core_Feature_DataManager_Description;
            }
            when 'DuplicateReview' {
                return System.Label.Core_Feature_DuplicateReview_Description;
            }
            when 'OrgOptimizer' {
                return System.Label.Core_Feature_OrgOptimizer_Description;
            }
            when 'HouseholdUpkeep' {
                return System.Label.Core_Feature_HouseholdUpkeep_Description;
            }
            when 'Addresses' {
                return System.Label.Core_Feature_Addresses_Description;
            }
            when 'Relationships' {
                return System.Label.Core_Feature_Relationships_Description;
            }
            when 'Affiliations' {
                return System.Label.Core_Feature_Affiliations_Description;
            }
            when 'PreferredEmail' {
                return System.Label.Core_Feature_PreferredEmail_Description;
            }
            when else {
                return null;
            }
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
