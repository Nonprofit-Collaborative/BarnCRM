/**
 * Restoring a relationship from the recycle bin brings back the other side that was deleted
 * with it, rather than building a new one (PEOPLE-21). However the two sides come back, one at
 * a time, one after the other, or together, the result is the one pair there was before.
 */
@IsTest
private class RelationshipRestoreTest {
    @IsTest
    static void restoringOneSideBringsBackItsOtherSide() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Set<Id> before = savedPairs(1);
            List<Id> ids = new List<Id>(before);
            delete as system new Relationship__c(Id = ids[0]);

            Test.startTest();
            undelete as system new Relationship__c(Id = ids[0]);
            Test.stopTest();

            assertOriginalPairsBack(before);
        }
    }

    @IsTest
    static void restoringOneSideThenTheOtherEndsWithOnePair() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Set<Id> before = savedPairs(1);
            List<Id> ids = new List<Id>(before);
            delete as system new Relationship__c(Id = ids[0]);

            Test.startTest();
            undelete as system new Relationship__c(Id = ids[0]);
            // The other side came back with the first, so this restore has nothing left to do.
            Database.undelete(
                new List<Relationship__c>{ new Relationship__c(Id = ids[1]) },
                false,
                AccessLevel.SYSTEM_MODE
            );
            Test.stopTest();

            assertOriginalPairsBack(before);
        }
    }

    @IsTest
    static void restoringBothSidesAtOnceEndsWithOnePair() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Set<Id> before = savedPairs(1);
            List<Id> ids = new List<Id>(before);
            delete as system new Relationship__c(Id = ids[0]);

            Test.startTest();
            undelete as system new List<Relationship__c>{
                new Relationship__c(Id = ids[0]),
                new Relationship__c(Id = ids[1])
            };
            Test.stopTest();

            assertOriginalPairsBack(before);
        }
    }

    @IsTest
    static void restoringTwoHundredRelationshipsBringsBackTheirOtherSides() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Set<Id> before = savedPairs(200);
            List<Relationship__c> firstSides = new List<Relationship__c>();
            Set<Id> taken = new Set<Id>();
            for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
                if (!taken.contains(record.Id)) {
                    firstSides.add(new Relationship__c(Id = record.Id));
                    taken.add(record.Id);
                    taken.add(record.Reciprocal_Relationship__c);
                }
            }
            Assert.areEqual(200, firstSides.size(), 'One side of each of the two hundred pairs');
            delete as system firstSides;
            Assert.areEqual(
                0,
                RelationshipTestDataFactory.allRelationships().size(),
                'Deleting one side of each pair took both'
            );

            Test.startTest();
            undelete as system firstSides;
            Test.stopTest();

            assertOriginalPairsBack(before);
        }
    }

    /** Saves this many relationships between different people and returns every record id. */
    private static Set<Id> savedPairs(Integer howMany) {
        List<Contact> people = RelationshipTestDataFactory.contacts(2 * howMany, 'Restore');
        List<Relationship__c> batch = new List<Relationship__c>();
        for (Integer i = 0; i < howMany; i++) {
            batch.add(
                RelationshipTestDataFactory.between(people[2 * i], people[2 * i + 1], 'Spouse')
            );
        }
        insert as system batch;
        Set<Id> ids = new Set<Id>();
        for (Relationship__c record : RelationshipTestDataFactory.allRelationships()) {
            ids.add(record.Id);
        }
        Assert.areEqual(2 * howMany, ids.size(), 'Every relationship got its other side');
        return ids;
    }

    /**
     * Exactly the records that were there before the delete are back, no others, and each is
     * paired with the other side it had.
     */
    private static void assertOriginalPairsBack(Set<Id> before) {
        List<Relationship__c> all = RelationshipTestDataFactory.allRelationships();
        Assert.areEqual(before.size(), all.size(), 'No third record was built');
        Map<Id, Relationship__c> byId = new Map<Id, Relationship__c>(all);
        Assert.isTrue(byId.keySet().equals(before), 'The original records are the ones back');
        for (Relationship__c record : all) {
            Relationship__c partner = byId.get(record.Reciprocal_Relationship__c);
            Assert.isNotNull(partner, 'Every restored record is paired with a live record');
            Assert.areEqual(record.Id, partner.Reciprocal_Relationship__c, 'Both ways');
        }
    }
}
