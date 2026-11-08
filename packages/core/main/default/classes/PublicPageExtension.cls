/**
 * The seam a module uses to publish a public page for its own records, served by whichever
 * package hosts public pages (BarnCRM Forms: its Salesforce Site page and its REST API), without
 * either package depending on the other (ADR-0190 public event pages, decision 1). Event
 * Management is the first user (EV-16).
 *
 * Found by `PublicPageExtensions` with `NamespaceUtil.resolveType`, the mechanism of
 * `FormAttachmentExtensions` (ADR-0175) and `HealthCheckExtensions` (ADR-0057). A page may be
 * asked for by a Site guest user, who has no object access: the module reads, in system mode,
 * only what its own records were explicitly published to show, and returns plain values with
 * every text finished, so a host needs no module vocabulary.
 */
@NamespaceAccessible
public interface PublicPageExtension {
	/** The key of this module's pages, such as `events`. */
	String kind();

	/** Whether this module publishes pages for records of the given object. */
	Boolean handles(Schema.SObjectType recordType);

	/** One record's public page, or null when the record is not published. */
	Map<String, Object> page(Id recordId);

	/** The public list of this module's published records. */
	Map<String, Object> listPage();
}
