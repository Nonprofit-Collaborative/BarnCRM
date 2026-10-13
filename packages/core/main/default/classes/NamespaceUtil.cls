/**
 * The namespace this package is running under, worked out at runtime.
 *
 * The namespace is deferred (ADR-0001) and will be registered later, at which point every
 * packaged tab, page, object, and page state parameter gains a prefix. Nothing may hard-code
 * either state: source that names `BarnCRM_Settings` breaks once the namespace exists, and
 * source that writes a prefix in front of it fails the namespace check today and breaks in an
 * unmanaged org.
 *
 * So the answer is asked for rather than assumed. In a managed package a class reports its
 * name as `namespace.ClassName`; with no namespace there is no dot, and the prefix is empty.
 *
 * Lightning web components must never build these names themselves. They read them from
 * Apex, which is why they appear on the report a controller returns.
 */
@NamespaceAccessible
public with sharing class NamespaceUtil {
    @TestVisible
    private static String cachedPrefix;

    /**
     * The package prefix, `mynamespace__` in a managed package and empty everywhere else.
     */
    @NamespaceAccessible
    public static String prefix() {
        if (cachedPrefix == null) {
            String className = NamespaceUtil.class.getName();
            cachedPrefix = className.contains('.') ? className.substringBefore('.') + '__' : '';
        }
        return cachedPrefix;
    }

    /**
     * A packaged API name with whatever prefix this org needs, for example a tab or page name.
     */
    @NamespaceAccessible
    public static String qualify(String apiName) {
        return String.isBlank(apiName) ? apiName : prefix() + apiName;
    }

    /** Stands in for the org's global describe in tests, keyed by lower-case API name. */
    @TestVisible
    private static Map<String, Schema.SObjectType> describeOverride;

    /** Objects by trimmed lower-case name, null when absent, looked up once per transaction. */
    @TestVisible
    private static Map<String, Schema.SObjectType> typesByName = new Map<String, Schema.SObjectType>();

    /**
     * The object a metadata row or setting names. Rows name objects without a prefix, so this
     * package's own object (`prefix() + name`) is tried first, then the name exactly as written:
     * a standard object, the subscriber's own object, or a name that already carries a prefix.
     * There is no match on the part after some other prefix, which could pick another package's
     * object (NPSP's `Address__c`). Null when nothing matches.
     */
    @NamespaceAccessible
    public static Schema.SObjectType objectType(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        String name = apiName.trim().toLowerCase();
        if (!typesByName.containsKey(name)) {
            Schema.SObjectType type = packagedObjectType(name);
            typesByName.put(name, type != null ? type : globalDescribe().get(name));
        }
        return typesByName.get(name);
    }

    /**
     * This package's own object of that name, or null. Never the subscriber's object or another
     * package's, even when its name ends the same way, so it is safe for asking whether a
     * BarnCRM object is in the org.
     */
    @NamespaceAccessible
    public static Schema.SObjectType packagedObjectType(String apiName) {
        if (String.isBlank(apiName)) {
            return null;
        }
        return globalDescribe().get(qualify(apiName.trim()).toLowerCase());
    }

    private static Map<String, Schema.SObjectType> globalDescribe() {
        return describeOverride != null ? describeOverride : Schema.getGlobalDescribe();
    }

    /**
     * The key a page state parameter has to use. Lightning namespaces these too: a package
     * with no namespace uses the `c__` prefix, and a managed package uses its own.
     */
    @NamespaceAccessible
    public static String stateKey(String parameterName) {
        if (String.isBlank(parameterName)) {
            return parameterName;
        }
        String packagePrefix = prefix();
        return String.isBlank(packagePrefix)
            ? 'c__' + parameterName
            : packagePrefix + parameterName;
    }
}
