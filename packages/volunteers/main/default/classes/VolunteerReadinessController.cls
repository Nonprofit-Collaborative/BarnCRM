/**
 * The volunteer readiness card on a person (R-VQ3): for each requirement Type, that Type's most
 * recent row or "not started", and whether it is current. Read only and never blocking: nothing
 * here refuses a sign-up or hours.
 *
 * Read in user mode, so the card shows only what the user may see. A user without access to
 * requirements (Team Member, Read Only) gets `canSee` false and the card shows nothing; so does
 * an account that is a household or organization rather than a person.
 */
public with sharing class VolunteerReadinessController {
    private static final Integer MAX_ROWS = 2000;

    /** What the card shows. */
    public class Readiness {
        @AuraEnabled
        public Boolean canSee = false;
        @AuraEnabled
        public List<Step> steps = new List<Step>();
    }

    /** One requirement Type on this person. `requirementId` is empty when not started. */
    public class Step {
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String typeLabel;
        @AuraEnabled
        public Id requirementId;
        @AuraEnabled
        public String statusLabel;
        @AuraEnabled
        public Date completedDate;
        @AuraEnabled
        public Date expires;
        @AuraEnabled
        public Boolean isCurrent = false;
    }

    @AuraEnabled(cacheable=true)
    public static Readiness getReadiness(Id personId) {
        Readiness result = new Readiness();
        if (
            personId == null ||
            !Schema.SObjectType.Volunteer_Requirement__c.isAccessible() ||
            !isPerson(personId)
        ) {
            return result;
        }
        result.canSee = true;

        Map<String, String> typeLabels = labels(Volunteer_Requirement__c.Type__c);
        Map<String, String> statusLabels = labels(Volunteer_Requirement__c.Status__c);
        Map<String, Volunteer_Requirement__c> latestByType = new Map<String, Volunteer_Requirement__c>();
        for (Volunteer_Requirement__c row : [
            SELECT Id, Type__c, Status__c, Completed_Date__c, Expires__c, Is_Current__c
            FROM Volunteer_Requirement__c
            WHERE Contact__c = :personId OR Account__c = :personId
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :MAX_ROWS
        ]) {
            if (row.Type__c != null && !latestByType.containsKey(row.Type__c)) {
                latestByType.put(row.Type__c, row);
            }
        }

        // Every active Type in picklist order, then any retired one this person still has.
        List<String> types = new List<String>();
        for (
            Schema.PicklistEntry entry : Volunteer_Requirement__c.Type__c.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                types.add(entry.getValue());
            }
        }
        for (String type : latestByType.keySet()) {
            if (!typeLabels.containsKey(type)) {
                types.add(type);
            }
        }
        for (String type : types) {
            Step step = new Step();
            step.type = type;
            step.typeLabel = typeLabels.containsKey(type) ? typeLabels.get(type) : type;
            Volunteer_Requirement__c row = latestByType.get(type);
            if (row != null) {
                step.requirementId = row.Id;
                step.statusLabel = statusLabels.containsKey(row.Status__c)
                    ? statusLabels.get(row.Status__c)
                    : row.Status__c;
                step.completedDate = row.Completed_Date__c;
                step.expires = row.Expires__c;
                step.isCurrent = row.Is_Current__c == true;
            }
            result.steps.add(step);
        }
        return result;
    }

    /**
     * A contact is a person. An account is one only where the org has person accounts and its
     * record type is a person type, read without naming any person account field.
     */
    private static Boolean isPerson(Id recordId) {
        Schema.SObjectType type = recordId.getSObjectType();
        if (type == Contact.SObjectType) {
            return true;
        }
        if (type != Account.SObjectType || !OrgShapeDetector.hasPersonAccounts()) {
            return false;
        }
        List<Account> found = [
            SELECT RecordTypeId
            FROM Account
            WHERE Id = :recordId
            WITH USER_MODE
            LIMIT 1
        ];
        return !found.isEmpty() &&
            OrgShapeDetector.personAccountRecordTypeIds().contains(found[0].RecordTypeId);
    }

    /** Active picklist values in order, value to label. */
    private static Map<String, String> labels(Schema.SObjectField field) {
        Map<String, String> byValue = new Map<String, String>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                byValue.put(entry.getValue(), entry.getLabel());
            }
        }
        return byValue;
    }
}
