/**
 * The helpers the relationship and affiliation code share: the status rule, the person name,
 * and the trigger-failure report.
 */
@IsTest(testFor='ApexClass:ConnectionStatus, ApexClass:PersonReference')
private class ConnectionHelpersTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private class ReportingHandler extends TriggerHandler {
        public void fail(List<SObject> records, String message) {
            reportFailure(new DmlException('boom'), records, 'ConnectionHelpersTest', message);
        }
    }

    @IsTest
    static void anEndDateMeansFormer() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                ConnectionStatus.FORMER,
                ConnectionStatus.settle(ConnectionStatus.CURRENT, Date.today(), null)
            );
        }
    }

    @IsTest
    static void clearingTheEndDateMeansCurrent() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                ConnectionStatus.CURRENT,
                ConnectionStatus.settle(ConnectionStatus.FORMER, null, Date.today())
            );
        }
    }

    @IsTest
    static void aBlankStatusIsCurrentAndADeliberateFormerStays() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(ConnectionStatus.CURRENT, ConnectionStatus.settle(null, null, null));
            Assert.areEqual(
                ConnectionStatus.FORMER,
                ConnectionStatus.settle(ConnectionStatus.FORMER, null, null)
            );
        }
    }

    @IsTest
    static void aPersonIsNamedByTheContactThenTheAccountThenTheFallback() {
        System.runAs(TestUsers.admin()) {
            // A contact's Name is the read-only compound callers query; an unsaved contact
            // built from its parts has none, so it is built as a query would hand it back.
            Contact contact = (Contact) JSON.deserialize(
                '{"attributes":{"type":"Contact"},"Name":"Garcia"}',
                Contact.class
            );
            Account account = new Account(Name = 'Garcia Household');
            Assert.areEqual('Garcia', PersonReference.nameOf(contact, account, 'Unnamed'));
            Assert.areEqual('Garcia Household', PersonReference.nameOf(null, account, 'Unnamed'));
            Assert.areEqual('Unnamed', PersonReference.nameOf(null, null, 'Unnamed'));
        }
    }

    @IsTest
    static void aFailureLeavesAnExistingMessageAlone() {
        System.runAs(TestUsers.admin()) {
            Account refused = new Account(Name = 'Refused');
            refused.addError('Already refused');
            Account other = new Account(Name = 'Other');

            new ReportingHandler().fail(new List<SObject>{ refused, other }, 'Sync failed');

            Assert.areEqual(1, refused.getErrors().size(), 'The first message is kept alone');
            Assert.areEqual('Already refused', refused.getErrors()[0].getMessage());
            Assert.areEqual('Sync failed', other.getErrors()[0].getMessage());
            new ReportingHandler().fail(null, 'Sync failed');
        }
    }
}
