/**
 * A stand-in module for the Form attachment seam's tests. Core resolves it by name, as it would
 * Event Management's class, so the tests reach nothing in Core but its accessible members.
 */
@IsTest
public with sharing class FormsTestModule implements FormAttachmentExtension {
	/** The form it attaches to any organization, or null for none. */
	public static Id attachedFormId;
	/** The receipts it was handed. */
	public static List<FormSubmissionReceipt> heard = new List<FormSubmissionReceipt>();
	/** Whether taking a receipt fails, as a module refusing it would. */
	public static Boolean fail = false;

	/** Registers this module with Core's seam, alone, with nothing heard yet. */
	public static void register() {
		FormAttachmentExtensions.EXTENSION_CLASSES.clear();
		FormAttachmentExtensions.EXTENSION_CLASSES.add('FormsTestModule');
		heard.clear();
		fail = false;
	}

	public Boolean handles(Schema.SObjectType contextType) {
		return contextType == Account.SObjectType;
	}

	public Id formFor(Id contextRecordId) {
		return attachedFormId;
	}

	public void received(FormSubmissionReceipt receipt) {
		if (fail) {
			throw new System.TypeException('Registration closed');
		}
		heard.add(receipt);
	}
}
