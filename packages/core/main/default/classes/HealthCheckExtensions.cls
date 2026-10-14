/**
 * Finds the Health Check extensions dependent packages installed, or answers that there are
 * none, which is the ordinary case in an org without Giving or Connect (G-20 follow-up,
 * ADR-0053, ADR-0057, amended by feature X-01 for Connect's).
 *
 * The class is found by namespace and name, the pattern `ImportEntityProcessors` uses for the
 * same reason (R-IR6): a class name is not an API name, so it takes no `__` prefix. A class
 * that cannot be built, or does not implement the interface, is treated as absent and logged,
 * because a health report must not fail over a module it can do without.
 */
@NamespaceAccessible
public with sharing class HealthCheckExtensions {
    /**
     * The class names dependent packages register to add findings, in the order they are asked:
     * Giving's (G-20 follow-up), then Connect's, for its nightly mirror run (X-01).
     */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'GivingHealthCheckExtension',
        'ConnectHealthCheckExtension'
    };

    /** Injected by Core's tests by class name, since no other package is there to resolve. */
    @TestVisible
    private static Map<String, HealthCheckExtension> overrides = new Map<String, HealthCheckExtension>();

    /** Set by Core's tests to see the org as having no extension beyond those injected. */
    @TestVisible
    private static Boolean noneForTest = false;

    /** Each class looked up so far this transaction, null when it is not installed. */
    private static Map<String, HealthCheckExtension> found = new Map<String, HealthCheckExtension>();

    /**
     * Every installed extension, keyed by the name a failure of it is reported under
     * (`giving_extension`, `connect_extension`), so one that throws never hides another's. Each
     * is looked up once per transaction.
     */
    @NamespaceAccessible
    public static Map<String, HealthCheckExtension> findAll() {
        Map<String, HealthCheckExtension> byKey = new Map<String, HealthCheckExtension>();
        for (String className : EXTENSION_CLASSES) {
            HealthCheckExtension extension = overrides.get(className);
            if (extension == null && noneForTest != true) {
                if (!found.containsKey(className)) {
                    found.put(className, resolve(className));
                }
                extension = found.get(className);
            }
            if (extension != null) {
                byKey.put(
                    className.removeEnd('HealthCheckExtension').toLowerCase() + '_extension',
                    extension
                );
            }
        }
        return byKey;
    }

    private static HealthCheckExtension resolve(String className) {
        Type extensionType = NamespaceUtil.resolveType(className);
        if (extensionType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = extensionType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'HealthCheckExtensions.resolve');
            return null;
        }
        if (candidate instanceof HealthCheckExtension) {
            return (HealthCheckExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement HealthCheckExtension'),
            'HealthCheckExtensions.resolve'
        );
        return null;
    }
}
