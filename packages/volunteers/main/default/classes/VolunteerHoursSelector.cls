/**
 * The hours reads `VolunteerHoursService` and the Approve Hours screen make, in user mode: a
 * coordinator lists, approves, rejects or reopens only the entries they can see.
 */
public with sharing class VolunteerHoursSelector {
    private static final String APPROVAL_FIELDS =
        'SELECT Id, Name, Status__c, Date_Worked__c, Hours__c, Rejection_Reason__c, ' +
        'Contact__r.Name, Account__r.Name, Volunteer_Job__r.Name, Volunteer_Shift__r.Name ' +
        'FROM Volunteer_Hours__c WHERE Status__c = :status';

    /**
     * One page of entries in this status for the Approve Hours screen, oldest date worked first
     * and then by Id, so paging by the last row seen never skips or repeats one. The job and the
     * dates narrow it when given. `afterDate` and `afterId` are the last row of the page before,
     * or null for the first page. At most `max` rows.
     */
    public static List<Volunteer_Hours__c> selectForApproval(
        String status,
        Id jobId,
        Date fromDate,
        Date toDate,
        Date afterDate,
        Id afterId,
        Integer max
    ) {
        Map<String, Object> binds = new Map<String, Object>{ 'status' => status, 'max' => max };
        String soql = APPROVAL_FIELDS;
        if (jobId != null) {
            soql += ' AND Volunteer_Job__c = :jobId';
            binds.put('jobId', jobId);
        }
        if (fromDate != null) {
            soql += ' AND Date_Worked__c >= :fromDate';
            binds.put('fromDate', fromDate);
        }
        if (toDate != null) {
            soql += ' AND Date_Worked__c <= :toDate';
            binds.put('toDate', toDate);
        }
        if (afterDate != null && afterId != null) {
            soql += ' AND (Date_Worked__c > :afterDate OR (Date_Worked__c = :afterDate AND Id > :afterId))';
            binds.put('afterDate', afterDate);
            binds.put('afterId', afterId);
        }
        soql += ' ORDER BY Date_Worked__c ASC, Id ASC LIMIT :max';
        return Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    /** The entries with these Ids, with what a status change reads. */
    public static List<Volunteer_Hours__c> selectForStatusChange(Set<Id> hoursIds) {
        if (hoursIds == null || hoursIds.isEmpty()) {
            return new List<Volunteer_Hours__c>();
        }
        return [
            SELECT Id, Status__c, Rejection_Reason__c
            FROM Volunteer_Hours__c
            WHERE Id IN :hoursIds
            WITH USER_MODE
        ];
    }
}
