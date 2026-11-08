/**
 * One choice a form catalog offers a module: a form (key is its record identifier) or one of a
 * form's questions (key is the question's key). Plain values, so neither package needs the
 * other's types (ADR-NEXT `NEXT-event-post-event-survey.md`).
 */
@NamespaceAccessible
public with sharing class FormCatalogEntry {
	@NamespaceAccessible
	public String key;
	@NamespaceAccessible
	public String label;
	/** A question's type (text, number, picklist and so on); empty for a form. */
	@NamespaceAccessible
	public String kind;

	@NamespaceAccessible
	public FormCatalogEntry() {
		// Filled in field by field by the extension.
	}
}
