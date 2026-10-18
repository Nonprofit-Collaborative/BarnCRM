/**
 * R-VL1, one active letter template per type, run by the Core trigger dispatcher through the
 * registry row `Volunteer_Letter_Template_Rules`, which always runs: it keeps a rule rather than
 * doing work for anyone (ADR-0024).
 *
 * Before the save, when one save activates two templates of a type, the last one stays active.
 * After it, every other active template of that type is deactivated.
 */
@NamespaceAccessible
public with sharing class VolunteerLetterTemplateTriggerHandler extends TriggerHandler {
    @NamespaceAccessible
    public VolunteerLetterTemplateTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerLetterTemplateTriggerHandler';
    }

    public override void beforeInsert() {
        keepLastActivePerType();
    }

    public override void beforeUpdate() {
        keepLastActivePerType();
    }

    public override void afterInsert() {
        deactivateOthers();
    }

    public override void afterUpdate() {
        deactivateOthers();
    }

    private void keepLastActivePerType() {
        Map<String, Volunteer_Letter_Template__c> lastByType = new Map<String, Volunteer_Letter_Template__c>();
        for (Volunteer_Letter_Template__c template : templates()) {
            if (template.Active__c) {
                Volunteer_Letter_Template__c earlier = lastByType.put(template.Type__c, template);
                if (earlier != null) {
                    earlier.Active__c = false;
                }
            }
        }
    }

    /**
     * System mode: the rule holds whoever saves, the install's package user included, and the
     * only value written is Active false on a template of a type the saver just activated.
     */
    private void deactivateOthers() {
        Set<String> types = new Set<String>();
        Set<Id> saved = new Set<Id>();
        for (Volunteer_Letter_Template__c template : templates()) {
            saved.add(template.Id);
            if (template.Active__c) {
                types.add(template.Type__c);
            }
        }
        if (types.isEmpty()) {
            return;
        }
        List<Volunteer_Letter_Template__c> others = [
            SELECT Id
            FROM Volunteer_Letter_Template__c
            WHERE Active__c = TRUE AND Type__c IN :types AND Id NOT IN :saved
            WITH SYSTEM_MODE
        ];
        for (Volunteer_Letter_Template__c other : others) {
            other.Active__c = false;
        }
        Database.update(others, true, AccessLevel.SYSTEM_MODE);
    }

    private List<Volunteer_Letter_Template__c> templates() {
        return (List<Volunteer_Letter_Template__c>) newRecords();
    }
}
