/**
 * Pins which targets an update marks, definition by definition, so that the per-transaction
 * memo of parsed paths and read sets in `RollupChanges` (D-143) is held to the result the
 * unmemoized collector gave: a change to an attribute a definition reads (its source, order-by,
 * filter or path attribute) marks that definition's targets, old and new; a change to anything
 * else marks nothing; a definition edited in the same transaction is read as it now is.
 */
@IsTest(testFor='ApexClass:RollupChanges')
private class RollupChangeDetectionTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Rollup_Definition__c definition(Integer n, String source, String path) {
        return new Rollup_Definition__c(
            Id = FakeIds.of(Rollup_Definition__c.SObjectType, n),
            Name = 'Detection ' + n,
            Definition_Key__c = 'Detection_' + n,
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

    private static String filterOn(String field) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => field,
                        'operator' => 'equals',
                        'value' => 'x'
                    }
                }
            }
        );
    }

    private static Id parent(Integer n) {
        return FakeIds.of(Account.SObjectType, 100 + n);
    }

    private static Account child(Integer n, Id parentId) {
        return new Account(
            Id = FakeIds.of(Account.SObjectType, n),
            Name = 'Child ' + n,
            ParentId = parentId,
            AnnualRevenue = 10,
            Industry = 'Education',
            Rating = 'Warm',
            Description = 'Before'
        );
    }

    private static Set<Id> marked(RollupChanges.Marked result) {
        Set<Id> ids = result.idsByTarget.get('account');
        return ids == null ? new Set<Id>() : ids;
    }

    private static Set<Id> definitionIds(RollupChanges.Marked result) {
        Set<Id> ids = new Set<Id>();
        List<Rollup_Definition__c> named = result.definitionsFor('Account');
        for (
            Rollup_Definition__c definition : named == null
                ? new List<Rollup_Definition__c>()
                : named
        ) {
            ids.add(definition.Id);
        }
        return ids;
    }

    /** One save of six children, each changing something different. */
    private class Save {
        List<SObject> records = new List<SObject>();
        Map<Id, SObject> oldRecords = new Map<Id, SObject>();

        Save() {
            // 1: an attribute nobody reads; 2: the source; 3: the filter; 4: the order-by;
            // 5: moved to another parent; 6: nothing at all.
            for (Integer n = 1; n <= 6; n++) {
                Account before = child(n, parent(n));
                Account now = before.clone(true);
                if (n == 1) {
                    now.Description = 'After';
                } else if (n == 2) {
                    now.AnnualRevenue = 20;
                } else if (n == 3) {
                    now.Industry = 'Energy';
                } else if (n == 4) {
                    now.Rating = 'Hot';
                } else if (n == 5) {
                    now.ParentId = parent(50);
                }
                this.records.add(now);
                this.oldRecords.put(now.Id, before);
            }
        }

        RollupChanges.Marked run(List<Rollup_Definition__c> definitions) {
            return RollupChanges.forSave(
                'Account',
                this.records,
                this.oldRecords,
                false,
                definitions
            );
        }
    }

    @IsTest
    static void anUpdateMarksExactlyWhatEachDefinitionReads() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c bySource = definition(1, 'Account', 'ParentId');
            bySource.Source_Field__c = 'AnnualRevenue';
            Rollup_Definition__c byFilter = definition(2, 'Account', 'ParentId');
            byFilter.Filter_JSON__c = filterOn('Industry');
            Rollup_Definition__c byOrder = definition(3, 'Account', 'ParentId');
            byOrder.Order_By_Field__c = 'Rating';
            Rollup_Definition__c staff = definition(4, 'Contact', 'AccountId');
            Rollup_Definition__c samePath = definition(5, 'Account', 'ParentId');
            samePath.Source_Field__c = 'AnnualRevenue';
            Save save = new Save();

            Test.startTest();
            RollupChanges.Marked source = save.run(new List<Rollup_Definition__c>{ bySource });
            RollupChanges.Marked filtered = save.run(new List<Rollup_Definition__c>{ byFilter });
            RollupChanges.Marked ordered = save.run(new List<Rollup_Definition__c>{ byOrder });
            RollupChanges.Marked other = save.run(new List<Rollup_Definition__c>{ staff });
            RollupChanges.Marked all = save.run(
                new List<Rollup_Definition__c>{ bySource, byFilter, byOrder, staff, samePath }
            );
            RollupChanges.Marked again = save.run(
                new List<Rollup_Definition__c>{ bySource, byFilter, byOrder, staff, samePath }
            );
            Test.stopTest();

            Set<Id> moved = new Set<Id>{ parent(5), parent(50) };
            Set<Id> expectSource = new Set<Id>{ parent(2) };
            expectSource.addAll(moved);
            Set<Id> expectFilter = new Set<Id>{ parent(3) };
            expectFilter.addAll(moved);
            Set<Id> expectOrder = new Set<Id>{ parent(4) };
            expectOrder.addAll(moved);
            Set<Id> expectAll = new Set<Id>{ parent(2), parent(3), parent(4) };
            expectAll.addAll(moved);

            Assert.areEqual(expectSource, marked(source), 'The source attribute and the move');
            Assert.areEqual(expectFilter, marked(filtered), 'The filter attribute and the move');
            Assert.areEqual(expectOrder, marked(ordered), 'The order-by attribute and the move');
            Assert.isTrue(other.isEmpty(), 'A definition of another source marks nothing');
            Assert.areEqual(expectAll, marked(all), 'Together: the union, nothing more');
            Assert.areEqual(
                new Set<Id>{ bySource.Id, byFilter.Id, byOrder.Id, samePath.Id },
                definitionIds(all),
                'Each definition that marked is named, the other source is not'
            );
            Assert.areEqual(marked(all), marked(again), 'A second save marks the same');
            Assert.areEqual(definitionIds(all), definitionIds(again), 'And names the same');
        }
    }

    @IsTest
    static void anUpdateOfNothingAnyDefinitionReadsMarksNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c byFilter = definition(1, 'Account', 'ParentId');
            byFilter.Filter_JSON__c = filterOn('Industry');
            byFilter.Source_Field__c = 'AnnualRevenue';
            List<SObject> records = new List<SObject>();
            Map<Id, SObject> oldRecords = new Map<Id, SObject>();
            for (Integer n = 1; n <= 200; n++) {
                Account before = child(n, parent(n));
                Account now = before.clone(true);
                now.Description = 'After';
                records.add(now);
                oldRecords.put(now.Id, before);
            }

            Test.startTest();
            RollupChanges.Marked result = RollupChanges.forSave(
                'Account',
                records,
                oldRecords,
                false,
                new List<Rollup_Definition__c>{ byFilter }
            );
            Test.stopTest();

            Assert.isTrue(result.isEmpty(), '200 changes to an unread attribute mark nothing');
        }
    }

    @IsTest
    static void aDefinitionEditedInTheTransactionIsReadAsItNowIs() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c byFilter = definition(1, 'Account', 'ParentId');
            byFilter.Filter_JSON__c = filterOn('Industry');
            Save save = new Save();

            Test.startTest();
            RollupChanges.Marked first = save.run(new List<Rollup_Definition__c>{ byFilter });
            byFilter.Filter_JSON__c = filterOn('Rating');
            RollupChanges.Marked second = save.run(new List<Rollup_Definition__c>{ byFilter });
            byFilter.Filter_JSON__c = null;
            byFilter.Relationship_Path__c = 'Parent Id!';
            RollupChanges.Marked broken = save.run(new List<Rollup_Definition__c>{ byFilter });
            byFilter.Relationship_Path__c = 'ParentId';
            RollupChanges.Marked mended = save.run(new List<Rollup_Definition__c>{ byFilter });
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ parent(3), parent(5), parent(50) },
                marked(first),
                'Filtered on industry: the industry change and the move'
            );
            Assert.areEqual(
                new Set<Id>{ parent(4), parent(5), parent(50) },
                marked(second),
                'Refiltered on rating: the rating change and the move, no longer the industry'
            );
            Assert.isTrue(broken.isEmpty(), 'A path that cannot be read marks nothing');
            Assert.areEqual(
                new Set<Id>{ parent(5), parent(50) },
                marked(mended),
                'Mended, with no filter: only the move'
            );
        }
    }

    @IsTest
    static void anInsertOrARecordWithNoPriorVersionMarksEveryRecord() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c byFilter = definition(1, 'Account', 'ParentId');
            byFilter.Filter_JSON__c = filterOn('Industry');
            Save save = new Save();
            Map<Id, SObject> partial = save.oldRecords.clone();
            partial.remove(save.records[0].Id);

            Test.startTest();
            RollupChanges.Marked inserted = RollupChanges.forSave(
                'Account',
                save.records,
                null,
                false,
                new List<Rollup_Definition__c>{ byFilter }
            );
            RollupChanges.Marked restored = RollupChanges.forSave(
                'Account',
                save.records,
                null,
                true,
                new List<Rollup_Definition__c>{ byFilter }
            );
            RollupChanges.Marked unmatched = RollupChanges.forSave(
                'Account',
                save.records,
                partial,
                false,
                new List<Rollup_Definition__c>{ byFilter }
            );
            Test.stopTest();

            Set<Id> everyNewParent = new Set<Id>{
                parent(1),
                parent(2),
                parent(3),
                parent(4),
                parent(50),
                parent(6)
            };
            Assert.areEqual(everyNewParent, marked(inserted), 'An insert marks every record');
            Assert.areEqual(everyNewParent, marked(restored), 'So does an undelete');
            Assert.areEqual(
                new Set<Id>{ parent(1), parent(3), parent(5), parent(50) },
                marked(unmatched),
                'A record with no prior version is marked as new; the rest only on a read change'
            );
        }
    }
}
