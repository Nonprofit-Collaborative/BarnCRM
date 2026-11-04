/**
 * Finds the Where Used extensions dependent packages installed (C-59, ADR-0159), the pattern
 * `HealthCheckExtensions` uses (ADR-0057). A class that is not installed, cannot be built, or does
 * not implement the interface is treated as absent, and a failure is logged: Where Used must still
 * answer for Core when a module cannot.
 */
@NamespaceAccessible
public with sharing class WhereUsedExtensions {
    /**
     * The class names dependent packages register, in the order they are asked: the Rollup
     * Builder module's rollup definitions, Giving's gift import columns, Programs' eligibility
     * rules, then Logic Models' computed indicators. Funders stores no field names, so it has none.
     */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'RollupsWhereUsedExtension',
        'GivingWhereUsedExtension',
        'ProgramsWhereUsedExtension',
        'LogicModelsWhereUsedExtension'
    };

    /** Injected by Core's tests by class name, since no other package is there to resolve. */
    @TestVisible
    private static Map<String, WhereUsedExtension> overrides = new Map<String, WhereUsedExtension>();

    /** Set by Core's tests to see the org as having no extension beyond those injected. */
    @TestVisible
    private static Boolean noneForTest = false;

    /** Every installed extension, by class name, in registration order. */
    @NamespaceAccessible
    public static Map<String, WhereUsedExtension> findAll() {
        Map<String, WhereUsedExtension> byName = new Map<String, WhereUsedExtension>();
        for (String className : EXTENSION_CLASSES) {
            WhereUsedExtension extension = overrides.get(className);
            if (extension == null && noneForTest != true) {
                extension = resolve(className);
            }
            if (extension != null) {
                byName.put(className, extension);
            }
        }
        return byName;
    }

    private static WhereUsedExtension resolve(String className) {
        Type extensionType = NamespaceUtil.resolveType(className);
        if (extensionType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = extensionType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'WhereUsedExtensions.resolve');
            return null;
        }
        if (candidate instanceof WhereUsedExtension) {
            return (WhereUsedExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement WhereUsedExtension'),
            'WhereUsedExtensions.resolve'
        );
        return null;
    }
}
