/**
 * The seam a module uses to offer a person the forms that can be filled in by anyone with a link,
 * and to build that link, without depending on the module that keeps forms (ADR-0188
 * `0188-event-post-event-survey.md`). Event Management's post-event survey (EV-18) is the first
 * user. Found by `FormCatalogExtensions`; absent when Forms is not installed. Everything runs
 * with the person's own access.
 */
@NamespaceAccessible
public interface FormCatalogExtension {
	/** The published forms that accept public answers (key: record identifier, label: name). */
	List<FormCatalogEntry> publicForms();

	/** The questions of a form, in order (key: question key, label: question text). */
	List<FormCatalogEntry> questions(Id formId);

	/**
	 * The address a person with no login opens to fill in the form, tied to a record the form
	 * was filled from; null when the form is not public or no Site can serve it.
	 */
	String publicLink(Id formId, Id contextRecordId);
}
