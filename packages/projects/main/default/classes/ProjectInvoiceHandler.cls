/**
 * The one rule on deleting a project invoice (registry row `Project_Invoice_Delete_Guard`,
 * Always Runs; canonical model R-PM17): only a Draft can be deleted. Deleting a Sent, Paid or Void
 * invoice would free the work on its lines to be billed again, which is what Void is for. Adds an
 * error to the refused records only: no DML.
 */
@NamespaceAccessible
public with sharing class ProjectInvoiceHandler extends TriggerHandler {
	/** Built by name from Core's dispatcher, so it needs a public constructor. */
	@NamespaceAccessible
	public ProjectInvoiceHandler() {
		return;
	}

	public override void beforeDelete() {
		List<SObject> deleting = oldRecords();
		if (deleting == null) {
			return;
		}
		for (SObject row : deleting) {
			if (row.get('Status__c') != ProjectBilling.DRAFT) {
				row.addError(BarnHelp.text('Projects', 'Projects_Invoice_DeleteBlocked'));
			}
		}
	}
}
