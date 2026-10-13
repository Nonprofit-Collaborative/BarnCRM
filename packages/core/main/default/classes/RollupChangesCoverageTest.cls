/**
 * The branches of RollupChanges the main suite leaves out: the collection helpers, saves that
 * name nothing the engine can read, a path the parser refuses, paths that walk more than one
 * reference, the household members token, and the survivor of a merge. It tests the class's
 * current public behavior only.
 */
@IsTest(testFor='ApexClass:RollupChanges')
private class RollupChangesCoverageTest {
    private static Account household(String name) {
        return new Account(Name = name, RecordTypeId = HouseholdService.householdRecordTypeId());
    }

    private static Account organization(String name) {
        return new Account(
            Name = name,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    private static Rollup_Definition__c definition(String source, String path) {
        return new Rollup_Definition__c(
            Name = 'Coverage count',
            Definition_Key__c = 'Coverage_Count_' + source,
            Source_Object__c = source,
            Relationship_Path__c = path,
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static Set<Id> marked(RollupChanges.Marked result) {
        Set<Id> ids = result.idsByTarget.get('account');
        return ids == null ? new Set<Id>() : ids;
    }

    @IsTest
    static void markedKeepsOnlyRealIdsUnderALowerCasedTarget() {
        System.runAs(TestUsers.admin()) {
            Id first = FakeIds.of(Account.SObjectType, 1);
            Id second = FakeIds.of(Account.SObjectType, 2);
            RollupChanges.Marked collected = new RollupChanges.Marked();
            Assert.isTrue(collected.isEmpty(), 'Nothing is marked to begin with');
            Assert.areEqual(0, collected.size(), 'And the count is zero');

            collected.add(null, new Set<Id>{ first });
            collected.add('  ', new Set<Id>{ first });
            collected.add('Account', null);
            collected.add('Account', new Set<Id>{ null });
            Assert.isTrue(
                collected.isEmpty(),
                'A blank target, no ids, or a null id marks nothing'
            );

            collected.add('ACCOUNT', new Set<Id>{ first, null });
            RollupChanges.Marked other = new RollupChanges.Marked();
            other.add('account', new Set<Id>{ first, second });
            other.add('Contact', new Set<Id>{ FakeIds.of(Contact.SObjectType, 1) });
            collected.addAll(other);

            Assert.areEqual(
                new Set<Id>{ first, second },
                collected.idsByTarget.get('account'),
                'Targets are keyed in lower case and merged without duplicates'
            );
            Assert.areEqual(3, collected.size(), 'Two accounts and one contact');
            Assert.isFalse(collected.isEmpty(), 'Something is marked now');
        }
    }

    @IsTest
    static void aSaveThatNamesNothingTheEngineCanReadMarksNothing() {
        System.runAs(TestUsers.admin()) {
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                definition('Account', 'ParentId')
            };
            Account child = organization('Child');
            child.Id = FakeIds.of(Account.SObjectType, 5);
            child.ParentId = FakeIds.of(Account.SObjectType, 6);

            Assert.isTrue(
                RollupChanges.forSave(
                        'Not_An_Object__c',
                        new List<SObject>{ child },
                        null,
                        false,
                        definitions
                    )
                    .isEmpty(),
                'An entity the org does not have marks nothing'
            );
            Assert.isTrue(
                RollupChanges.forSave('Account', null, null, false, definitions).isEmpty(),
                'No records marks nothing'
            );
            Assert.isTrue(
                RollupChanges.forSave('Account', new List<SObject>(), null, false, definitions)
                    .isEmpty(),
                'An empty save marks nothing'
            );
            Assert.isTrue(
                RollupChanges.afterDelete(
                        'Not_An_Object__c',
                        new List<SObject>{ child },
                        definitions
                    )
                    .isEmpty(),
                'A delete of an unknown entity marks nothing'
            );
            Assert.isTrue(
                RollupChanges.afterDelete('Account', null, definitions).isEmpty(),
                'A delete of no records marks nothing'
            );
            Assert.isTrue(
                RollupChanges.afterDelete('Account', new List<SObject>(), definitions).isEmpty(),
                'A delete of an empty list marks nothing'
            );
            Assert.areEqual(
                new Set<Id>{ child.ParentId },
                marked(
                    RollupChanges.forSave(
                        'Account',
                        new List<SObject>{ child },
                        null,
                        false,
                        definitions
                    )
                ),
                'The same save does mark the parent once the entity is real'
            );
            Assert.areEqual(
                new Set<Id>{ child.ParentId },
                marked(
                    RollupChanges.afterDelete('Account', new List<SObject>{ child }, definitions)
                ),
                'And so does its delete'
            );
        }
    }

    @IsTest
    static void aDefinitionWhosePathCannotBeReadIsSkippedNotFatal() {
        System.runAs(TestUsers.admin()) {
            Rollup_Definition__c broken = definition('Account', 'Parent Id!');
            Rollup_Definition__c blank = definition('Account', null);
            Account child = organization('Child');
            child.Id = FakeIds.of(Account.SObjectType, 5);
            child.ParentId = FakeIds.of(Account.SObjectType, 6);
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                broken,
                blank,
                definition('Account', 'ParentId')
            };

            Test.startTest();
            Assert.isNull(RollupChanges.pathOf(broken), 'A path with a space is refused');
            Assert.isNull(RollupChanges.pathOf(blank), 'A missing path is refused');
            RollupChanges.Marked saved = RollupChanges.forSave(
                'Account',
                new List<SObject>{ child },
                null,
                false,
                definitions
            );
            RollupChanges.Marked deleted = RollupChanges.afterDelete(
                'Account',
                new List<SObject>{ child },
                definitions
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ child.ParentId },
                marked(saved),
                'The readable definition still marks its parent'
            );
            Assert.areEqual(
                new Set<Id>{ child.ParentId },
                marked(deleted),
                'And still does on a delete'
            );
        }
    }

    @IsTest
    static void aPathThroughTwoReferencesMarksTheRecordAtTheEnd() {
        System.runAs(TestUsers.admin()) {
            RelationshipTestDataFactory.quietOtherAutomations();
            Account grandparent = organization('Grandparent');
            insert grandparent;
            Account parent = organization('Parent');
            parent.ParentId = grandparent.Id;
            insert parent;
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Okafor',
                AccountId = parent.Id
            );
            insert ana;
            Id affiliationId = FakeIds.of(Affiliation__c.SObjectType, 1);
            Affiliation__c saved = new Affiliation__c(Id = affiliationId, Contact__c = ana.Id);

            Test.startTest();
            RollupChanges.Marked oneStep = RollupChanges.forSave(
                'Affiliation__c',
                new List<SObject>{ saved },
                null,
                false,
                new List<Rollup_Definition__c>{
                    definition('Affiliation__c', 'Contact__c > AccountId')
                }
            );
            RollupChanges.Marked twoSteps = RollupChanges.forSave(
                'Affiliation__c',
                new List<SObject>{ saved },
                null,
                false,
                new List<Rollup_Definition__c>{
                    definition('Affiliation__c', 'Contact__c > AccountId > ParentId')
                }
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ parent.Id },
                marked(oneStep),
                'The account the person is on'
            );
            Assert.areEqual(
                new Set<Id>{ grandparent.Id },
                marked(twoSteps),
                'And the one above it when the path goes a step further'
            );
        }
    }

    @IsTest
    static void aPathThatCannotBeWalkedMarksNothingAndIsLogged() {
        System.runAs(TestUsers.admin()) {
            Contact ana = new Contact(FirstName = 'Ana', LastName = 'Okafor');
            insert ana;
            Id affiliationId = FakeIds.of(Affiliation__c.SObjectType, 1);
            Affiliation__c saved = new Affiliation__c(Id = affiliationId, Contact__c = ana.Id);

            Test.startTest();
            RollupChanges.Marked unknownFirst = RollupChanges.forSave(
                'Affiliation__c',
                new List<SObject>{ saved },
                null,
                false,
                new List<Rollup_Definition__c>{ definition('Affiliation__c', 'Nobody__c') }
            );
            RollupChanges.Marked unknownSecond = RollupChanges.forSave(
                'Affiliation__c',
                new List<SObject>{ saved },
                null,
                false,
                new List<Rollup_Definition__c>{
                    definition('Affiliation__c', 'Contact__c > NoSuchReference')
                }
            );
            Test.stopTest();

            Assert.isTrue(
                unknownFirst.isEmpty(),
                'A reference the entity does not have marks nothing'
            );
            Assert.isTrue(
                unknownSecond.isEmpty(),
                'A second step the query cannot read marks nothing and does not throw'
            );
        }
    }

    @IsTest
    static void aHouseholdMembersPathMarksEveryoneInTheHousehold() {
        System.runAs(TestUsers.admin()) {
            Account nolan = household('The Nolan Family');
            Account lee = household('The Lee Family');
            insert new List<Account>{ nolan, lee };
            Contact ana = new Contact(FirstName = 'Ana', LastName = 'Nolan', AccountId = nolan.Id);
            Contact ben = new Contact(FirstName = 'Ben', LastName = 'Nolan', AccountId = nolan.Id);
            Contact cal = new Contact(FirstName = 'Cal', LastName = 'Lee', AccountId = lee.Id);
            insert new List<Contact>{ ana, ben, cal };
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                definition('Affiliation__c', 'Contact__c > {HouseholdMembers}')
            };
            Id affiliationId = FakeIds.of(Affiliation__c.SObjectType, 1);

            Test.startTest();
            RollupChanges.Marked saved = RollupChanges.forSave(
                'Affiliation__c',
                new List<SObject>{ new Affiliation__c(Id = affiliationId, Contact__c = ana.Id) },
                null,
                false,
                definitions
            );
            RollupChanges.Marked moved = RollupChanges.forSave(
                'Contact',
                new List<SObject>{
                    new Contact(Id = ana.Id, AccountId = lee.Id, LastName = 'Nolan')
                },
                new Map<Id, SObject>{
                    ana.Id => new Contact(Id = ana.Id, AccountId = nolan.Id, LastName = 'Nolan')
                },
                false,
                definitions
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ ana.Id, ben.Id },
                marked(saved),
                'The household of the person saved: everyone in it, and nobody from another'
            );
            Assert.isTrue(
                marked(moved).containsAll(new Set<Id>{ ana.Id, ben.Id, cal.Id }),
                'A person who moves marks the members of both households'
            );
        }
    }

    @IsTest
    static void theSurvivorOfAMergeMarksItsHousehold() {
        System.runAs(TestUsers.admin()) {
            Account nolan = household('The Nolan Family');
            insert nolan;
            Contact survivor = new Contact(
                FirstName = 'Ana',
                LastName = 'Nolan',
                AccountId = nolan.Id
            );
            insert survivor;
            Id loserId = FakeIds.of(Contact.SObjectType, 9);
            Contact loser = (Contact) JSON.deserialize(
                '{"attributes":{"type":"Contact"},"Id":"' +
                    loserId +
                    '","LastName":"Nolan","MasterRecordId":"' +
                    survivor.Id +
                    '"}',
                Contact.class
            );
            List<Rollup_Definition__c> perHousehold = new List<Rollup_Definition__c>{
                definition('Affiliation__c', 'Contact__c > {Household}')
            };

            Test.startTest();
            RollupChanges.Marked merged = RollupChanges.afterDelete(
                'Contact',
                new List<SObject>{ loser },
                perHousehold
            );
            RollupChanges.Marked plainDelete = RollupChanges.afterDelete(
                'Contact',
                new List<SObject>{ new Contact(Id = loserId, LastName = 'Nolan') },
                perHousehold
            );
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ nolan.Id },
                marked(merged),
                'The household the surviving record is in has to be recounted'
            );
            Assert.isTrue(
                plainDelete.isEmpty(),
                'A delete that is not a merge, of a person in no household, marks nothing'
            );
        }
    }

    @IsTest
    static void aBulkOfTwoHundredMovesMarksEveryParentOnce() {
        System.runAs(TestUsers.admin()) {
            List<SObject> now = new List<SObject>();
            Map<Id, SObject> before = new Map<Id, SObject>();
            Set<Id> expected = new Set<Id>();
            for (Integer i = 1; i <= 200; i++) {
                Id childId = FakeIds.of(Account.SObjectType, i);
                Id oldParent = FakeIds.of(Account.SObjectType, 1000 + i);
                Id newParent = FakeIds.of(Account.SObjectType, 2000 + i);
                expected.add(oldParent);
                expected.add(newParent);
                now.add(new Account(Id = childId, Name = 'Child ' + i, ParentId = newParent));
                before.put(
                    childId,
                    new Account(Id = childId, Name = 'Child ' + i, ParentId = oldParent)
                );
            }

            Test.startTest();
            RollupChanges.Marked moved = RollupChanges.forSave(
                'Account',
                now,
                before,
                false,
                new List<Rollup_Definition__c>{ definition('Account', 'ParentId') }
            );
            Test.stopTest();

            Assert.areEqual(
                400,
                moved.size(),
                'Two hundred records leave one parent and join another'
            );
            Assert.areEqual(expected, marked(moved), 'Every one of the 400 parents is marked');
        }
    }

    @IsTest
    static void readingsAreResolvedFromThePathAndTheEntity() {
        System.runAs(TestUsers.admin()) {
            Map<String, Schema.SObjectField> fields = RollupChanges.fieldMap(Account.SObjectType);
            Assert.isTrue(fields.containsKey('parentid'), 'The field map is keyed in lower case');

            Set<String> local = RollupChanges.localFields(
                new Set<String>{ 'Name', 'Parent.Name', 'Owner__r.Name', 'NoSuchField__c' },
                fields
            );
            Assert.isTrue(local.contains('name'), 'A plain attribute is read as itself');
            Assert.isTrue(
                local.contains('parentid'),
                'A standard reference is read through its Id'
            );
            Assert.isFalse(
                local.contains('nosuchfield__c'),
                'An attribute the entity does not have is dropped'
            );
            Assert.isFalse(
                local.contains('owner__c'),
                'A custom reference the entity does not have is dropped too'
            );

            Account before = new Account(Name = 'Old', NumberOfEmployees = 1);
            Account after = new Account(Name = 'Old', NumberOfEmployees = 2);
            Assert.isFalse(
                RollupChanges.changed(new Set<String>{ 'name' }, after, before),
                'The same name is no change'
            );
            Assert.isTrue(
                RollupChanges.changed(
                    new Set<String>{ 'name', 'numberofemployees' },
                    after,
                    before
                ),
                'A different head count is'
            );
        }
    }
}
