/**
 * The Field History card (C-68, R-FH4): a record's kept changes, for anyone who can read the
 * record, and Restore for admins. FieldHistoryService checks the access.
 */
public with sharing class FieldHistoryController {
	/** The card, in one round trip. */
	public class HistoryView {
		@AuraEnabled
		public Boolean enabled = false;
		@AuraEnabled
		public List<FieldHistoryService.Entry> entries = new List<FieldHistoryService.Entry>();
	}

	@AuraEnabled
	public static HistoryView getHistory(Id recordId) {
		try {
			return viewOf(recordId);
		} catch (Exception caught) {
			throw UserErrors.wrap(caught, 'Field History card', true);
		}
	}

	/** Puts back the value a change replaced, after the card's confirm. */
	@AuraEnabled
	public static HistoryView restore(Id recordId, Id historyId, String fieldName) {
		try {
			FieldHistoryService.restore(historyId, fieldName);
			return viewOf(recordId);
		} catch (Exception caught) {
			if (!(caught instanceof FieldHistoryService.FieldHistoryException)) {
				ErrorLogger.log(caught, 'Field History restore');
			}
			throw UserErrors.wrapShowingDml(caught, Label.Core_UnexpectedError);
		}
	}

	private static HistoryView viewOf(Id recordId) {
		HistoryView view = new HistoryView();
		view.enabled = SettingsService.getSettings().Field_History_Enabled__c == true;
		view.entries = FieldHistoryService.historyFor(recordId);
		return view;
	}
}
