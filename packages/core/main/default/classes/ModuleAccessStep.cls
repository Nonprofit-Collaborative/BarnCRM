/**
 * A module's own step after each pass of Core's access sync for it (ADR-0131, D-200 S1), such
 * as Programs applying its Participant Privacy preset. Registered in the module's catalog row
 * as `ModuleAccessStep: ClassName` (`ModuleExtensions`); the class needs a public no-argument
 * constructor. A failure is logged and never stops the sync.
 */
@NamespaceAccessible
public interface ModuleAccessStep {
	/** Runs after each pass, also while nothing was left to give. */
	void afterSync();
}
