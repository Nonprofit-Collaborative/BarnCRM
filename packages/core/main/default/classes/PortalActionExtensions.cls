/**
 * Finds the portal action extensions modules installed (ADR-0185
 * `0185-portal-builder-off-platform-portal-api.md`, decision 9), the pattern
 * `FormAttachmentExtensions` uses (ADR-0175). A class that is not installed, cannot be built or
 * does not implement the interface is absent, and a failure is logged: a portal works without
 * any module's actions.
 */
@NamespaceAccessible
public with sharing class PortalActionExtensions {
	/** The class names modules register: Volunteers (PB-03) and Event Management (PB-07). */
	@NamespaceAccessible
	public static final List<String> EXTENSION_CLASSES = new List<String>{
		'VolunteersPortalExtension',
		'EventsPortalExtension'
	};

	/** Injected by tests by class name, since no module is there to resolve. */
	@TestVisible
	private static Map<String, PortalActionExtension> overrides = new Map<String, PortalActionExtension>();

	/** The installed extension offering this action, or null when no installed module does. */
	@NamespaceAccessible
	public static PortalActionExtension forAction(String actionName) {
		if (String.isBlank(actionName)) {
			return null;
		}
		for (String className : EXTENSION_CLASSES) {
			PortalActionExtension extension = overrides.containsKey(className)
				? overrides.get(className)
				: resolve(className);
			if (extension == null) {
				continue;
			}
			try {
				Set<String> names = extension.actionNames();
				if (names != null && names.contains(actionName)) {
					return extension;
				}
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'PortalActionExtensions.forAction');
			}
		}
		return null;
	}

	private static PortalActionExtension resolve(String className) {
		return (PortalActionExtension) NamespaceUtil.build(
			className,
			PortalActionExtension.class,
			'PortalActionExtensions.resolve'
		);
	}
}
