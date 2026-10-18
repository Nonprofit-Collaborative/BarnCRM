/**
 * What the Approve Hours screen calls (V-02, canonical model Section 29M, R-VG5).
 *
 * Lists entries a page at a time, in user mode, and moves them only through
 * `VolunteerHoursService`, which is the one way an entry's status changes. A user without the
 * custom permission `Manage_Volunteers` gets the list marked read only, and is refused before
 * the service is reached if they call a verb anyway. Anything unexpected is recorded in the
 * Error Log before it is reported (plan Section 7.2).
 */
public with sharing class VolunteerHoursApprovalController {
    private static final String CONTEXT = 'Approve Hours screen';
    /** Rows on one page: enough to clear a week's queue, few enough to read on a phone. */
    public static final Integer PAGE_SIZE = 50;
    /** The most entries one verb call moves: a guard on what a crafted call can ask for. */
    public static final Integer MAX_PER_CALL = 500;
    private static final Set<String> STATUSES = new Set<String>{
        VolunteerHoursService.STATUS_SUBMITTED,
        VolunteerHoursService.STATUS_APPROVED,
        VolunteerHoursService.STATUS_REJECTED
    };

    /** One row of the list. */
    public class HoursRow {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public String jobName;
        @AuraEnabled
        public String shiftName;
        @AuraEnabled
        public Date dateWorked;
        @AuraEnabled
        public Decimal hours;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String rejectionReason;
    }

    /** One page of the list, and whether this user may act on it. */
    public class HoursPage {
        @AuraEnabled
        public Boolean canManage = false;
        @AuraEnabled
        public List<HoursRow> rows = new List<HoursRow>();
        @AuraEnabled
        public Boolean hasMore = false;
        @AuraEnabled
        public Integer pageSize = PAGE_SIZE;
    }

    /** What a verb did: how many moved, and each entry it could not move with the reason. */
    public class ActionResult {
        @AuraEnabled
        public Integer moved = 0;
        @AuraEnabled
        public List<Refusal> refused = new List<Refusal>();
    }

    public class Refusal {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String message;
    }

    /**
     * One page of entries in a status (Submitted when none is given), narrowed by job and dates
     * worked. `afterDate` and `afterId` are the last row of the page before, or null for the
     * first page. Not cacheable: the list changes with every approval.
     */
    @AuraEnabled
    public static HoursPage getHours(
        String status,
        Id jobId,
        Date fromDate,
        Date toDate,
        Date afterDate,
        Id afterId
    ) {
        String wanted = String.isBlank(status) ? VolunteerHoursService.STATUS_SUBMITTED : status;
        if (!STATUSES.contains(wanted)) {
            throw badRequest(Label.Volunteers_Approve_ActionFailed);
        }
        try {
            HoursPage page = new HoursPage();
            page.canManage = VolunteerHoursService.canManage();
            List<Volunteer_Hours__c> found = VolunteerHoursSelector.selectForApproval(
                wanted,
                jobId,
                fromDate,
                toDate,
                afterDate,
                afterId,
                PAGE_SIZE + 1
            );
            page.hasMore = found.size() > PAGE_SIZE;
            for (Integer i = 0; i < found.size() && i < PAGE_SIZE; i++) {
                page.rows.add(rowFor(found[i]));
            }
            return page;
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    @AuraEnabled
    public static ActionResult approve(List<Id> hoursIds) {
        Set<Id> ids = checked(hoursIds);
        try {
            return resultOf(VolunteerHoursService.approve(ids));
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /** Rejects the entries for the reason given, which is required (R-VG8). */
    @AuraEnabled
    public static ActionResult reject(List<Id> hoursIds, String reason) {
        Set<Id> ids = checked(hoursIds);
        if (String.isBlank(reason)) {
            throw badRequest(Label.Volunteers_Hours_RejectionReasonRequired);
        }
        try {
            return resultOf(VolunteerHoursService.reject(ids, reason));
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    @AuraEnabled
    public static ActionResult reopen(List<Id> hoursIds) {
        Set<Id> ids = checked(hoursIds);
        try {
            return resultOf(VolunteerHoursService.reopen(ids));
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    // ------------------------------------------------------------------------------ helpers

    /** The permission first, then a list that is present and not too long. */
    private static Set<Id> checked(List<Id> hoursIds) {
        if (!VolunteerHoursService.canManage()) {
            throw badRequest(Label.Volunteers_Hours_NeedManagePermission);
        }
        if (hoursIds == null || hoursIds.isEmpty()) {
            throw badRequest(Label.Volunteers_Approve_NothingSelected);
        }
        if (hoursIds.size() > MAX_PER_CALL) {
            throw badRequest(
                String.format(
                    Label.Volunteers_Approve_TooMany,
                    new List<String>{ String.valueOf(MAX_PER_CALL) }
                )
            );
        }
        return new Set<Id>(hoursIds);
    }

    private static HoursRow rowFor(Volunteer_Hours__c entry) {
        HoursRow row = new HoursRow();
        row.recordId = entry.Id;
        row.name = entry.Name;
        row.personName = entry.Contact__r != null
            ? entry.Contact__r.Name
            : (entry.Account__r != null ? entry.Account__r.Name : null);
        row.jobName = entry.Volunteer_Job__r == null ? null : entry.Volunteer_Job__r.Name;
        row.shiftName = entry.Volunteer_Shift__r == null ? null : entry.Volunteer_Shift__r.Name;
        row.dateWorked = entry.Date_Worked__c;
        row.hours = entry.Hours__c;
        row.status = entry.Status__c;
        row.rejectionReason = entry.Rejection_Reason__c;
        return row;
    }

    private static ActionResult resultOf(VolunteerHoursService.StatusChange change) {
        ActionResult result = new ActionResult();
        result.moved = change.moved;
        for (Id hoursId : change.refused.keySet()) {
            Refusal refusal = new Refusal();
            refusal.recordId = hoursId;
            refusal.message = change.refused.get(hoursId);
            result.refused.add(refusal);
        }
        return result;
    }

    private static AuraHandledException badRequest(String message) {
        AuraHandledException refused = new AuraHandledException(message);
        refused.setMessage(message);
        return refused;
    }

    /** A refusal the service names is passed on as it is; anything else is logged first. */
    private static AuraHandledException report(Exception failure) {
        if (failure instanceof VolunteerHoursService.VolunteerHoursException) {
            return badRequest(failure.getMessage());
        }
        ErrorLogger.log(failure, CONTEXT, null);
        return badRequest(Label.Volunteers_Approve_ActionFailed);
    }
}
