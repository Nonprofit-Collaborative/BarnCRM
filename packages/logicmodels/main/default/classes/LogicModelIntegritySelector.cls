/**
 * The read the Logic Models scope rule makes about what already exists in the org, whoever is
 * saving (R-LM1). ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because the answer is a fact about the org, not about
 * what the saving user may see: a model someone else owns must still stop a second one for the
 * same scope. What the user learns is limited to the refusal itself, naming only whether the scope
 * is the organization or a program. No field of a hidden record is shown, and nothing reaches a
 * dynamic query.
 */
public without sharing class LogicModelIntegritySelector {
    /**
     * The models holding one of these scope keys, other than the ones being saved.
     *
     * @param scopeKeys the scope keys being claimed
     * @param excluded the models being saved, which may keep their own key
     * @return the models already holding a key
     */
    public static List<Logic_Model__c> selectByScopeKeys(Set<String> scopeKeys, Set<Id> excluded) {
        if (scopeKeys == null || scopeKeys.isEmpty()) {
            return new List<Logic_Model__c>();
        }
        Set<Id> skip = excluded == null ? new Set<Id>() : excluded;
        return [
            SELECT Id, Scope_Key__c
            FROM Logic_Model__c
            WHERE Scope_Key__c IN :scopeKeys AND Id NOT IN :skip
            WITH SYSTEM_MODE
        ];
    }
}
