/**
 * Record-level rules for Appeal__c: the appeal hierarchy is shallow and it never loops
 * (R-AP2). An appeal that is its own parent is caught by a validation rule; this handler
 * catches the longer loops a validation rule cannot see.
 */
@NamespaceAccessible
public with sharing class AppealTriggerHandler extends TriggerHandler {
    private static final Integer MAX_DEPTH = 20;

    @NamespaceAccessible
    public AppealTriggerHandler() {
        return;
    }

    public override String getName() {
        return 'AppealTriggerHandler';
    }

    public override void beforeInsert() {
        preventCycles((List<Appeal__c>) Trigger.new);
    }

    public override void beforeUpdate() {
        preventCycles((List<Appeal__c>) Trigger.new);
    }

    /**
     * Walks up from each appeal's proposed parent. Meeting the appeal itself means the save
     * would close a loop.
     */
    private void preventCycles(List<Appeal__c> appeals) {
        Set<Id> parentIds = new Set<Id>();
        for (Appeal__c appeal : appeals) {
            if (appeal.Parent_Appeal__c != null) {
                parentIds.add(appeal.Parent_Appeal__c);
            }
        }
        if (parentIds.isEmpty()) {
            return;
        }

        Map<Id, Id> parents = AppealSelector.selectParentsById(parentIds);
        Set<Id> unresolved = new Set<Id>();
        for (Id parentId : parents.values()) {
            if (parentId != null && !parents.containsKey(parentId)) {
                unresolved.add(parentId);
            }
        }
        Integer depth = 0;
        while (!unresolved.isEmpty() && depth < MAX_DEPTH) {
            Map<Id, Id> next = AppealSelector.selectParentsById(unresolved);
            parents.putAll(next);
            unresolved = new Set<Id>();
            for (Id parentId : next.values()) {
                if (parentId != null && !parents.containsKey(parentId)) {
                    unresolved.add(parentId);
                }
            }
            depth++;
        }

        for (Appeal__c appeal : appeals) {
            if (appeal.Parent_Appeal__c == null || appeal.Id == null) {
                continue;
            }
            Id ancestorId = appeal.Parent_Appeal__c;
            Integer steps = 0;
            while (ancestorId != null && steps <= MAX_DEPTH) {
                if (ancestorId == appeal.Id) {
                    appeal.addError(Label.Giving_Appeal_ParentCycle);
                    break;
                }
                ancestorId = parents.get(ancestorId);
                steps++;
            }
        }
    }
}
