/**
 * Whether a test that needs real person accounts can run in this org, and when it cannot,
 * why. A test that needs them asks skipReason() first and returns only when it gives one.
 *
 * There are two reasons, and they are not the same thing. An org that does not store people
 * as accounts at all is the Platform-only shape Core must also run on (ADR-0013): there is
 * nothing true to assert there. An org that does store people as accounts but gives the
 * running user none of its person record types (a Nonprofit Cloud trial ships its Person
 * Account record type without giving it to the System Administrator profile) is a gap in
 * the org's setup, not a shape to skip: the test fails, naming the script that closes the
 * gap (scripts/org/grant-person-record-type.sh), so person account coverage can never
 * quietly not run (PEOPLE-29). Each reason is checked against the schema rather than taken
 * from the detector on trust, and a skip is written to the debug log.
 */
@IsTest
public class PersonAccountTestShape {
    public static final String NO_PERSON_ACCOUNTS = 'Skipped: this org does not store people as accounts (the Platform-only shape, ADR-0013).';
    public static final String NO_PERSON_TYPE_FOR_USER = 'This org stores people as accounts but gives the running user none of its person record types, so person account coverage cannot run. Run scripts/org/grant-person-record-type.sh <alias> to give the System Administrator profile one.';

    /**
     * Null when the running user can create real person accounts here, and NO_PERSON_ACCOUNTS
     * in an org that has none. Fails the calling test, with NO_PERSON_TYPE_FOR_USER, in an org
     * that has person accounts but gives the running user no person record type.
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
            Assert.fail(NO_PERSON_TYPE_FOR_USER);
        }
        return null;
    }

    private static String logged(String reason) {
        System.debug(LoggingLevel.WARN, reason);
        return reason;
    }
}
