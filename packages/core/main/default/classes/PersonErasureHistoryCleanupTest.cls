/**
 * The field history cleanup an erasure queues once it has committed (canonical model R-ER4): it
 * leaves the person alone, deletes nothing when there is no history, and logs a target it
 * cannot read without stopping the others.
 */
@IsTest(testFor='ApexClass:PersonErasureHistoryCleanup')
private class PersonErasureHistoryCleanupTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static List<Error_Log__c> logged() {
        return [
            SELECT Context__c
            FROM Error_Log__c
            WHERE Context__c LIKE 'PersonErasureHistoryCleanup%'
        ];
    }

    @IsTest
    static void aTargetWithNoHistoryIsLeftAloneAndNothingIsLogged() {
        System.runAs(TestUsers.admin()) {
            Contact person = RelationshipTestDataFactory.contacts(1, 'Garcia')[0];
            Map<String, Set<Id>> targets = new Map<String, Set<Id>>{
                'ContactHistory.ContactId' => new Set<Id>{ person.Id }
            };

            Test.startTest();
            System.enqueueJob(new PersonErasureHistoryCleanup(targets));
            Test.stopTest();

            Assert.isTrue(logged().isEmpty(), 'Nothing to delete is not a failure');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE Id = :person.Id],
                'The cleanup touches history, never the person'
            );
        }
    }

    @IsTest
    static void anUnreadableTargetIsLoggedAndDoesNotStopTheNextOne() {
        System.runAs(TestUsers.admin()) {
            Contact person = RelationshipTestDataFactory.contacts(1, 'Garcia')[0];
            Map<String, Set<Id>> targets = new Map<String, Set<Id>>{
                'NoSuchHistory.ParentId' => new Set<Id>{ person.Id },
                'ContactHistory.ContactId' => new Set<Id>{ person.Id }
            };

            Test.startTest();
            new PersonErasureHistoryCleanup(targets).execute(null);
            Test.stopTest();

            List<Error_Log__c> entries = logged();
            Assert.areEqual(1, entries.size(), 'Only the unreadable target is logged');
            Assert.areEqual(
                'PersonErasureHistoryCleanup.NoSuchHistory',
                entries[0].Context__c,
                'Named by the history object that failed'
            );
        }
    }
}
