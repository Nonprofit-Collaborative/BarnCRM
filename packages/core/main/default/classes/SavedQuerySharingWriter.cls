/**
 * Keeps the Apex managed share of each saved Find query in step with its Shared flag.
 *
 * System mode, `without sharing`, under ADR-0076 (saved queries are private and shared by Apex
 * managed sharing) and in the manner of ADR-0021: a user cannot create a share with an Apex
 * sharing reason, so this one write runs as the system. It is reached only from FindController,
 * after the caller has checked the Find and Export Records permission and that the running user
 * owns every query passed in. It writes nothing but Saved_Query__Share rows with the reason
 * Shared_With_Find_Users__c, granting Read to the org's All Internal Users group.
 */
public without sharing class SavedQuerySharingWriter {
    /** Shares each query whose value is true and unshares each whose value is false. */
    public static void setShared(Map<Id, Boolean> sharedByQueryId) {
        if (sharedByQueryId == null || sharedByQueryId.isEmpty()) {
            return;
        }
        String reason = Schema.Saved_Query__Share.RowCause.Shared_With_Find_Users__c;
        Set<Id> queryIds = sharedByQueryId.keySet();
        Map<Id, List<Saved_Query__Share>> existingByQuery = new Map<Id, List<Saved_Query__Share>>();
        for (Saved_Query__Share share : [
            SELECT Id, ParentId
            FROM Saved_Query__Share
            WHERE ParentId IN :queryIds AND RowCause = :reason
            WITH SYSTEM_MODE
        ]) {
            if (!existingByQuery.containsKey(share.ParentId)) {
                existingByQuery.put(share.ParentId, new List<Saved_Query__Share>());
            }
            existingByQuery.get(share.ParentId).add(share);
        }

        List<Saved_Query__Share> toInsert = new List<Saved_Query__Share>();
        List<Saved_Query__Share> toDelete = new List<Saved_Query__Share>();
        Id everyone;
        for (Id queryId : queryIds) {
            Boolean shared = sharedByQueryId.get(queryId) == true;
            List<Saved_Query__Share> existing = existingByQuery.get(queryId);
            if (shared && existing == null) {
                everyone = everyone == null ? allInternalUsers() : everyone;
                toInsert.add(
                    new Saved_Query__Share(
                        ParentId = queryId,
                        UserOrGroupId = everyone,
                        AccessLevel = 'Read',
                        RowCause = reason
                    )
                );
            } else if (!shared && existing != null) {
                toDelete.addAll(existing);
            }
        }
        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, AccessLevel.SYSTEM_MODE);
        }
        if (!toDelete.isEmpty()) {
            Database.delete(toDelete, AccessLevel.SYSTEM_MODE);
        }
    }

    /** The org-wide group every internal user belongs to. */
    private static Id allInternalUsers() {
        return [SELECT Id FROM Group WHERE Type = 'Organization' WITH SYSTEM_MODE LIMIT 1].Id;
    }
}
