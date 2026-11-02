/**
 * The dated rows the Grant Pipeline's Upcoming Deadlines and the Grant Calendar both draw (ADR-0162
 * `0162-funders-restricted-funds-schedules-calendar.md` decision 8): application deadlines of
 * grants not yet submitted, due dates of open requirements, and expected payments. One reader, so
 * the two cannot disagree. Everything runs in user mode.
 *
 * A `fromDate` of null reads everything up to `toDate`, overdue rows included. Mine means a grant
 * the person owns, or for a requirement also one assigned to the person.
 */
public with sharing class GrantDeadlineSelector {
    /** Grants before submitting whose Application Deadline falls in the range. */
    public static List<Grant__c> applications(
        Date fromDate,
        Date toDate,
        Boolean mineOnly,
        Integer maxRows
    ) {
        return (List<Grant__c>) Database.queryWithBinds(
            'SELECT Id, Name, Stage__c, Funder__c, Funder__r.Name, Amount_Requested__c,' +
                ' Application_Deadline__c, Next_Step__c, Owner.Name FROM Grant__c' +
                ' WHERE Stage__c IN :beforeSubmitting AND Application_Deadline__c != null' +
                ' AND Application_Deadline__c <= :toDate' +
                (fromDate == null ? '' : ' AND Application_Deadline__c >= :fromDate') +
                (mineOnly == true ? ' AND OwnerId = :ownerId' : '') +
                ' ORDER BY Application_Deadline__c ASC, Name LIMIT :maxRows',
            binds(fromDate, toDate, maxRows),
            AccessLevel.USER_MODE
        );
    }

    /** Open requirements due in the range; empty when the person cannot read requirements. */
    public static List<Grant_Requirement__c> requirements(
        Date fromDate,
        Date toDate,
        Boolean mineOnly,
        Integer maxRows
    ) {
        if (!Schema.SObjectType.Grant_Requirement__c.isAccessible()) {
            return new List<Grant_Requirement__c>();
        }
        Map<String, Object> binds = binds(fromDate, toDate, maxRows);
        binds.put('openStatuses', GrantRequirementService.OPEN_STATUSES);
        return (List<Grant_Requirement__c>) Database.queryWithBinds(
            'SELECT Id, Name, Type__c, Due_Date__c, Grant__c, Grant__r.Name,' +
                ' Grant__r.Funder__c, Grant__r.Funder__r.Name, Assigned_To__r.Name' +
                ' FROM Grant_Requirement__c WHERE Status__c IN :openStatuses' +
                ' AND Due_Date__c <= :toDate' +
                (fromDate == null ? '' : ' AND Due_Date__c >= :fromDate') +
                (mineOnly == true
                    ? ' AND (Assigned_To__c = :ownerId OR Grant__r.OwnerId = :ownerId)'
                    : '') +
                ' ORDER BY Due_Date__c ASC, Name LIMIT :maxRows',
            binds,
            AccessLevel.USER_MODE
        );
    }

    /** Expected payments due in the range; empty when the person cannot read payments. */
    public static List<Grant_Payment__c> expectedPayments(
        Date fromDate,
        Date toDate,
        Boolean mineOnly,
        Integer maxRows
    ) {
        if (!Schema.SObjectType.Grant_Payment__c.isAccessible()) {
            return new List<Grant_Payment__c>();
        }
        Map<String, Object> binds = binds(fromDate, toDate, maxRows);
        binds.put('expected', GrantPaymentService.STATUS_EXPECTED);
        return (List<Grant_Payment__c>) Database.queryWithBinds(
            'SELECT Id, Name, Due_Date__c, Amount__c, Grant__c, Grant__r.Name,' +
                ' Grant__r.Funder__c, Grant__r.Funder__r.Name, Grant__r.Owner.Name' +
                ' FROM Grant_Payment__c WHERE Status__c = :expected' +
                ' AND Due_Date__c <= :toDate' +
                (fromDate == null ? '' : ' AND Due_Date__c >= :fromDate') +
                (mineOnly == true ? ' AND Grant__r.OwnerId = :ownerId' : '') +
                ' ORDER BY Due_Date__c ASC, Name LIMIT :maxRows',
            binds,
            AccessLevel.USER_MODE
        );
    }

    private static Map<String, Object> binds(Date fromDate, Date toDate, Integer maxRows) {
        return new Map<String, Object>{
            'beforeSubmitting' => GrantService.BEFORE_SUBMITTING,
            'fromDate' => fromDate,
            'toDate' => toDate,
            'maxRows' => maxRows,
            'ownerId' => UserInfo.getUserId()
        };
    }
}
