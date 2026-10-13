/**
 * What the household screens call. Every method validates what it is given and returns a
 * shape the component can render, or an error a person can read.
 */
public with sharing class HouseholdController {
    /**
     * One sample household in the naming preview.
     */
    public class HouseholdPreview {
        @AuraEnabled
        public String members;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String formalGreeting;
        @AuraEnabled
        public String informalGreeting;
    }

    /**
     * The naming patterns as this org has them saved.
     */
    public class NamingSettings {
        @AuraEnabled
        public String namePattern;
        @AuraEnabled
        public String formalPattern;
        @AuraEnabled
        public String informalPattern;
        @AuraEnabled
        public Boolean includeDeceasedInName;
        @AuraEnabled
        public Boolean canEdit;
    }

    /**
     * One member of a household, as the members panel shows them.
     */
    public class MemberView {
        @AuraEnabled
        public Id personId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public Boolean isPrimary;
        @AuraEnabled
        public Boolean isDeceased;
    }

    /**
     * Five sample households, computed in memory from the patterns being typed. Nothing is
     * read from or written to the org's own households. R-H14.
     */
    @AuraEnabled(cacheable=true)
    public static List<HouseholdPreview> preview(
        String namePattern,
        String formalPattern,
        String informalPattern
    ) {
        try {
            BarnCRM_Settings__c settings = SettingsService.getSettings();
            Boolean includeDeceased =
                settings != null &&
                settings.Include_Deceased_In_Name__c == true;
            List<HouseholdPreview> result = new List<HouseholdPreview>();
            for (List<HouseholdService.Person> members : sampleHouseholds()) {
                HouseholdPreview row = new HouseholdPreview();
                row.members = describe(members);
                row.name = HouseholdNamingService.computeName(
                    members,
                    namePattern,
                    includeDeceased
                );
                row.formalGreeting = HouseholdNamingService.computeFormalGreeting(
                    members,
                    formalPattern,
                    includeDeceased
                );
                row.informalGreeting = HouseholdNamingService.computeInformalGreeting(
                    members,
                    informalPattern
                );
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            throw asUserError(e, Label.Core_Households_ErrorContextNaming, null);
        }
    }

    /**
     * The patterns this org has saved, so that the settings page opens on the admin's own
     * wording rather than on the shipped defaults.
     */
    @AuraEnabled(cacheable=true)
    public static NamingSettings getNamingSettings() {
        try {
            BarnCRM_Settings__c settings = SettingsService.getSettings();
            NamingSettings result = new NamingSettings();
            result.namePattern = settings == null ? null : settings.Household_Name_Pattern__c;
            result.formalPattern = settings == null ? null : settings.Formal_Greeting_Pattern__c;
            result.informalPattern = settings == null
                ? null
                : settings.Informal_Greeting_Pattern__c;
            result.includeDeceasedInName =
                settings != null &&
                settings.Include_Deceased_In_Name__c == true;
            result.canEdit = canManageSettings();
            return result;
        } catch (Exception e) {
            throw asUserError(e, Label.Core_Households_ErrorContextNaming, null);
        }
    }

    /**
     * Starts the batch that rewrites every household that is not marked as a custom name,
     * and gives the screen the job id so it can report progress. Rewriting every household
     * in the org is an administrator's action, so the permission is checked here and not
     * only on the screen.
     */
    @AuraEnabled
    public static String recomputeAll() {
        try {
            if (!canManageSettings()) {
                throw new HouseholdException(Label.Core_Households_ErrorNoSettingsPermission);
            }
            return String.valueOf(Database.executeBatch(new HouseholdNamingBatch(), 200));
        } catch (Exception e) {
            throw asUserError(e, Label.Core_Households_ErrorContextNaming, null);
        }
    }

    /**
     * How this org says people belong to a household, so that a screen can offer the
     * actions that make sense here and no other code has to know the answer.
     */
    @AuraEnabled(cacheable=true)
    public static String getMembershipMode() {
        return HouseholdService.isJunctionMode()
            ? HouseholdService.MODE_JUNCTION
            : HouseholdService.SOURCE_CONTACT;
    }

    @AuraEnabled(cacheable=true)
    public static List<MemberView> getMembers(Id householdId) {
        try {
            if (householdId == null || householdId.getSObjectType() != Account.SObjectType) {
                throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
            }
            List<MemberView> result = new List<MemberView>();
            // What a screen shows is read with the running user's own access (ADR-0021),
            // so a field this user cannot read on the record does not reach the panel.
            Map<Id, List<HouseholdService.Person>> membersByHousehold = HouseholdService.getMembersAsUser(
                new Set<Id>{ householdId }
            );
            List<HouseholdService.Person> members = membersByHousehold.get(householdId);
            if (members == null) {
                return result;
            }
            for (HouseholdService.Person person : members) {
                MemberView row = new MemberView();
                row.personId = person.id;
                row.name = fullName(person);
                row.role = person.role;
                row.source = person.sourceObject;
                row.isPrimary = person.isPrimary == true;
                row.isDeceased = person.isDeceased == true;
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            throw asUserError(e, Label.Core_Households_ErrorContextMembership, householdId);
        }
    }

    /**
     * Moves a person from the household whose page the panel sits on (`sourceHouseholdId`)
     * to another. In junction mode only that one membership ends; left out, every other
     * household the person is in is left.
     */
    @AuraEnabled
    public static void moveContact(Id contactId, Id targetHouseholdId, Id sourceHouseholdId) {
        try {
            HouseholdService.moveContact(contactId, targetHouseholdId, sourceHouseholdId);
        } catch (Exception e) {
            throw asUserError(e, Label.Core_Households_ErrorContextMembership, contactId);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static Boolean canManageSettings() {
        return FeatureManagement.checkPermission('Manage_BarnCRM_Settings');
    }

    /**
     * What the screen is told. A HouseholdException already says in plain words what went
     * wrong and what to do, so its message goes through as it is. Anything else is a
     * platform failure whose wording is for an administrator reading the Error Log, not
     * for the person at the screen: the whole exception is logged and the screen gets the
     * generic message.
     */
    private static AuraHandledException asUserError(Exception e, String context, Id recordId) {
        String message;
        if (e instanceof HouseholdException) {
            message = e.getMessage();
        } else {
            ErrorLogger.log(e, context, recordId);
            message = Label.Core_Households_ErrorUnexpected;
        }
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    private static String fullName(HouseholdService.Person person) {
        String first = String.isNotBlank(person.preferredName)
            ? person.preferredName
            : person.firstName;
        String full =
            (first == null ? '' : first) +
            ' ' +
            (person.lastName == null ? '' : person.lastName);
        return full.trim();
    }

    /**
     * Line breaks that a formatter may have put inside the sample label are not part of
     * anybody's name, so they are squeezed back to single spaces before the value is used.
     */
    private static String squeeze(String value) {
        return value == null ? '' : value.replaceAll('\\s+', ' ').trim();
    }

    private static String describe(List<HouseholdService.Person> members) {
        List<String> names = new List<String>();
        for (HouseholdService.Person person : members) {
            names.add(fullName(person));
        }
        return String.join(names, ', ');
    }

    /**
     * The five sample households the preview uses, read from a custom label so that they
     * can be translated. Each household is separated by a vertical bar, each member by a
     * semicolon, and each member reads: title, first name, surname, preferred name, role,
     * and Y when the person has died.
     */
    private static List<List<HouseholdService.Person>> sampleHouseholds() {
        List<List<HouseholdService.Person>> result = new List<List<HouseholdService.Person>>();
        for (String block : Label.Core_HouseholdNaming_SampleHouseholds.split('\\|')) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>();
            for (String entry : block.split(';')) {
                List<String> parts = entry.split(',', -1);
                if (parts.size() < 6) {
                    continue;
                }
                HouseholdService.Person person = new HouseholdService.Person();
                person.salutation = squeeze(parts[0]);
                person.firstName = squeeze(parts[1]);
                person.lastName = squeeze(parts[2]);
                person.preferredName = squeeze(parts[3]);
                person.role = squeeze(parts[4]);
                person.isDeceased = 'Y'.equalsIgnoreCase(squeeze(parts[5]));
                members.add(person);
            }
            if (!members.isEmpty()) {
                result.add(members);
            }
        }
        return result;
    }
}
