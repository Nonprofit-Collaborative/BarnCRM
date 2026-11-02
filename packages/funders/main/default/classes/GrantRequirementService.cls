/**
 * The rules of a grant requirement (canonical model 29ZI, ADR-0161 `0161-funders-module.md`):
 * which statuses are open (R-GQ1), the submitted date (R-GQ2), and marking one submitted from the
 * Grant Pipeline.
 */
public with sharing class GrantRequirementService {
    public static final String STATUS_NOT_STARTED = 'Not Started';
    public static final String STATUS_IN_PROGRESS = 'In Progress';
    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_ACCEPTED = 'Accepted';
    public static final String STATUS_WAIVED = 'Waived';

    /** R-GQ1: the open statuses; only these are reminded, counted overdue or listed. */
    public static final List<String> OPEN_STATUSES = new List<String>{
        STATUS_NOT_STARTED,
        STATUS_IN_PROGRESS
    };

    private static final Set<String> SENT = new Set<String>{ STATUS_SUBMITTED, STATUS_ACCEPTED };

    public static Boolean isOpen(String status) {
        return OPEN_STATUSES.contains(status);
    }

    /**
     * R-GQ2: an empty Submitted Date becomes today when a requirement becomes Submitted or
     * Accepted. A date already there is kept.
     *
     * @param requirements the requirements being saved
     * @param oldById their saved versions, null on insert
     */
    public static void fillSubmittedDates(
        List<Grant_Requirement__c> requirements,
        Map<Id, Grant_Requirement__c> oldById
    ) {
        Date today = Date.today();
        for (Grant_Requirement__c requirement : requirements) {
            Grant_Requirement__c old = oldById == null ? null : oldById.get(requirement.Id);
            if (old != null && old.Status__c == requirement.Status__c) {
                continue;
            }
            if (SENT.contains(requirement.Status__c) && requirement.Submitted_Date__c == null) {
                requirement.Submitted_Date__c = today;
            }
        }
    }

    /**
     * Marks one requirement Submitted, as the person: the dates automation fills the Submitted
     * Date.
     */
    public static void markSubmitted(Id requirementId) {
        update as user new Grant_Requirement__c(Id = requirementId, Status__c = STATUS_SUBMITTED);
    }
}
