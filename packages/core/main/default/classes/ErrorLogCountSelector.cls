/**
 * Counts Error Log rows for Health Check (plan Section 4.8). Counting, not listing: Health
 * Check says how many entries nobody has read and sends the administrator to the tab.
 */
@NamespaceAccessible
public with sharing class ErrorLogCountSelector {
    @TestVisible
    private static final String STATUS_NEW = 'New';

    /**
     * How many Error Log entries nobody has looked at yet, or zero for a user who cannot read
     * the Error Log at all. A person without access is told nothing rather than shown a
     * failure: what they cannot see is not evidence of what is there.
     */
    public static Integer countNew() {
        if (!isReadable()) {
            return 0;
        }
        return [SELECT COUNT() FROM Error_Log__c WHERE Status__c = :STATUS_NEW WITH USER_MODE];
    }

    /**
     * The same count, stopping at `cap + 1`, so a count over a flooded Error Log spends at most
     * that many query rows. A result above `cap` means "more than `cap`".
     */
    public static Integer countNewUpTo(Integer cap) {
        if (!isReadable()) {
            return 0;
        }
        Integer readUpTo = cap + 1;
        return [
            SELECT COUNT()
            FROM Error_Log__c
            WHERE Status__c = :STATUS_NEW
            WITH USER_MODE
            LIMIT :readUpTo
        ];
    }

    /**
     * Whether the running user can read the Error Log at all.
     *
     * The status is part of the question, not a detail of it: the count filters on it, and a
     * `WITH USER_MODE` query throws for a field the reader may not see. Asking about the object
     * alone turned a person's missing field access into a failed check on Maria's Health Check
     * page, which is the opposite of what this selector promises: what somebody cannot see is
     * told to them as nothing, never as a fault.
     */
    public static Boolean isReadable() {
        return Error_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .isAccessible() && Error_Log__c.Status__c.getDescribe().isAccessible();
    }

    /**
     * The relative URL of the Error Log list view, resolved through describe so that it is
     * correct whatever namespace the package carries.
     */
    @NamespaceAccessible
    public static String listViewUrl() {
        return '/lightning/o/' +
            Error_Log__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            '/list';
    }
}
