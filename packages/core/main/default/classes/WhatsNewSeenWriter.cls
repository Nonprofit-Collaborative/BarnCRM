/**
 * Stores, for the running user, the release whose What's new notes they dismissed (C-27).
 *
 * DOCUMENTED EXCEPTION to the user-mode DML rule (plan Section 7.2), under ADR-0021 and
 * ADR-0087 (`0087-whats-new-from-packaged-release-notes.md`). `Whats_New_Seen__c` is a
 * protected hierarchy custom setting, so no permission set can grant a subscriber user access
 * to it, and every BarnCRM user, Read Only included, must be able to dismiss the card.
 *
 * The conditions of ADR-0021 are met here:
 *
 * - The write is the running user's own record, reached only from their own Dismiss
 *   (`WhatsNewController.dismiss`); no record of any other user is read or written.
 * - The value is the current version `WhatsNewController` computed from the shipped Release
 *   Note records. No user-typed text reaches it, and this class builds no query.
 * - Only `Last_Seen_Version__c`, a package owned field, is written. Nothing else is elevated.
 */
public without sharing class WhatsNewSeenWriter {
    public static void markSeen(String version) {
        Id userId = UserInfo.getUserId();
        Whats_New_Seen__c row = Whats_New_Seen__c.getValues(userId);
        if (row == null) {
            row = new Whats_New_Seen__c(SetupOwnerId = userId);
        }
        row.Last_Seen_Version__c = version;
        Database.upsert(row, AccessLevel.SYSTEM_MODE);
    }
}
