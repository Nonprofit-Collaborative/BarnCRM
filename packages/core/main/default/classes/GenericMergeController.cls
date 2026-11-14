/**
 * The Merge Records area of the Duplicate Matching tab (C-62, R-DP11, R-DP12): compare two
 * records of one BarnCRM object, merge them, and undo a recent merge. Every action needs
 * Manage BarnCRM Settings, as auto-merge does, and the Merge Records setting on.
 */
public with sharing class GenericMergeController {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		null,
		'Core',
		'Core_Duplicates_ErrorUnexpected'
	);

	private static final Integer MAX_SHOWN = 20;

	/** One recent merge, as the list shows it. */
	public class MergeView {
		@AuraEnabled
		public Id journalId;
		@AuraEnabled
		public String objectLabel;
		@AuraEnabled
		public String mergedName;
		@AuraEnabled
		public Id survivorId;
		@AuraEnabled
		public Datetime mergedAt;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Boolean canUndo = false;
		@AuraEnabled
		public String notes;
	}

	/** The area, in one round trip. */
	public class PanelView {
		@AuraEnabled
		public Boolean enabled = false;
		/** The objects offered, as label and value, by label. */
		@AuraEnabled
		public List<Map<String, String>> objects = new List<Map<String, String>>();
		@AuraEnabled
		public List<MergeView> merges = new List<MergeView>();
	}

	@AuraEnabled
	public static PanelView getView() {
		try {
			DuplicateController.requirePermission();
			return currentView();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Merge records panel');
		}
	}

	@AuraEnabled
	public static GenericMergeService.Comparison compare(
		String objectName,
		Id firstId,
		Id secondId
	) {
		try {
			DuplicateController.requirePermission();
			return GenericMergeService.compare(objectName, firstId, secondId);
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Compare two records');
		}
	}

	@AuraEnabled
	public static GenericMergeService.Outcome mergeRecords(
		String objectName,
		Id keepId,
		Id otherId,
		List<String> fromOther
	) {
		try {
			DuplicateController.requirePermission();
			return GenericMergeService.mergeRecords(objectName, keepId, otherId, fromOther);
		} catch (Exception caught) {
			// A refused save shows its own words (a validation rule's, say); nothing was merged.
			if (!(caught instanceof DuplicateService.DuplicateException)) {
				ErrorLogger.log(caught, 'Merge two records');
			}
			throw UserErrors.wrapShowingDml(
				caught,
				BarnHelp.text('Core', 'Core_Duplicates_ErrorUnexpected')
			);
		}
	}

	/** Undoes one merge still marked Merged, within the undo window. */
	@AuraEnabled
	public static PanelView undo(Id journalId) {
		try {
			DuplicateController.requirePermission();
			Datetime since = Datetime.now().addDays(-AutoMergeService.UNDO_DAYS);
			List<Merge_Journal__c> journals = [
				SELECT
					Id,
					Survivor_Id__c,
					Merged_Id__c,
					Merged_Name__c,
					Status__c,
					Changed_Values__c,
					Moved_Records__c,
					Notes__c
				FROM Merge_Journal__c
				WHERE
					Id = :journalId
					AND Status__c = :AutoMergeService.MERGED
					AND CreatedDate >= :since
				WITH USER_MODE
			];
			if (journals.isEmpty()) {
				throw new DuplicateService.DuplicateException(
					BarnHelp.text('Core', 'Core_GenericMerge_ErrorNoUndo')
				);
			}
			AutoMergeService.undo(journals);
			return currentView();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Undo a merge');
		}
	}

	private static PanelView currentView() {
		PanelView view = new PanelView();
		view.enabled = SettingsService.getSettings().Generic_Merge_Enabled__c == true;
		if (!view.enabled) {
			return view;
		}
		Map<String, String> offered = GenericMergeService.objects();
		Map<String, String> byLabel = new Map<String, String>();
		for (String name : offered.keySet()) {
			byLabel.put(offered.get(name) + '|' + name, name);
		}
		List<String> labels = new List<String>(byLabel.keySet());
		labels.sort();
		for (String key : labels) {
			view.objects.add(
				new Map<String, String>{
					'label' => key.substringBefore('|'),
					'value' => byLabel.get(key)
				}
			);
		}
		Datetime since = Datetime.now().addDays(-AutoMergeService.UNDO_DAYS);
		// Merges of anything but people: auto-merge lists those.
		String people =
			Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + '%';
		for (Merge_Journal__c journal : [
			SELECT Id, Survivor_Id__c, Merged_Name__c, Status__c, Notes__c, CreatedDate
			FROM Merge_Journal__c
			WHERE CreatedDate >= :since AND (NOT Survivor_Id__c LIKE :people)
			WITH USER_MODE
			ORDER BY CreatedDate DESC
			LIMIT :MAX_SHOWN
		]) {
			MergeView row = new MergeView();
			row.journalId = journal.Id;
			row.survivorId = journal.Survivor_Id__c;
			row.objectLabel = Id.valueOf(journal.Survivor_Id__c)
				.getSObjectType()
				.getDescribe(SObjectDescribeOptions.DEFERRED)
				.getLabel();
			row.mergedName = journal.Merged_Name__c;
			row.mergedAt = journal.CreatedDate;
			row.status = journal.Status__c;
			row.canUndo = journal.Status__c == AutoMergeService.MERGED;
			row.notes = journal.Notes__c;
			view.merges.add(row);
		}
		return view;
	}
}
