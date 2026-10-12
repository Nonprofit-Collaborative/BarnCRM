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
