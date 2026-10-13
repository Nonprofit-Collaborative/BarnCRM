/**
 * Which target records a save marks for recalculation (canonical model R-R11, rollup proposal
 * slice S6). Core holds no giving objects, so these tests roll organizations up to their parent
 * (`ParentId`) and affiliations up to an organization or a person's household; the giving cases
 * are in Giving's regression suite.
 */
@IsTest
private class RollupChangesTest {
    private static Account organization(String name) {
        return new Account(
            Name = name,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    private static Account household(String name) {
        return new Account(Name = name, RecordTypeId = HouseholdService.householdRecordTypeId());
    }

    private static Rollup_Definition__c definition(String source, String path, String filter) {
        return new Rollup_Definition__c(
            Name = 'Test count',
            Definition_Key__c = 'Test_Count_' + source,
            Source_Object__c = source,
            Relationship_Path__c = path,
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Filter_JSON__c = filter,
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static String filter(String field, String operator, Object value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => field,
                        'operator' => operator,
                        'value' => value
                    }
                }
            }
        );
    }

    private static Id fakeId(Schema.SObjectType entity) {
        return FakeIds.of(entity, 1);
    }

    private static Set<Id> markedAccounts(RollupChanges.Marked marked) {
        Set<Id> ids = marked.idsByTarget.get('account');
        return ids == null ? new Set<Id>() : ids;
    }

    @IsTest
    static void aRecordMovedToAnotherParentMarksBothParents() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c children = definition('Account', 'ParentId', null);
            Account child = organization('Child');
            child.Id = fakeId(Account.SObjectType);
            Id oldParent = FakeIds.of(Account.SObjectType, 2);
            Id newParent = FakeIds.of(Account.SObjectType, 3);
            Account now = child.clone(true);
            now.ParentId = newParent;
            Account before = child.clone(true);
            before.ParentId = oldParent;

            RollupChanges.Marked moved = RollupChanges.forSave(
                'Account',
                new List<SObject>{ now },
                new Map<Id, SObject>{ child.Id => before },
                false,
                new List<Rollup_Definition__c>{ children }
            );
            Account renamed = before.clone(true);
            renamed.Name = 'Renamed';
            RollupChanges.Marked unread = RollupChanges.forSave(
                'Account',
                new List<SObject>{ renamed },
                new Map<Id, SObject>{ child.Id => before },
                false,
                new List<Rollup_Definition__c>{ children }
            );
            RollupChanges.Marked deleted = RollupChanges.afterDelete(
                'Account',
                new List<SObject>{ before },
                new List<Rollup_Definition__c>{ children }
            );

