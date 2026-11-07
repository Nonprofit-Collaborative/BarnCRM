/**
 * Lets a module's tests stand in for Forms' catalog extension, since Apex tests of a module that
 * does not depend on Forms cannot rely on Forms being installed (ADR-NEXT
 * `NEXT-event-post-event-survey.md`). Test only.
 */
@IsTest
@NamespaceAccessible
public class FormCatalogTestSupport {
	/** Makes the extension the one `FormCatalogExtensions` finds, for the running test. */
	@NamespaceAccessible
	public static void install(FormCatalogExtension extension) {
		String name = FormCatalogExtensions.EXTENSION_CLASSES[0];
		FormCatalogExtensions.EXTENSION_CLASSES.clear();
		FormCatalogExtensions.EXTENSION_CLASSES.add(name);
		FormCatalogExtensions.overrides = new Map<String, FormCatalogExtension>{
			name => extension
		};
	}
}
