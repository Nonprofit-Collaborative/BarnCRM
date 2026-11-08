/**
 * Finds the form catalog extension Forms installed (ADR-NEXT `NEXT-event-post-event-survey.md`),
 * or answers that there is none, the ordinary case in an org without Forms. A class that is not
 * installed, cannot be built or does not implement the interface is absent, and a failure is
 * logged: a module's page must load whatever Forms does.
 */
@NamespaceAccessible
public with sharing class FormCatalogExtensions {
	/** The class names modules register. Forms registers its class here. */
	@NamespaceAccessible
	public static final List<String> EXTENSION_CLASSES = new List<String>{
		'FormsCatalogExtension'
	};

	/** Injected by tests by class name, since no module is there to resolve. */
	@TestVisible
	private static Map<String, FormCatalogExtension> overrides = new Map<String, FormCatalogExtension>();

	/** Whether a module keeps forms. */
	@NamespaceAccessible
	public static Boolean isAvailable() {
		return first() != null;
	}

	/** The published forms that accept public answers; empty when no module keeps forms. */
	@NamespaceAccessible
	public static List<FormCatalogEntry> publicForms() {
		FormCatalogExtension extension = first();
		if (extension == null) {
			return new List<FormCatalogEntry>();
		}
		try {
			return extension.publicForms();
		} catch (Exception failed) {
			ErrorLogger.log(failed, 'FormCatalogExtensions.publicForms');
			return new List<FormCatalogEntry>();
		}
	}

	/** A form's questions in order; empty when unknown. */
	@NamespaceAccessible
	public static List<FormCatalogEntry> questions(Id formId) {
		FormCatalogExtension extension = first();
		if (extension == null || formId == null) {
			return new List<FormCatalogEntry>();
		}
		try {
			return extension.questions(formId);
		} catch (Exception failed) {
			ErrorLogger.log(failed, 'FormCatalogExtensions.questions', formId);
			return new List<FormCatalogEntry>();
		}
	}

	/** The public address of a form for a record, or null when there is none. */
	@NamespaceAccessible
	public static String publicLink(Id formId, Id contextRecordId) {
		FormCatalogExtension extension = first();
		if (extension == null || formId == null) {
			return null;
		}
		try {
			return extension.publicLink(formId, contextRecordId);
		} catch (Exception failed) {
			ErrorLogger.log(failed, 'FormCatalogExtensions.publicLink', formId);
			return null;
		}
	}

	private static FormCatalogExtension first() {
		for (String className : EXTENSION_CLASSES) {
			FormCatalogExtension extension = overrides.containsKey(className)
				? overrides.get(className)
				: resolve(className);
			if (extension != null) {
				return extension;
			}
		}
		return null;
	}

	private static FormCatalogExtension resolve(String className) {
		Type extensionType = NamespaceUtil.resolveType(className);
		if (extensionType == null) {
			return null;
		}
		Object candidate;
		try {
			candidate = extensionType.newInstance();
		} catch (Exception cannotBuild) {
			ErrorLogger.log(cannotBuild, 'FormCatalogExtensions.resolve');
			return null;
		}
		if (candidate instanceof FormCatalogExtension) {
			return (FormCatalogExtension) candidate;
		}
		ErrorLogger.log(
			new System.TypeException(className + ' does not implement FormCatalogExtension'),
			'FormCatalogExtensions.resolve'
		);
		return null;
	}
}
