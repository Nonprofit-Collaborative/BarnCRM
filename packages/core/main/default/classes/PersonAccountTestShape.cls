/**
 * Whether a test that needs real person accounts can run in this org, and when it cannot,
 * why. A test that needs them asks skipReason() first and returns only when it gives one.
 *
 * There are two reasons, and they are not the same thing. An org that does not store people
 * as accounts at all is the Platform-only shape Core must also run on (ADR-0013): there is
 * nothing true to assert there. An org that does store people as accounts but gives the
 * running user none of its person record types (a Nonprofit Cloud trial ships its Person
 * Account record type without giving it to the System Administrator profile) is a gap in
 * the org's setup, and every test that returns there is coverage that did not run
 * (PEOPLE-29). Each reason is checked against the schema rather than taken from the
 * detector on trust, and written to the debug log, so a run that skipped says so and says
 * which.
 */
@IsTest
public class PersonAccountTestShape {
    public static final String NO_PERSON_ACCOUNTS = 'Skipped: this org does not store people as accounts (the Platform-only shape, ADR-0013).';
    public static final String NO_PERSON_TYPE_FOR_USER = 'Skipped: this org stores people as accounts but gives the running user none of its person record types. Give the System Administrator profile one so this test runs.';

    /**
     * Null when the running user can create real person accounts here; otherwise the reason
     * the test cannot, after checking that reason against the org's own describe.
     */
    public static String skipReason() {
        Schema.DescribeSObjectResult account = Account.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        if (!OrgShapeDetector.hasPersonAccounts()) {
            Assert.isFalse(
                account.fields.getMap().containsKey('personcontactid'),
                'The detector and the schema agree that this org has no person accounts'
            );
            return logged(NO_PERSON_ACCOUNTS);
        }
        if (OrgShapeDetector.creatablePersonRecordTypeId() == null) {
            Map<Id, Schema.RecordTypeInfo> infos = account.getRecordTypeInfosById();
            for (Id personType : OrgShapeDetector.personAccountRecordTypeIds()) {
                Schema.RecordTypeInfo info = infos.get(personType);
                Assert.isFalse(
                    info != null && info.isAvailable(),
                    'No person record type is available to the running user, so none can be created'
                );
            }
            return logged(NO_PERSON_TYPE_FOR_USER);
        }
        return null;
    }

    private static String logged(String reason) {
        System.debug(LoggingLevel.WARN, reason);
        return reason;
    }
}
