/**
 * The seam a module uses to offer an action on a Portal Builder page, such as signing up for a
 * volunteer shift (PB-03), without either package depending on the other (ADR-0185
 * `0185-portal-builder-off-platform-portal-api.md`, decision 9). A template names the action as
 * `Module.Action`; Portal Builder finds the extension through `PortalActionExtensions`.
 *
 * Portal Builder calls `run` only for a verified portal person and only for a record it has
 * already found on that person's page. The call runs as the portal's integration user, which has
 * no object access of its own, so the extension reads and writes in system mode and must act
 * only for the person it is given.
 */
@NamespaceAccessible
public interface PortalActionExtension {
	/** The action names this module offers, each `Module.Action`. */
	Set<String> actionNames();

	/**
	 * Runs one action for the person on the record. Returns a short message for the person, or
	 * throws to refuse; the message of a refusal is not shown, only that it was refused.
	 */
	String run(String actionName, Id personId, Id recordId);
}
