/**
 * What a module hears about one processed form submission (ADR-NEXT `NEXT-forms-module.md`,
 * decision 9; canonical model R-FS4). Plain values only, so neither Forms nor the module needs
 * the other's types.
 */
@NamespaceAccessible
public with sharing class FormSubmissionReceipt {
	/** The form filled in. */
	@NamespaceAccessible
	public Id formId;
	/** The form's name, for a message or a log line. */
	@NamespaceAccessible
	public String formName;
	/** The Form Submission record. */
	@NamespaceAccessible
	public Id submissionId;
	/** The module's record the form was filled from. */
	@NamespaceAccessible
	public Id contextRecordId;
	/** The person matched or created, or null when the form writes no person. */
	@NamespaceAccessible
	public Id personId;
	/** The organization matched or created, or null when the form writes none. */
	@NamespaceAccessible
	public Id organizationId;
	/** The answers that counted (hidden questions left out), by field key. */
	@NamespaceAccessible
	public Map<String, Object> answers = new Map<String, Object>();
	/** Every record the submission wrote or matched, by the record key the form gives it. */
	@NamespaceAccessible
	public Map<String, Id> recordIds = new Map<String, Id>();

	@NamespaceAccessible
	public FormSubmissionReceipt() {
		// Filled in field by field by the Forms module.
	}
}