            Assert.areEqual(
                new Set<Id>{ oldParent, newParent },
                markedAccounts(moved),
                'The total it left and the total it joined'
            );
            Assert.isTrue(unread.isEmpty(), 'A change to nothing the rollup reads marks nothing');
            Assert.areEqual(
                new Set<Id>{ oldParent },
                markedAccounts(deleted),
                'A delete: the old one'
            );
        }
    }

    /**
     * The gap slice S5 left: an affiliation moved from Ana to Bea marks Bea's household and also
     * the household Ana is in, which the old and new versions sharing one id used to hide.
     */
    @IsTest
    static void aRecordMovedToAnotherPersonMarksBothHouseholds() {
        System.runAs(TestUsers.admin()) {
            Account nolan = household('The Nolan Family');
            Account lee = household('The Lee Family');
            insert new List<Account>{ nolan, lee };
            Contact ana = new Contact(FirstName = 'Ana', LastName = 'Nolan', AccountId = nolan.Id);
            Contact bea = new Contact(FirstName = 'Bea', LastName = 'Lee', AccountId = lee.Id);
            insert new List<Contact>{ ana, bea };
            Rollup_Definition__c perHousehold = definition(
                'Affiliation__c',
                'Contact__c > {Household}',
                null
            );
            Id affiliationId = fakeId(Affiliation__c.SObjectType);

            Test.startTest();
            RollupChanges.Marked marked = RollupChanges.forSave(
                'Affiliation__c',
                new List<SObject>{ new Affiliation__c(Id = affiliationId, Contact__c = bea.Id) },
                new Map<Id, SObject>{
                    affiliationId => new Affiliation__c(Id = affiliationId, Contact__c = ana.Id)
                },
                false,
                new List<Rollup_Definition__c>{ perHousehold }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ nolan.Id, lee.Id },
                markedAccounts(marked),
                'The household it left and the one it joined'
            );
        }
    }

    @IsTest
    static void aPersonWhoMovesMarksBothHouseholdsForHouseholdTotals() {
        System.runAs(TestUsers.admin()) {
            Account nolan = household('The Nolan Family');
            Account lee = household('The Lee Family');
            insert new List<Account>{ nolan, lee };
            Contact ana = new Contact(FirstName = 'Ana', LastName = 'Nolan', AccountId = nolan.Id);
            insert ana;
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                definition('Affiliation__c', 'Contact__c > {Household}', null)
            };
            Contact before = new Contact(Id = ana.Id, AccountId = nolan.Id, LastName = 'Nolan');

            Test.startTest();
            RollupChanges.Marked moved = RollupChanges.forSave(
                'Contact',
                new List<SObject>{
                    new Contact(Id = ana.Id, AccountId = lee.Id, LastName = 'Nolan')
                },
                new Map<Id, SObject>{ ana.Id => before },
                false,
                definitions
            );
            RollupChanges.Marked renamed = RollupChanges.forSave(
                'Contact',
                new List<SObject>{
                    new Contact(Id = ana.Id, AccountId = nolan.Id, LastName = 'Lee')
                },
                new Map<Id, SObject>{ ana.Id => before },
                false,
                definitions
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ nolan.Id, lee.Id },
                markedAccounts(moved),
                'Both households, so her totals leave one and join the other'
            );
            Assert.isTrue(renamed.isEmpty(), 'A rename moves no household total');
        }
    }

    /** A total that reads a parent's attribute moves when the parent changes it (R-R11). */
    @IsTest
    static void aChangeReadThroughARelationshipMarksTheRowsUnderIt() {
        System.runAs(TestUsers.admin()) {
            Account riverbend = organization('Riverbend');
            insert riverbend;
            Contact ana = new Contact(FirstName = 'Ana', LastName = 'Okafor');
            insert ana;
            insert new Affiliation__c(Contact__c = ana.Id, Organization__c = riverbend.Id);
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                definition(
                    'Affiliation__c',
                    'Organization__c',
                    filter('Contact__r.Deceased__c', 'equals', false)
                )
            };
            Contact before = new Contact(Id = ana.Id, LastName = 'Okafor', Deceased__c = false);

            Test.startTest();
            RollupChanges.Marked marked = RollupChanges.forSave(
                'Contact',
                new List<SObject>{
                    new Contact(Id = ana.Id, LastName = 'Okafor', Deceased__c = true)
                },
                new Map<Id, SObject>{ ana.Id => before },
                false,
                definitions
            );
            RollupChanges.Marked unread = RollupChanges.forSave(
                'Contact',
                new List<SObject>{
                    new Contact(Id = ana.Id, LastName = 'Other', Deceased__c = false)
                },
                new Map<Id, SObject>{ ana.Id => before },
                false,
                definitions
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ riverbend.Id },
                markedAccounts(marked),
                'The organization whose total counts Ana\'s affiliation'
            );
            Assert.isTrue(unread.isEmpty(), 'An attribute nobody reads marks nothing');
        }
    }

    /**
     * The platform deletes a household's membership rows with it and restores them with it,
     * without their triggers: their targets are read before the delete and after the undelete.
     */
    @IsTest
    static void aDeleteMarksTheTotalsOfTheRowsDeletedWithIt() {
        System.runAs(TestUsers.admin()) {
            Account nolan = household('The Nolan Family');
            Account riverbend = organization('Riverbend');
            insert new List<Account>{ nolan, riverbend };
            Contact ana = new Contact(FirstName = 'Ana', LastName = 'Nolan');
            insert ana;
            insert new Household_Member__c(
                Household__c = nolan.Id,
                Contact__c = ana.Id,
                Account__c = riverbend.Id
            );
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                definition('Household_Member__c', 'Account__c', null)
            };

            Test.startTest();
            RollupDependents.beforeDelete(
                Account.SObjectType,
                new List<SObject>{ nolan },
                definitions
            );
            RollupChanges.Marked deleted = RollupChanges.afterDelete(
                'Account',
                new List<SObject>{ nolan },
                definitions
            );
            RollupChanges.Marked handedOver = RollupDependents.takeReadBeforeDelete();
            RollupChanges.Marked restored = RollupChanges.forSave(
                'Account',
                new List<SObject>{ nolan },
                null,
                true,
                definitions
            );
            Test.stopTest();

            Assert.isTrue(
                markedAccounts(deleted).contains(riverbend.Id),
                'The organization the deleted membership counted towards'
            );
            Assert.isTrue(handedOver.isEmpty(), 'Held targets are handed over once');
            Assert.isTrue(
                markedAccounts(restored).contains(riverbend.Id),
                'And again when the household is restored'
            );
        }
    }

    @IsTest
    static void aFewTargetsAreRecalculatedInTheSameSave() {
        System.runAs(TestUsers.admin()) {
            insert definition('Account', 'ParentId', null);
            Account parent = organization('Parent');
            insert parent;
            Account child = organization('Child');
            child.ParentId = parent.Id;
            insert child;
            TriggerHandler.clearRunClaims();
            TriggerHandler.testNew = new List<SObject>{ child };

            Test.startTest();
            new RollupTriggerHandler().afterInsert();
            Integer queued = [SELECT COUNT() FROM Rollup_Queue__c];
            Account counted = [SELECT NumberOfEmployees FROM Account WHERE Id = :parent.Id];
            Test.stopTest();

            Assert.areEqual(1, counted.NumberOfEmployees, 'Right before the save returned');
            Assert.areEqual(0, queued, 'Nothing queued');
        }
    }

    @IsTest
    static void aBulkChangeIsQueuedAndCaughtUpInTheBackground() {
        System.runAs(TestUsers.admin()) {
            insert definition('Account', 'ParentId', null);
            Account parent = organization('Parent');
            insert parent;
            List<Account> children = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                Account child = organization('Child ' + i);
                child.ParentId = parent.Id;
                children.add(child);
            }
            insert children;
            RollupService.instantLimit = 0;
            TriggerHandler.clearRunClaims();
            TriggerHandler.testNew = children;

            Test.startTest();
            new RollupTriggerHandler().afterInsert();
            Integer queued = [SELECT COUNT() FROM Rollup_Queue__c];
            Test.stopTest();

            Assert.areEqual(1, queued, 'Two hundred saves to one parent: one entry');
            Assert.areEqual(
                200,
                [SELECT NumberOfEmployees FROM Account WHERE Id = :parent.Id].NumberOfEmployees,
                'Caught up by the processor'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Queue__c], 'And the entry is gone');
        }
    }

    @IsTest
    static void aSaveInTheBackgroundOrOverTheLimitIsQueued() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(RollupService.canRecalculateNow(1), 'A normal save of one record');
            Assert.isFalse(
                RollupService.canRecalculateNow(RollupService.instantLimit + 1),
                'More than the instant limit'
            );
        }
    }

    @IsTest
    static void aDefinitionReadsItsAttributesPathAndFilter() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c fund = definition(
                'Affiliation__c',
                'Contact__c > {Household} | Organization__c',
                filter('Contact__r.Deceased__c', 'equals', false)
            );
            fund.Source_Field__c = 'Start_Date__c';

            Set<String> reads = RollupChanges.readsOf(
                fund,
                RollupPath.parse(fund.Relationship_Path__c)
            );

            Assert.areEqual(
                new Set<String>{
                    'Start_Date__c',
                    'Contact__r.Deceased__c',
                    'Contact__c',
                    'Organization__c'
                },
                reads,
                'Source, filter and every path alternative'
            );
            Assert.isTrue(
                RollupFilterParser.fieldsOf('not a filter').isEmpty(),
                'An unreadable filter names nothing'
            );
        }
    }
}
