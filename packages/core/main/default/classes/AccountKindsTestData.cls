/**
 * Organization test data for Core and every module (ADR-0141). Core ships no Organization
 * record type, so a test never names one: it asks here for the record type the org uses for
 * organizations, which is what `AccountKinds` detects in the test context (null for No record
 * type, which saves an account with none).
 *
 * A test must pass on any org shape, whatever record types and access the org was left with.
 * Detection weighs the org's active record types, not the running user's access, and BarnCRM's
 * permission sets give no Account record type, so in an org that kept a record type the test
 * user's profile does not give (a gate org upgraded from a version that shipped Organization,
 * say) the detected one cannot be saved. `useRecordTypeTheUserCanUse` then stores, for this
 * test only, the first record type the user can use, or No record type when they can use none.
 */
@IsTest
@NamespaceAccessible
public class AccountKindsTestData {
    /** The record type new organizations get, or null for No record type. */
    @NamespaceAccessible
    public static Id organizationRecordTypeId() {
        useRecordTypeTheUserCanUse();
        return AccountKinds.organizationRecordTypeId();
    }

    /** An unsaved organization with this name, of the organization record type. */
    @NamespaceAccessible
    public static Account organization(String name) {
        return new Account(Name = name, RecordTypeId = organizationRecordTypeId());
    }

    /**
     * Makes the record type for organizations one the running user can use, for tests whose
     * organizations the product creates (import, sample data). Call it in the test setup, as the
     * user the tests run as, before anything that creates an organization. Stores nothing when
     * the record type in force is already usable, so on most orgs it changes nothing.
     */
    @NamespaceAccessible
    public static void useRecordTypeTheUserCanUse() {
        if (AccountKinds.organizationRecordTypeUsable()) {
            return;
        }
        String usable = AccountKinds.NO_RECORD_TYPE;
        for (Schema.RecordTypeInfo info : AccountKinds.candidateRecordTypes()) {
            if (info.isAvailable()) {
                usable = info.getDeveloperName();
                break;
            }
        }
        // Written as the system writes it: the Settings save refuses No record type where a
        // candidate exists, which is exactly the org this test may be running in.
        OrgSettingsSystemWriter.save(
            new Map<Schema.SObjectField, Object>{
                BarnCRM_Settings__c.Organization_Record_Type__c => usable
            }
        );
    }
}
