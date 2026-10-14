/**
 * Deletes the field history of an erased person and their Individual once the erasure has
 * committed (canonical model R-ER4). It cannot run inside the erasure: the erasure's own save
 * writes history rows that hold the old values, and they exist only after the commit.
 *
 * Runs as the user who erased, in user mode, so it deletes only where Salesforce lets that user
 * delete field history (the Delete From Field History permission). A refusal is logged; the
 * erasure itself already stands.
 */
public with sharing class PersonErasureHistoryCleanup implements Queueable {
    /** Record Ids by history object and parent field, as "ContactHistory.ContactId". */
    private final Map<String, Set<Id>> targets;

    public PersonErasureHistoryCleanup(Map<String, Set<Id>> targets) {
        this.targets = targets;
    }

    public void execute(QueueableContext context) {
        for (String key : targets.keySet()) {
            String historyObject = key.substringBefore('.');
            String parentField = key.substringAfter('.');
            try {
                List<SObject> rows = Database.queryWithBinds(
                    'SELECT Id FROM ' +
                        historyObject +
                        ' WHERE ' +
                        parentField +
                        ' IN :ids LIMIT 10000',
                    new Map<String, Object>{ 'ids' => targets.get(key) },
                    AccessLevel.USER_MODE
                );
                if (!rows.isEmpty()) {
                    Database.delete(rows, true, AccessLevel.USER_MODE);
                }
            } catch (Exception refused) {
                ErrorLogger.log(refused, 'PersonErasureHistoryCleanup.' + historyObject);
            }
        }
    }
}
