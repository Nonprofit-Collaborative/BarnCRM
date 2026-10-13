/**
 * The helpers Campaign sync and the Opportunity mirror share (ConnectSync): how a typed
 * identifier is read, when a transaction is too spent to copy, and how refusals are grouped so a
 * rule that refuses a whole import writes a handful of Warnings (R-OM6).
 */
@IsTest(testFor='ApexClass:ConnectSync')
private class ConnectSyncTest {
    private static final String CONTEXT = 'Connect sync test';
    private static final String ONE = 'Could not copy "{0}": {1}';
    private static final String MANY = 'Could not copy {0} records ({1}): {2}';

    private static List<Error_Log__c> warnings() {
        return [
            SELECT Message__c, Record_Reference__c
            FROM Error_Log__c
            WHERE Context__c = :CONTEXT AND Severity__c = 'Warning'
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void aTypedIdentifierMustBeTheExpectedObjects() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id userId = UserInfo.getUserId();
            Assert.isNull(ConnectSync.idOf(null, User.SObjectType), 'Nothing typed, nothing read.');
            Assert.isNull(ConnectSync.idOf('  ', User.SObjectType), 'Blank is nothing.');
            Assert.isNull(ConnectSync.idOf('not an id', User.SObjectType), 'Words are not an id.');
            Assert.isNull(
                ConnectSync.idOf(String.valueOf(userId), Account.SObjectType),
                'Another object\'s id is refused.'
            );
            Assert.areEqual(
                userId,
                ConnectSync.idOf(' ' + String.valueOf(userId).left(15) + ' ', User.SObjectType),
                'A 15 character id, with spaces around it, reads as the 18 character one.'
            );
            Assert.isNull(ConnectSync.idOf(String.valueOf(userId), null), 'No object, no match.');
        }
    }

    @IsTest
    static void aSpentTransactionHasNoHeadroom() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(ConnectSync.hasHeadroom(5, 4, 600, 0.4), 'A fresh transaction has room.');
            ConnectSync.simulatedCpuTimeUsed = Limits.getLimitCpuTime() - 100;
            Assert.isFalse(
                ConnectSync.hasHeadroom(5, 4, 600, 0.4),
                'Too little CPU left stops a copy that runs other automation.'
            );
            Assert.isTrue(
                ConnectSync.hasHeadroom(5, 4, 600),
                'CPU is only checked when asked for.'
            );
            ConnectSync.simulatedCpuTimeUsed = null;
            ConnectSync.simulatedQueriesUsed = Limits.getLimitQueries() - 5;
            Assert.isFalse(ConnectSync.hasHeadroom(1, 1, 1), 'Queries run out too.');
            ConnectSync.simulatedQueriesUsed = null;
            ConnectSync.simulatedDmlStatementsUsed = Limits.getLimitDmlStatements() - 5;
            Assert.isFalse(ConnectSync.hasHeadroom(1, 1, 1), 'So do DML statements.');
            ConnectSync.simulatedDmlStatementsUsed = null;
            Assert.isFalse(ConnectSync.hasHeadroom(1, 1, Limits.getLimitDmlRows()), 'And rows.');
        }
    }

    @IsTest
    static void refusalsAreWrittenOncePerMessage() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id userId = UserInfo.getUserId();
            ConnectSync.Warnings refused = new ConnectSync.Warnings();
            for (Integer i = 1; i <= 12; i++) {
                refused.add('A rule said no.', 'G-' + i, userId);
            }
            ConnectSync.Warnings other = new ConnectSync.Warnings();
            other.add('Amount is missing.', 'G-99', userId);
            other.add('A rule said no.', 'G-13', userId);
            refused.addAll(other);
            refused.addAll(null);
            Assert.areEqual(14, refused.count(), 'Every refusal is counted.');

            Test.startTest();
            Integer logWritesBefore = Limits.getPublishImmediateDML();
            refused.write(CONTEXT, ONE, MANY);
            Integer logWrites = Limits.getPublishImmediateDML() - logWritesBefore;
            Test.stopTest();

            Assert.isTrue(refused.isEmpty(), 'Writing empties the list.');
            Assert.areEqual(1, logWrites, 'One statement, whatever the number of refusals.');
            List<Error_Log__c> logged = warnings();
            Assert.areEqual(2, logged.size(), 'One Warning per distinct message.');
            // Long text cannot be sorted in a query, so the two are told apart by what they say.
            String one = logged[0].Message__c.contains('G-99')
                ? logged[0].Message__c
                : logged[1].Message__c;
            String many = logged[0].Message__c.contains('G-99')
                ? logged[1].Message__c
                : logged[0].Message__c;
            Assert.areEqual(
                'Could not copy "G-99": Amount is missing.',
                one,
                'A message about one record names it.'
            );
            Assert.isTrue(
                many.startsWith('Could not copy 13 records (G-1, G-2,'),
                'A message about many gives the count and the first names: ' + many
            );
            Assert.isTrue(
                many.contains('G-10 and 3 more'),
                'Only ten names are spelled out: ' + many
            );
        }
    }

    @IsTest
    static void nothingRefusedWritesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            ConnectSync.Warnings refused = new ConnectSync.Warnings();
            refused.write(CONTEXT, ONE, MANY);
            Assert.areEqual(0, warnings().size(), 'No refusals, no Warning.');
            Assert.areEqual(0, refused.count(), 'Nothing counted.');
        }
    }

    @IsTest
    static void aShareOfTheQueryAndDmlLimitsMustBeLeft() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(
                ConnectSync.hasHeadroom(7, 4, 600, 0.4, 0.5),
                'A fresh transaction has room.'
            );
            // Far more than a fixed margin leaves, and still not half the limit.
            ConnectSync.simulatedQueriesUsed = Limits.getLimitQueries() / 2;
            Assert.isTrue(
                ConnectSync.hasHeadroom(7, 4, 600),
                'The fixed margin alone would start a copy here.'
            );
            Assert.isFalse(
                ConnectSync.hasHeadroom(7, 4, 600, 0.4, 0.5),
                'Half the queries are spent, which the org\'s own Opportunity automation may need.'
            );
            ConnectSync.simulatedQueriesUsed = null;
            ConnectSync.simulatedDmlStatementsUsed = Limits.getLimitDmlStatements() / 2;
            Assert.isFalse(
                ConnectSync.hasHeadroom(7, 4, 600, 0.4, 0.5),
                'The same for DML statements.'
            );
        }
    }

    @IsTest
    static void distinctMessagesPastTheCapAreCountedTogether() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Id userId = UserInfo.getUserId();
            ConnectSync.Warnings refused = new ConnectSync.Warnings();
            // A message carrying a record identifier is distinct for every record.
            for (Integer i = 1; i <= 120; i++) {
                refused.add('Duplicate of record ' + i, 'G-' + i, userId);
            }
            Assert.areEqual(120, refused.count(), 'Every refusal is still counted.');

            Test.startTest();
            refused.write(CONTEXT, ONE, MANY);
            Test.stopTest();

            List<Error_Log__c> logged = warnings();
            Assert.areEqual(ConnectSync.MESSAGES_KEPT, logged.size(), 'At most the kept messages.');
            Integer shared = 0;
            for (Error_Log__c entry : logged) {
                if (entry.Message__c.contains(Label.Connect_Sync_OtherMessages)) {
                    shared++;
                    Assert.isTrue(
                        entry.Message__c.startsWith('Could not copy 71 records'),
                        'The rest are counted together: ' + entry.Message__c
                    );
                }
            }
            Assert.areEqual(1, shared, 'One entry for the rest.');
        }
    }
}
