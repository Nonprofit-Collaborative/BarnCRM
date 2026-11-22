/**
 * The rules of a grant requirement (canonical model 29ZI, ADR-0161 `0161-funders-module.md`):
 * which statuses are open (R-GQ1) and marking one submitted from the Grant Pipeline. The submitted
 * date (R-GQ2) is the before-save flow Grant_Requirement_Dates.
 */
public with sharing class GrantRequirementService {
	public static final String STATUS_NOT_STARTED = 'Not Started';
	public static final String STATUS_IN_PROGRESS = 'In Progress';
	public static final String STATUS_SUBMITTED = 'Submitted';
	public static final String STATUS_ACCEPTED = 'Accepted';
	public static final String STATUS_WAIVED = 'Waived';
	public static final String STATUS_DONE = 'Done';
	/** R-GQ7: a checklist step. */
	public static final String TYPE_TASK = 'Task';
	/** R-GN12: the renewal application. */
	public static final String TYPE_RENEWAL = 'Renewal';
	/** R-GQ8: the requirement types that are documents with files. */
	public static final List<String> DOCUMENT_TYPES = new List<String>{
		'Letter of Inquiry',
		'Application',
		'Narrative Report',
		'Financial Report'
	};

	/** R-GQ1: the open statuses; only these are reminded, counted overdue or listed. */
	public static final List<String> OPEN_STATUSES = new List<String>{ STATUS_NOT_STARTED, STATUS_IN_PROGRESS };

	public static Boolean isOpen(String status) {
		return OPEN_STATUSES.contains(status);
	}

	/**
	 * Marks one requirement Submitted, as the person: the dates automation (R-GQ2, the before-save
	 * flow Grant_Requirement_Dates) fills the Submitted Date. Returns what it replaced, for Undo (modules-17).
	 */
	public static FundersUndoState markSubmitted(Id requirementId) {
		FundersUndoState previous = new FundersUndoState();
		for (Grant_Requirement__c row : [
			SELECT Id, Status__c, Submitted_Date__c
			FROM Grant_Requirement__c
			WHERE Id = :requirementId
			WITH USER_MODE
			LIMIT 1
		]) {
			previous.id = row.Id;
			previous.status = row.Status__c;
			previous.dateValue = row.Submitted_Date__c;
		}
		update as user new Grant_Requirement__c(Id = requirementId, Status__c = STATUS_SUBMITTED);
		return previous;
	}

	/**
	 * Undo for Mark Submitted (modules-17): puts back the open status and the Submitted Date the
	 * requirement had, as the person. Only a requirement still Submitted goes back, and only to an
	 * open status; anything changed since is left alone.
	 *
	 * @return true when it was put back
	 */
	public static Boolean undoSubmitted(Id requirementId, String status, Date submittedDate) {
		if (requirementId == null || !isOpen(status)) {
			return false;
		}
		List<Grant_Requirement__c> rows = [
			SELECT Id, Status__c
			FROM Grant_Requirement__c
			WHERE Id = :requirementId
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty() || rows[0].Status__c != STATUS_SUBMITTED) {
			return false;
		}
		update as user new Grant_Requirement__c(
			Id = requirementId,
			Status__c = status,
			Submitted_Date__c = submittedDate
		);
		return true;
	}
}
