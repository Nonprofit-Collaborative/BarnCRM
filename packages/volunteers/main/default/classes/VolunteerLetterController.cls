/**
 * The Volunteer letter record action on a contact or person account (V-08): what it may offer,
 * a preview, and generating one letter. Every check is the service's; this class only shapes
 * answers for the screen.
 */
public with sharing class VolunteerLetterController {
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
                String label =
                    template.Name +
                    ' (' +
                    (typeLabels.containsKey(template.Type__c)
                        ? typeLabels.get(template.Type__c)
                        : template.Type__c) +
                    ')';
                templates.add(new Map<String, String>{ 'label' => label, 'value' => template.Id });
            }
        }
        return new Map<String, Object>{
            'canManage' => canManage,
            'isPerson' => isPerson,
            'templates' => templates
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
        } catch (VolunteerLetterService.VolunteerLetterException refused) {
            throw handled(refused);
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
        } catch (VolunteerLetterService.VolunteerLetterException refused) {
            throw handled(refused);
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

    private static AuraHandledException handled(Exception refused) {
        AuraHandledException handled = new AuraHandledException(refused.getMessage());
        handled.setMessage(refused.getMessage());
        return handled;
    }
}
