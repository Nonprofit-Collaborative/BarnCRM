/**
 * Finds the public page extensions modules installed (ADR-0190 public event pages, decision 1),
 * the pattern `FormAttachmentExtensions` uses (ADR-0175). A class that is not installed, cannot
 * be built or does not implement the interface is absent, and a failure is logged and answered
 * as "no page": a public address never shows an error's detail.
 */
@NamespaceAccessible
public with sharing class PublicPageExtensions {
	/** The class names modules register: Event Management's event pages (EV-16). */
	@NamespaceAccessible
	public static final List<String> EXTENSION_CLASSES = new List<String>{ 'EventPublicPage' };

	/** The module key of the package that serves public pages (BarnCRM Forms). */
	private static final String HOST_MODULE = 'Forms';

	/** Injected by tests by class name, since no module is there to resolve. */
	@TestVisible
	private static Map<String, PublicPageExtension> overrides = new Map<String, PublicPageExtension>();

	/** Set by tests: whether a host is installed. */
	@TestVisible
	private static Boolean hostForTest;

	/**
	 * Lets a module's test say whether a host is installed (`@TestVisible` does not cross a
	 * package boundary); null resolves by name again. Ignored outside tests.
	 */
	@NamespaceAccessible
	public static void setHostInstalledForTest(Boolean installed) {
		if (Test.isRunningTest()) {
			hostForTest = installed;
		}
	}

	/**
	 * Lets a host's test stand in a module's pages, as the only extension. Ignored outside tests.
	 */
	@NamespaceAccessible
	public static void useForTest(PublicPageExtension extension) {
		if (Test.isRunningTest()) {
			EXTENSION_CLASSES.clear();
			EXTENSION_CLASSES.add('TestPublicPage');
			overrides = new Map<String, PublicPageExtension>{ 'TestPublicPage' => extension };
		}
	}

	/** Whether a package that serves public pages (BarnCRM Forms) is installed. */
	@NamespaceAccessible
	public static Boolean hostInstalled() {
		if (hostForTest != null) {
			return hostForTest;
		}
		for (ModuleManagerService.ModuleStatus module : ModuleManagerService.getModules()) {
			if (HOST_MODULE.equalsIgnoreCase(module.getName())) {
				return module.getStatus() != ModuleManagerService.STATUS_NOT_INSTALLED;
			}
		}
		return false;
	}

	/** One record's public page, or null when no module publishes it. */
	@NamespaceAccessible
	public static Map<String, Object> page(Id recordId) {
		if (recordId == null) {
			return null;
		}
		Schema.SObjectType type = recordId.getSObjectType();
		for (PublicPageExtension extension : installed()) {
			try {
				if (extension.handles(type) == true) {
					return extension.page(recordId);
				}
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'PublicPageExtensions.page', recordId);
				return null;
			}
		}
		return null;
	}

	/** The public list of one kind of page, or null when no module offers it. */
	@NamespaceAccessible
	public static Map<String, Object> listPage(String kind) {
		if (String.isBlank(kind)) {
			return null;
		}
		for (PublicPageExtension extension : installed()) {
			try {
				if (kind.trim().equalsIgnoreCase(extension.kind())) {
					return extension.listPage();
				}
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'PublicPageExtensions.listPage');
				return null;
			}
		}
		return null;
	}

	private static List<PublicPageExtension> installed() {
		List<PublicPageExtension> found = new List<PublicPageExtension>();
		for (String className : EXTENSION_CLASSES) {
			PublicPageExtension extension = overrides.containsKey(className)
				? overrides.get(className)
				: resolve(className);
			if (extension != null) {
				found.add(extension);
			}
		}
		return found;
	}

	private static PublicPageExtension resolve(String className) {
		return (PublicPageExtension) NamespaceUtil.build(
			className,
			PublicPageExtension.class,
			'PublicPageExtensions.resolve'
		);
	}
}
