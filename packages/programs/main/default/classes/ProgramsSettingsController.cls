/**
 * The Programs settings page (reached from the Programs section of BarnCRM Settings): the intake
 * and eligibility picklists (P-07, canonical model 29ZA) with their current values and a link to
 * change them in Setup, and the Participant Privacy preset (P-08, R-EN7). Returns plain wrappers
 * (plan 9.9).
 */
public with sharing class ProgramsSettingsController {
    private static final String CONTEXT = 'ProgramsSettingsController';

    /** The intake picklists an admin may change, in the order the page shows them. */
    @TestVisible
    private static final List<Schema.SObjectField> INTAKE_PICKLISTS = new List<Schema.SObjectField>{
        Enrollment__c.Referral_Source__c,
        Enrollment__c.Eligibility_Status__c,
        Enrollment__c.Eligibility_Basis__c
    };

    public class Picklist {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public List<String> values = new List<String>();
        @AuraEnabled
        public String defaultValue;
        @AuraEnabled
        public String setupUrl;
    }

    public class Settings {
        @AuraEnabled
        public Boolean canManage = false;
        @AuraEnabled
        public List<Picklist> intakePicklists = new List<Picklist>();
        /** The Participant Privacy preset (P-08): Shared, the default, or Private. */
        @AuraEnabled
        public String participantPrivacy = ProgramsSharing.SHARED;
    }

    /**
     * Saves the Participant Privacy preset org-wide (P-08, R-EN7): Private when true, Shared when
     * false. Audited, and applied within a minute by a queued job. Returns the page's settings.
     */
    @AuraEnabled
    public static Settings savePrivacy(Boolean privateParticipants) {
        if (!HealthCheckService.canManageSettings()) {
            AuraHandledException refused = new AuraHandledException(
                Label.Programs_Settings_NoAccess
            );
            refused.setMessage(Label.Programs_Settings_NoAccess);
            throw refused;
        }
        try {
            ProgramsSharing.savePreset(privateParticipants);
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT, null);
            AuraHandledException refused = new AuraHandledException(
                Label.Programs_Settings_SaveFailed
            );
            refused.setMessage(Label.Programs_Settings_SaveFailed);
            throw refused;
        }
        return getSettings();
    }

    @AuraEnabled
    public static Settings getSettings() {
        try {
            Settings settings = new Settings();
            settings.canManage = HealthCheckService.canManageSettings();
            if (!settings.canManage) {
                return settings;
            }
            settings.participantPrivacy = ProgramsSharing.presetName(ProgramsSharing.isPrivate());
            for (Schema.SObjectField token : INTAKE_PICKLISTS) {
                Schema.DescribeFieldResult described = token.getDescribe();
                Picklist picklist = new Picklist();
                picklist.label = described.getLabel();
                picklist.apiName = described.getLocalName();
                for (Schema.PicklistEntry entry : described.getPicklistValues()) {
                    if (entry.isActive()) {
                        picklist.values.add(entry.getLabel());
                    }
                    if (entry.isDefaultValue()) {
                        picklist.defaultValue = entry.getLabel();
                    }
                }
                picklist.setupUrl = setupUrl();
                settings.intakePicklists.add(picklist);
            }
            return settings;
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT, null);
            AuraHandledException refused = new AuraHandledException(
                Label.Programs_Settings_LoadFailed
            );
            refused.setMessage(Label.Programs_Settings_LoadFailed);
            throw refused;
        }
    }

    /**
     * The enrollment's Fields and Relationships page in Setup, where the field is picked. Object
     * Manager takes the object's API name, so no Setup ID is read.
     */
    private static String setupUrl() {
        return '/lightning/setup/ObjectManager/' +
            Schema.SObjectType.Enrollment__c.getName() +
            '/FieldsAndRelationships/view';
    }
}
