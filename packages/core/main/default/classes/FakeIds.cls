/**
 * Ids for tests that need a well formed Id no record carries: only its key prefix is read, or
 * it is compared and never queried.
 *
 * Built from the object's key prefix at run time, so no Id literal sits in the source (Code
 * Analyzer's AvoidHardcodingId) and the prefix is right in every org.
 *
 * Public and namespace accessible, never global (ADR-0017), so a module package's tests can
 * call it. Test only.
 */
@IsTest
@NamespaceAccessible
public class FakeIds {
    /**
     * @param type the object the Id should belong to
     * @param n a number that makes this Id differ from others of the same object
     * @return an 18 character Id of that object
     */
    @NamespaceAccessible
    public static Id of(Schema.SObjectType type, Integer n) {
        return ofPrefix(type.getDescribe().getKeyPrefix(), n);
    }

    /**
     * For an Id whose object has no SObjectType Apex can name (a package version, 04t).
     *
     * @param keyPrefix the three character key prefix
     * @param n a number that makes this Id differ from others with the same prefix
     * @return an 18 character Id with that prefix
     */
    @NamespaceAccessible
    public static Id ofPrefix(String keyPrefix, Integer n) {
        return Id.valueOf(keyPrefix + String.valueOf(n).leftPad(12, '0'));
    }
}
