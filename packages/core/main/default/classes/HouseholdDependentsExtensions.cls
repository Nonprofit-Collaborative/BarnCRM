/**
 * Asks every installed `HouseholdDependentsExtension` which of a set of households it still
 * credits records to, so the empty household tidy-up keeps them (R-H12, ADR-NEXT
 * `NEXT-empty-household-tidy-up-keeps-households-with-gifts.md`).
 *
 * Found by namespace and class name, as `HealthCheckExtensions` finds its extensions
 * (ADR-0017). An extension that is not installed is absent and asks nothing. One that is
 * installed but cannot be built, does not implement the interface, or throws while answering
 * reports every household it was asked about as dependent, and the failure is logged: not
 * being able to answer is not answering no, and a household kept by mistake costs far less
 * than history cleared by mistake (the ADR-0036 rule).
 */
@NamespaceAccessible
public with sharing class HouseholdDependentsExtensions {
    /** The class names dependent packages register, in the order they are asked. */
    @NamespaceAccessible
    public static final List<String> EXTENSION_CLASSES = new List<String>{
        'GivingHouseholdDependentsExtension'
    };

    /** Injected by Core's tests by class name, since no other package is there to resolve. */
    @TestVisible
    private static Map<String, HouseholdDependentsExtension> overrides = new Map<String, HouseholdDependentsExtension>();

    /** Set by Core's tests to see the org as having no extension beyond those injected. */
    @TestVisible
    private static Boolean noneForTest = false;

    /** Each class looked up so far this transaction, null when it is not installed. */
    private static Map<String, HouseholdDependentsExtension> found = new Map<String, HouseholdDependentsExtension>();

    /**
     * Of these households, the ones any installed extension still credits records to. Never
     * null.
     */
    @NamespaceAccessible
    public static Set<Id> householdsWithDependents(Set<Id> householdIds) {
        Set<Id> dependent = new Set<Id>();
        if (householdIds == null || householdIds.isEmpty()) {
            return dependent;
        }
        for (String className : EXTENSION_CLASSES) {
            HouseholdDependentsExtension extension = extensionFor(className);
            if (extension != null) {
                dependent.addAll(ask(extension, householdIds));
            }
        }
        return dependent;
    }

    /** The extension registered under this name, or null when it is not installed. */
    private static HouseholdDependentsExtension extensionFor(String className) {
        HouseholdDependentsExtension extension = overrides.get(className);
        if (extension != null || noneForTest == true) {
            return extension;
        }
        if (!found.containsKey(className)) {
            found.put(className, resolve(className));
        }
        return found.get(className);
    }

    /** One extension's answer; every household when it cannot answer. */
    private static Set<Id> ask(HouseholdDependentsExtension extension, Set<Id> householdIds) {
        try {
            Set<Id> answer = extension.householdsWithDependents(new Set<Id>(householdIds));
            return answer == null ? new Set<Id>() : answer;
        } catch (Exception cannotAnswer) {
            ErrorLogger.log(cannotAnswer, 'HouseholdDependentsExtensions.householdsWithDependents');
            return householdIds;
        }
    }

    private static HouseholdDependentsExtension resolve(String className) {
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
            ErrorLogger.log(cannotBuild, 'HouseholdDependentsExtensions.resolve');
            return new EveryHouseholdDependent();
        }
        if (candidate instanceof HouseholdDependentsExtension) {
            return (HouseholdDependentsExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(
                className + ' does not implement HouseholdDependentsExtension'
            ),
            'HouseholdDependentsExtensions.resolve'
        );
        return new EveryHouseholdDependent();
    }

    /** Stands in for an installed extension that cannot be used: it keeps every household. */
    @TestVisible
    private class EveryHouseholdDependent implements HouseholdDependentsExtension {
        public Set<Id> householdsWithDependents(Set<Id> householdIds) {
            return householdIds;
        }
    }
}
