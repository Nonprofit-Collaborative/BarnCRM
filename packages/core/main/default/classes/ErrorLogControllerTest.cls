/**
 * The Error Log tile: what it counts, what it lists, and what happens when Maria marks an entry
 * as seen.
 */
@IsTest
private class ErrorLogControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void theTileCountsWhatIsWaitingAndListsTheMostRecent() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertErrorLogs(7, ErrorLogger.STATUS_NEW);
            TestDataFactory.insertErrorLogs(2, ErrorLogger.STATUS_RESOLVED);

            Test.startTest();
            ErrorLogController.ErrorLogTileView tile = ErrorLogController.getTile(5);
            Test.stopTest();

            Assert.areEqual(7, tile.newCount, 'Only the new entries are counted.');
            Assert.areEqual(5, tile.recent.size(), 'The tile lists five.');
            Assert.isTrue(tile.canUpdate, 'An administrator can change an entry.');
            Assert.isNotNull(tile.recent[0].message, 'Each line shows the message.');
            Assert.isNotNull(tile.recent[0].context, 'And where it came from.');
            Assert.isNotNull(tile.recent[0].occurredAt, 'And when it happened.');
        }
    }

    @IsTest
    static void markingAnEntryAcknowledgedTakesItOutOfTheNewCount() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(3, ErrorLogger.STATUS_NEW)[0];

            Test.startTest();
            ErrorLogController.ErrorLogTileView tile = ErrorLogController.acknowledge(entry.Id);
            Test.stopTest();

            Assert.areEqual(2, tile.newCount, 'One fewer waiting.');
            Assert.areEqual(
                ErrorLogger.STATUS_ACKNOWLEDGED,
                [SELECT Status__c FROM Error_Log__c WHERE Id = :entry.Id].Status__c,
                'The entry is marked as seen.'
            );
        }
    }

    @IsTest
    static void markingAnEntryTwiceChangesNothingTheSecondTime() {
        System.runAs(TestUsers.admin()) {
            Error_Log__c entry = TestDataFactory.insertErrorLogs(
                1,
                ErrorLogger.STATUS_ACKNOWLEDGED
            )[0];

            Test.startTest();
            ErrorLogController.ErrorLogTileView tile = ErrorLogController.acknowledge(entry.Id);
            Test.stopTest();

            Assert.areEqual(0, tile.newCount, 'It was never in the new count.');
        }
    }

    @IsTest
    static void anEntryThatIsNotThereSaysSo() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.insertErrorLogs(1, ErrorLogger.STATUS_NEW);
            List<String> notEntries = new List<String>{
                null,
                '   ',
                'not-an-id',
                String.valueOf(UserInfo.getUserId())
            };

            Test.startTest();
            for (String candidate : notEntries) {
                try {
                    ErrorLogController.acknowledge(candidate);
                    Assert.fail('The value "' + candidate + '" is not an Error Log entry.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_ErrorLog_EntryNotFound,
                        expected.getMessage(),
                        'Maria is told to refresh the page.'
                    );
                }
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void anEmptyLogIsAnEmptyTile() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            ErrorLogController.ErrorLogTileView tile = ErrorLogController.getTile(null);
            Test.stopTest();

            Assert.areEqual(0, tile.newCount, 'Nothing has gone wrong.');
            Assert.areEqual(0, tile.recent.size(), 'So there is nothing to list.');
        }
    }
}
