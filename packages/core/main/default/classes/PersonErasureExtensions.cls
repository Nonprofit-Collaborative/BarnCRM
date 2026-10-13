/**
 * Finds the person erasure extensions dependent packages installed (canonical model R-ER8;
 * ADR-NEXT `NEXT-erase-a-person-anonymizes-in-place.md`), by namespace and class name as
 * `HouseholdDependentsExtensions` does (ADR-0017).
 *
 * One rule differs from the other seams on purpose: an extension that is installed but cannot be
 * built, or does not implement the interface, refuses the erasure. Leaving it out would erase
 * the person in Core and report done while the module's records about them stayed.
 */
@NamespaceAccessible
public with sharing class PersonErasureExtensions {
    /** The class names dependent packages register, in the order they are asked. */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'GivingPersonErasureExtension'
    };

    /** Injected by Core's tests, since no other package is there to resolve. */
    @TestVisible
    private static List<PersonErasureExtension> overrides = new List<PersonErasureExtension>();

    /** Set by Core's tests to see the org as having no extension beyond those injected. */
    @TestVisible
    private static Boolean noneForTest = false;

    /**
     * Every installed extension, in registration order. Throws `PersonErasure.ErasureException`
     * when one is installed but unusable.
     */
    @NamespaceAccessible
    public static List<PersonErasureExtension> installed() {
        List<PersonErasureExtension> result = new List<PersonErasureExtension>(overrides);
        if (noneForTest == true) {
            return result;
        }
        for (String className : EXTENSION_CLASSES) {
            PersonErasureExtension extension = resolve(className);
            if (extension != null) {
                result.add(extension);
            }
        }
        return result;
    }

    private static PersonErasureExtension resolve(String className) {
        String prefix = NamespaceUtil.prefix();
        Type extensionType = Type.forName(
            String.isBlank(prefix) ? null : prefix.removeEnd('__'),
            className
        );
        if (extensionType == null) {
            extensionType = Type.forName(className);
        }
        if (extensionType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = extensionType.newInstance();
        } catch (Exception cannotBuild) {
            throw unusable(className, cannotBuild.getMessage());
        }
        if (candidate instanceof PersonErasureExtension) {
            return (PersonErasureExtension) candidate;
        }
        throw unusable(className, className + ' does not implement PersonErasureExtension');
    }

    private static PersonErasure.ErasureException unusable(String className, String reason) {
        ErrorLogger.logMessages(
            new List<String>{ reason },
            'PersonErasureExtensions.resolve',
            ErrorLogger.SEVERITY_ERROR
        );
        return new PersonErasure.ErasureException(
            String.format(Label.Core_Erase_ExtensionFailed, new List<String>{ className })
        );
    }
}
