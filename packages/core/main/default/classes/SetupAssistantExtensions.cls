/**
 * Finds the Setup Assistant extensions dependent packages installed, or answers that there are
 * none, which is the ordinary case in an org with Core alone (C-29, ADR-0059).
 *
 * The same resolver shape as `HealthCheckExtensions` (ADR-0057, ADR-0058): each class is found
 * by namespace and then by name alone, looked up once per transaction, and a class that cannot
 * be built or does not implement the interface is treated as absent and logged, because the
 * assistant must open whatever a module does.
 */
@NamespaceAccessible
public with sharing class SetupAssistantExtensions {
    /** The class names dependent packages register, in the order they are asked. */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'GivingSetupAssistantExtension'
    };

    /** Injected by Core's tests, since no other package is there to resolve. */
    @TestVisible
    private static List<SetupAssistantExtension> overrides;

    /** Each class looked up so far this transaction, null when it is not installed. */
    private static Map<String, SetupAssistantExtension> found = new Map<String, SetupAssistantExtension>();

    /** Every installed extension, in the order of `EXTENSION_CLASSES`. */
    @NamespaceAccessible
    public static List<SetupAssistantExtension> findAll() {
        if (overrides != null) {
            return overrides;
        }
        List<SetupAssistantExtension> extensions = new List<SetupAssistantExtension>();
        for (String className : EXTENSION_CLASSES) {
            if (!found.containsKey(className)) {
                found.put(className, resolve(className));
            }
            if (found.get(className) != null) {
                extensions.add(found.get(className));
            }
        }
        return extensions;
    }

    @TestVisible
    private static SetupAssistantExtension resolve(String className) {
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
            ErrorLogger.log(cannotBuild, 'SetupAssistantExtensions.resolve');
            return null;
        }
        if (candidate instanceof SetupAssistantExtension) {
            return (SetupAssistantExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement SetupAssistantExtension'),
            'SetupAssistantExtensions.resolve'
        );
        return null;
    }
}
