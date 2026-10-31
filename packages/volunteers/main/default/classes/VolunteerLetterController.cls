/**
 * The Volunteer letter record action on a contact or person account (V-08): what it may offer,
 * a preview, and generating one letter. Every check is the service's; this class only shapes
 * answers for the screen.
 */
public with sharing class VolunteerLetterController {
    private static final String CONTEXT = 'Volunteer letter action';

    /** What the action shows when it opens. */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getActionContext(Id recordId) {
        Boolean canManage = VolunteerHoursService.canManage();
        Boolean isPerson =
            recordId != null &&
            (recordId.getSObjectType() == Contact.SObjectType ||
            !VolunteerLetterSelector.personAccounts(new Set<Id>{ recordId }).isEmpty());
        List<Map<String, String>> templates = new List<Map<String, String>>();
        if (canManage && isPerson) {
            Map<String, String> typeLabels = typeLabels();
            for (
                Volunteer_Letter_Template__c template : VolunteerLetterSelector.activeTemplates()
            ) {
                String typeLabel = typeLabels.containsKey(template.Type__c)
                    ? typeLabels.get(template.Type__c)
                    : template.Type__c;
                // A template named for its type is not shown as "Certificate (Certificate)".
                String label = template.Name == typeLabel
                    ? template.Name
                    : template.Name + ' (' + typeLabel + ')';
                templates.add(new Map<String, String>{ 'label' => label, 'value' => template.Id });
            }
        }
        return new Map<String, Object>{
            'canManage' => canManage,
            'isPerson' => isPerson,
            'templates' => templates,
            'organizationNameBlank' => String.isBlank(
                BarnCRM_Settings__c.getOrgDefaults().Organization_Legal_Name__c
            )
        };
    }

    /** The merged letter, as the inside of its body, or why this person gets none. */
    @AuraEnabled
    public static Map<String, String> preview(
        Id recordId,
        Id templateId,
        Date fromDate,
        Date toDate
    ) {
        try {
            VolunteerLetterService.Letter letter = VolunteerLetterService.mergeLetters(
                new List<Id>{ recordId },
                templateId,
                fromDate,
                toDate
            )[0];
            return new Map<String, String>{
                'body' => letter.body,
                'skipReason' => letter.skipReason
            };
        } catch (Exception failure) {
            throw report(failure, recordId);
        }
    }

    /** Saves the letter as a file on the person; returns why not when none is made. */
    @AuraEnabled
    public static Map<String, String> generate(
        Id recordId,
        Id templateId,
        Date fromDate,
        Date toDate
    ) {
        try {
            VolunteerLetterService.Outcome outcome = VolunteerLetterService.generate(
                new List<Id>{ recordId },
                templateId,
                fromDate,
                toDate
            );
            return new Map<String, String>{
                'versionId' => outcome.versionIds.isEmpty() ? null : outcome.versionIds[0],
                'skipReason' => outcome.skipped.get(recordId)
            };
        } catch (Exception failure) {
            throw report(failure, recordId);
        }
    }

    /** The Type picklist's labels in the user's language, by value. */
    private static Map<String, String> typeLabels() {
        Map<String, String> labels = new Map<String, String>();
        for (
            Schema.PicklistEntry entry : Volunteer_Letter_Template__c.Type__c.getDescribe()
                .getPicklistValues()
        ) {
            labels.put(entry.getValue(), entry.getLabel());
        }
        return labels;
    }

    /** A refusal the service names is passed on as it is; anything else is logged first. */
    private static AuraHandledException report(Exception failure, Id recordId) {
        return UserErrors.wrap(
            failure,
            failure instanceof VolunteerLetterService.VolunteerLetterException,
            CONTEXT,
            recordId,
            Label.Volunteers_Letter_ActionFailed
        );
    }
}
