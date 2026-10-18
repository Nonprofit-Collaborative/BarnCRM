/**
 * Volunteer hours: entering them and moving them through approval (V-02, canonical model
 * Section 29M, ADR-0127 decision 4).
 *
 * The four verbs are submit, approve, reject and reopen. Submit creates entries and is open to
 * anyone who may create them; the other three move Status, Approved By and Approved Date and
 * need the custom permission `Manage_Volunteers` (R-VG5). They are the only way those fields
 * change: the hours rules refuse a change made any other way, so "Approved" always means a
 * coordinator, or the Hours Require Approval setting, said so.
 *
 * The record rules the hours automation applies on every save (the starting status, the job
 * from the shift, the household from the person) live here too, as methods that take explicit
 * lists, so `VolunteerHoursTriggerHandler` stays a wrapper.
 */
public with sharing class VolunteerHoursService {
    public static final String MANAGE_PERMISSION = 'Manage_Volunteers';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';

    /** The entries a verb is moving right now: the only ones whose status may change. */
    private static Set<Id> beingMoved = new Set<Id>();

    public class VolunteerHoursException extends Exception {
    }

    /**
     * Whether the running user may approve, reject and reopen hours. Asked each time, not
     * cached: the check costs no query, and a cached answer would outlive a `System.runAs`.
     */
    public static Boolean canManage() {
        return FeatureManagement.checkPermission(MANAGE_PERMISSION);
    }

    // ----------------------------------------------------------------------------- the verbs

    /**
     * Creates these entries, in user mode. Each starts Submitted, or Approved by the running
     * user now when Hours Require Approval is off (R-VG6); the hours rules decide which as the
     * entries are saved, so an entry created any other way starts the same.
     */
    public static List<Database.SaveResult> submit(List<Volunteer_Hours__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(entries, false, AccessLevel.USER_MODE);
    }

    /**
     * Approves these entries: Approved By and Approved Date are the running user and now, and a
     * rejection reason left from an earlier rejection is cleared. An entry already Approved is
     * left as it is. Returns how many it moved.
     */
    public static Integer approve(Set<Id> hoursIds) {
        requirePermission();
        Datetime now = Datetime.now();
        List<Volunteer_Hours__c> moves = new List<Volunteer_Hours__c>();
        for (Volunteer_Hours__c entry : VolunteerHoursSelector.selectForStatusChange(hoursIds)) {
            if (entry.Status__c != STATUS_APPROVED) {
                moves.add(move(entry.Id, STATUS_APPROVED, UserInfo.getUserId(), now, null));
            }
        }
        save(moves);
        return moves.size();
    }

    /**
     * Rejects these entries for the reason given, which is required (R-VG8). Approved By and
     * Approved Date record who rejected them and when. An entry already Rejected keeps its
     * first reason. Returns how many it moved.
     */
    public static Integer reject(Set<Id> hoursIds, String reason) {
        requirePermission();
        if (String.isBlank(reason)) {
            throw new VolunteerHoursException(Label.Volunteers_Hours_RejectionReasonRequired);
        }
        String trimmed = reason.trim().abbreviate(255);
        Datetime now = Datetime.now();
        List<Volunteer_Hours__c> moves = new List<Volunteer_Hours__c>();
        for (Volunteer_Hours__c entry : VolunteerHoursSelector.selectForStatusChange(hoursIds)) {
            if (entry.Status__c != STATUS_REJECTED) {
                moves.add(move(entry.Id, STATUS_REJECTED, UserInfo.getUserId(), now, trimmed));
            }
        }
        save(moves);
        return moves.size();
    }

    /**
     * Moves these Approved or Rejected entries back to Submitted and clears who decided, when,
     * and why, so the entry can be corrected and decided again (R-VG7). Returns how many it
     * moved.
     */
    public static Integer reopen(Set<Id> hoursIds) {
        requirePermission();
        List<Volunteer_Hours__c> moves = new List<Volunteer_Hours__c>();
        for (Volunteer_Hours__c entry : VolunteerHoursSelector.selectForStatusChange(hoursIds)) {
            if (entry.Status__c != STATUS_SUBMITTED) {
                moves.add(move(entry.Id, STATUS_SUBMITTED, null, null, null));
            }
        }
        save(moves);
        return moves.size();
    }

    // ---------------------------------------------------------------- the rules on every save

    /**
     * R-VG5 and R-VG6 for new entries saved outside the verbs: an entry is saved Submitted,
     * or Approved by the saving user now when Hours Require Approval is off. Naming any other
     * status is refused. Approved By and Approved Date are the module's to write.
     */
    public static void applyStartingStatus(List<Volunteer_Hours__c> entries) {
        Boolean approvalRequired = VolunteerSettings.hoursRequireApproval();
        Datetime now = Datetime.now();
        for (Volunteer_Hours__c entry : entries) {
            String named = String.isBlank(entry.Status__c) ? STATUS_SUBMITTED : entry.Status__c;
            Boolean allowed =
                named == STATUS_SUBMITTED || (named == STATUS_APPROVED && !approvalRequired);
            if (!allowed) {
                entry.addError(Label.Volunteers_Hours_StatusThroughApproval);
                continue;
            }
            if (approvalRequired) {
                entry.Status__c = STATUS_SUBMITTED;
                entry.Approved_By__c = null;
                entry.Approved_Date__c = null;
            } else {
                entry.Status__c = STATUS_APPROVED;
                entry.Approved_By__c = UserInfo.getUserId();
                entry.Approved_Date__c = now;
            }
        }
    }

    /**
     * R-VG5 for saved entries: Status, Approved By and Approved Date change only while a verb
     * is moving the entry. A change made any other way is refused, naming the way to make it.
     */
    public static void refuseStatusChangesOutsideTheService(
        List<Volunteer_Hours__c> entries,
        Map<Id, Volunteer_Hours__c> previousById
    ) {
        for (Volunteer_Hours__c entry : entries) {
            Volunteer_Hours__c previous = previousById.get(entry.Id);
            if (previous == null || beingMoved.contains(entry.Id)) {
                continue;
            }
            if (
                entry.Status__c != previous.Status__c ||
                entry.Approved_By__c != previous.Approved_By__c ||
                entry.Approved_Date__c != previous.Approved_Date__c
            ) {
                entry.addError(Label.Volunteers_Hours_StatusThroughApproval);
            }
        }
    }

    /**
     * R-VG3: an entry naming a shift carries that shift's job, so a shift deleted later leaves
     * the hours with their job. A shift the user cannot see leaves the job as it was typed.
     */
    public static void fillJobsFromShifts(List<Volunteer_Hours__c> entries) {
        Set<Id> shiftIds = new Set<Id>();
        for (Volunteer_Hours__c entry : entries) {
            if (entry.Volunteer_Shift__c != null) {
                shiftIds.add(entry.Volunteer_Shift__c);
            }
        }
        if (shiftIds.isEmpty()) {
            return;
        }
        Map<Id, Volunteer_Shift__c> shifts = VolunteerShiftSelector.selectByIds(shiftIds);
        for (Volunteer_Hours__c entry : entries) {
            Volunteer_Shift__c shift = shifts.get(entry.Volunteer_Shift__c);
            if (shift != null) {
                entry.Volunteer_Job__c = shift.Volunteer_Job__c;
            }
        }
    }

    /**
     * R-VG2: the household credited with each entry is the person's household as Core answers
     * it, in either membership mode (as R-G2 does for a gift), and empty when the person has
     * none or the entry names nobody.
     */
    public static void deriveHouseholds(List<Volunteer_Hours__c> entries) {
        Set<Id> personIds = new Set<Id>();
        for (Volunteer_Hours__c entry : entries) {
            Id personId = personOf(entry);
            if (personId != null) {
                personIds.add(personId);
            }
        }
        Map<Id, Id> householdByPerson = personIds.isEmpty()
            ? new Map<Id, Id>()
            : HouseholdService.getHouseholdIdsFor(personIds);
        for (Volunteer_Hours__c entry : entries) {
            Id personId = personOf(entry);
            entry.Household__c = personId == null ? null : householdByPerson.get(personId);
        }
    }

    /** The entry's person: the contact, or the account when there is no contact. */
    public static Id personOf(Volunteer_Hours__c entry) {
        return entry.Contact__c != null ? entry.Contact__c : entry.Account__c;
    }

    // ------------------------------------------------------------------------------ helpers

    private static void requirePermission() {
        if (!canManage()) {
            throw new VolunteerHoursException(Label.Volunteers_Hours_NeedManagePermission);
        }
    }

    /** An entry carrying only its Id and the four fields a verb moves. */
    private static Volunteer_Hours__c move(
        Id hoursId,
        String status,
        Id decidedBy,
        Datetime decidedAt,
        String reason
    ) {
        return new Volunteer_Hours__c(
            Id = hoursId,
            Status__c = status,
            Approved_By__c = decidedBy,
            Approved_Date__c = decidedAt,
            Rejection_Reason__c = reason
        );
    }

    /**
     * Saves the moves with these entries open to a status change, and closes them again
     * whatever happens. The earlier open set is restored rather than emptied.
     */
    private static void save(List<Volunteer_Hours__c> moves) {
        if (moves.isEmpty()) {
            return;
        }
        Set<Id> wasOpen = beingMoved;
        try {
            Set<Id> open = new Set<Id>(wasOpen);
            open.addAll(new Map<Id, Volunteer_Hours__c>(moves).keySet());
            beingMoved = open;
            VolunteerHoursWriter.save(moves);
        } finally {
            beingMoved = wasOpen;
        }
    }
}
