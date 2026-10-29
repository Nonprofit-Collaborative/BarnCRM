/**
 * Organization test data for Core and every module (ADR-0141). Core ships no Organization
 * record type, so a test never names one: it asks here for the record type the org uses for
 * organizations, which is what `AccountKinds` detects in the test context (null for No record
 * type, which saves an account with none).
 */
@IsTest
@NamespaceAccessible
public class AccountKindsTestData {
    /** The record type new organizations get, or null for No record type. */
    @NamespaceAccessible
    public static Id organizationRecordTypeId() {
        return AccountKinds.organizationRecordTypeId();
    }

    /** An unsaved organization with this name, of the organization record type. */
    @NamespaceAccessible
    public static Account organization(String name) {
        return new Account(Name = name, RecordTypeId = organizationRecordTypeId());
    }
}
