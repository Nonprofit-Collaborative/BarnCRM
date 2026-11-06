/**
 * What a one-click Funders change replaced (modules-17), sent to the browser so its Undo can put
 * it back: the record, its status before, and the date field the change stamps (a requirement's
 * Submitted Date, a payment's Received Date) as it was before.
 */
public with sharing class FundersUndoState {
	@AuraEnabled
	public String id;
	@AuraEnabled
	public String status;
	@AuraEnabled
	public Date dateValue;
}
