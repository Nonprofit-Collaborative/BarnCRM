/**
 * The seam a module uses to attach a BarnCRM Forms form to its own records and to receive what
 * those forms collect, without either package depending on the other (ADR-0175
 * `0175-forms-module.md`, decision 9). Event Management is the first user: an event holds its
 * registration form's record identifier as text, and each processed registration reaches the
 * module in the same transaction as the person it matched or created.
 *
 * Found by `FormAttachmentExtensions` with `NamespaceUtil.resolveType`, the mechanism of
 * `HealthCheckExtensions` (ADR-0057), `WhereUsedExtensions` (ADR-0159) and
 * `RecordGlanceExtensions` (ADR-0167). Everything runs with the person's own access.
 */
@NamespaceAccessible
public interface FormAttachmentExtension {
	/** Whether this module's records of the given object take a form. */
	Boolean handles(Schema.SObjectType contextType);

	/** The form the module attached to one of its records, or null when none. */
	Id formFor(Id contextRecordId);

	/**
	 * Called once a submission filled from one of the module's records is processed: the person
	 * and organization are written, so the module can write its own record for them.
	 */
	void received(FormSubmissionReceipt receipt);
}
