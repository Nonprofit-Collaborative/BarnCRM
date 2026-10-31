/**
 * Whose logic model a model is, and the rule that each has one (canonical model R-LM1, R-LM2;
 * ADR-NEXT `NEXT-logic-models-module.md`, decision 5).
 *
 * A model with no program is the organization's; a model may name a program by its record
 * identifier, held as text so Logic Models never depends on Programs. Every save sets the unique
 * `Scope_Key__c` (`Organization`, or the program's 18-character identifier), and a second model
 * for the same scope is refused with a plain message, counting models the saving user cannot see.
 * The unique field backs the check against two saves at the same moment.
 */
public with sharing class LogicModelScope {
    /** The scope key of the organization's own model. */
    public static final String ORGANIZATION = 'Organization';

    /**
     * Sets each model's scope key, normalizes its program identifier to 18 characters, and refuses
     * a malformed identifier or a scope another model already holds.
     *
     * @param models the models being saved (Trigger.new, before insert or update)
     * @param previousById the models as they were, or null on insert
     */
    public static void apply(List<Logic_Model__c> models, Map<Id, Logic_Model__c> previousById) {
        Map<String, Logic_Model__c> claimed = new Map<String, Logic_Model__c>();
        for (Logic_Model__c model : models) {
            String key = keyFor(model.Program_Id__c);
            if (key == null) {
                model.Program_Id__c.addError(Label.LogicModels_Scope_BadProgram);
                continue;
            }
            model.Program_Id__c = key == ORGANIZATION ? null : key;
            Logic_Model__c previous = previousById == null ? null : previousById.get(model.Id);
            Boolean moved = previous == null || previous.Scope_Key__c != key;
            model.Scope_Key__c = key;
            if (!moved) {
                continue;
            }
            if (claimed.containsKey(key)) {
                model.addError(messageFor(key));
                continue;
            }
            claimed.put(key, model);
        }
        if (claimed.isEmpty()) {
            return;
        }
        Set<Id> own = previousById == null ? new Set<Id>() : previousById.keySet();
        for (
            Logic_Model__c existing : LogicModelIntegritySelector.selectByScopeKeys(
                claimed.keySet(),
                own
            )
        ) {
            Logic_Model__c model = claimed.get(existing.Scope_Key__c);
            if (model != null) {
                model.addError(messageFor(existing.Scope_Key__c));
            }
        }
    }

    /**
     * The scope key for a program identifier: `Organization` when it is blank, the 18-character
     * identifier when it is well formed, and null when it is not.
     *
     * @param programId the program identifier as typed or saved
     * @return the scope key, or null for a malformed identifier
     */
    public static String keyFor(String programId) {
        if (String.isBlank(programId)) {
            return ORGANIZATION;
        }
        try {
            return String.valueOf(Id.valueOf(programId.trim()));
        } catch (System.StringException e) {
            return null;
        }
    }

    private static String messageFor(String key) {
        return key == ORGANIZATION
            ? Label.LogicModels_Scope_OrganizationTaken
            : Label.LogicModels_Scope_ProgramTaken;
    }
}
