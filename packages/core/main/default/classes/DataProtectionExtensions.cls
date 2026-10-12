/**
 * Finds the data protection extensions dependent packages installed, and gathers the objects
 * they protect (canonical model R-IT14; ADR-NEXT `NEXT-import-load-one-object.md`). An org
 * without Giving has none, and nothing is missing: Core's own bookkeeping is listed in
 * `DataProtectedFields`.
 *
 * The class is found by namespace and name, the pattern `HealthCheckExtensions` uses. A class
 * that cannot be built, does not implement the interface, or throws is logged and left out, so
 * a broken module never stops an import; its objects are then protected only by the checks that
 * do not depend on it (custom settings, metadata, the user's own access).
 */
@NamespaceAccessible
public with sharing class DataProtectionExtensions {
    /** The class names dependent packages register, in the order they are asked. */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'GivingDataProtectionExtension'
    };

    /** Injected by Core's tests, since no other package is there to resolve. */
    @TestVisible
    private static List<DataProtectionExtension> overrides = new List<DataProtectionExtension>();

    /** Set by Core's tests to see the org as having no extension beyond those injected. */
    @TestVisible
    private static Boolean noneForTest = false;

    /** Every protected object, gathered once per transaction. */
    private static Set<Schema.SObjectType> gathered;

    /** The objects every installed extension protects. */
    @NamespaceAccessible
    public static Set<Schema.SObjectType> protectedObjects() {
        if (gathered == null) {
            gathered = new Set<Schema.SObjectType>();
            List<DataProtectionExtension> extensions = new List<DataProtectionExtension>(overrides);
            if (noneForTest != true) {
                for (String className : EXTENSION_CLASSES) {
                    DataProtectionExtension extension = resolve(className);
                    if (extension != null) {
                        extensions.add(extension);
                    }
                }
            }
            for (DataProtectionExtension extension : extensions) {
                try {
                    Set<Schema.SObjectType> objects = extension.protectedObjects();
                    if (objects != null) {
                        gathered.addAll(objects);
                    }
                } catch (Exception failed) {
                    ErrorLogger.log(failed, 'DataProtectionExtensions.protectedObjects');
                }
            }
            gathered.remove(null);
        }
        return gathered;
    }

    /** Clears what was gathered, for a test that changes the extensions mid-transaction. */
    @TestVisible
    private static void reset() {
        gathered = null;
    }

    private static DataProtectionExtension resolve(String className) {
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
            ErrorLogger.log(cannotBuild, 'DataProtectionExtensions.resolve');
            return null;
        }
        if (candidate instanceof DataProtectionExtension) {
            return (DataProtectionExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement DataProtectionExtension'),
            'DataProtectionExtensions.resolve'
        );
        return null;
    }
}
