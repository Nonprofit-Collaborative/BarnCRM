/**
 * Saved Super Transform step lists (C-50f1, canonical model Section 29P): save, list, load,
 * rename and delete as a person who holds BarnCRM Bulk Update, org-wide visibility between two
 * such people, and refusal of a document or a name that is not usable.
 */
@IsTest(testFor='ApexClass:SavedTransformService, ApexClass:BulkUpdateController')
private class SavedTransformServiceTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.createUser(
                'Maria',
                new List<String>{ 'BarnCRM_Find_And_Export', 'BarnCRM_Bulk_Update' }
            );
            TestDataFactory.createUser(
                'Joel',
                new List<String>{ 'BarnCRM_Find_And_Export', 'BarnCRM_Bulk_Update' }
            );
            TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Find_And_Export' });
        }
    }

    private static User named(String firstName) {
        String prefix = 'barn-test.' + firstName.toLowerCase() + '.%';
        return [SELECT Id FROM User WHERE Username LIKE :prefix LIMIT 1];
    }

    private static String definition() {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => 'Contact',
                'filter' => new Map<String, Object>{
                    'version' => 1,
                    'conditions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 1,
                            'field' => 'Title',
                            'operator' => 'equals',
                            'value' => 'Volunteer'
                        }
                    }
                },
                'changes' => new List<Object>{
                    new Map<String, Object>{
                        'field' => 'Phone',
                        'action' => 'transform',
                        'transforms' => new List<Object>{
                            new Map<String, Object>{
                                'op' => 'digits',
                                'pattern' => '(###) ###-####',
                                'country' => '1'
                            }
                        }
                    },
                    new Map<String, Object>{
                        'field' => 'Title',
                        'action' => 'set',
                        'value' => 'Coordinator'
                    }
                }
            }
        );
    }

    private static String withChanges(Object changes) {
        return JSON.serialize(
            new Map<String, Object>{ 'version' => 1, 'object' => 'Contact', 'changes' => changes }
        );
    }

    private static void assertRefused(String json, String name, String why) {
        try {
            SavedTransformService.save(name, json);
            System.assert(false, 'Refused: ' + why);
        } catch (BulkUpdateFields.BulkUpdateException refused) {
            System.assertNotEquals(null, refused.getMessage(), why);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Saved_Transform__c], 'Nothing saved: ' + why);
    }

    @IsTest
    static void aListSavesLoadsRenamesAndDeletes() {
        System.runAs(named('Maria')) {
            SavedTransformService.SavedList saved = SavedTransformService.save(
                '  Tidy   volunteer phones ',
                definition()
            );
            System.assertEquals('Tidy volunteer phones', saved.name, 'Spaces are tidied.');
            System.assertEquals('Contact', saved.objectName);

            List<SavedTransformService.ListEntry> entries = SavedTransformService.listAll();
            System.assertEquals(1, entries.size());
            System.assertEquals('Tidy volunteer phones', entries[0].name);
            System.assertEquals('Contact', entries[0].objectName);
            System.assertEquals('Contact', entries[0].objectLabel);

            SavedTransformService.SavedList loaded = SavedTransformService.load(saved.recordId);
            System.assertEquals(
                definition(),
                loaded.definitionJson,
                'The document is stored as sent.'
            );

            SavedTransformService.SavedList renamed = SavedTransformService.rename(
                saved.recordId,
                'Phones'
            );
            System.assertEquals('Phones', renamed.name);
            System.assertEquals(
                definition(),
                SavedTransformService.load(saved.recordId).definitionJson,
                'A rename leaves the document alone.'
            );

            SavedTransformService.remove(saved.recordId);
            System.assertEquals(0, SavedTransformService.listAll().size());
        }
    }

    private static String withFilter(List<Object> conditions, String logic) {
        Map<String, Object> filter = new Map<String, Object>{
            'version' => 1,
            'conditions' => conditions
        };
        if (logic != null) {
            filter.put('logic', logic);
        }
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => 'Contact',
                'filter' => filter,
                'changes' => new List<Object>()
            }
        );
    }

    private static Map<String, Object> condition(Integer id, String field) {
        return new Map<String, Object>{
            'id' => id,
            'field' => field,
            'operator' => 'equals',
            'value' => 'x'
        };
    }

    @IsTest
    static void loadingDropsConditionsWhoseFieldIsGoneAndCountsThem() {
        System.runAs(named('Maria')) {
            SavedTransformService.SavedList saved = SavedTransformService.save(
                'Stale',
                withFilter(
                    new List<Object>{
                        condition(1, 'Title'),
                        condition(2, 'Gone__c'),
                        condition(3, 'Account.Nothing__c')
                    },
                    '1 OR (2 AND 3)'
                )
            );
            SavedTransformService.SavedList loaded = SavedTransformService.load(saved.recordId);
            System.assertEquals(2, loaded.droppedConditions);
            Map<String, Object> filter = (Map<String, Object>) ((Map<String, Object>) JSON.deserializeUntyped(
                    loaded.definitionJson
                ))
                .get('filter');
            System.assertEquals(1, ((List<Object>) filter.get('conditions')).size());
            System.assertEquals(false, filter.containsKey('logic'), 'Logic no longer fits.');

            SavedTransformService.SavedList everything = SavedTransformService.save(
                'All stale',
                withFilter(new List<Object>{ condition(1, 'Gone__c') }, null)
            );
            SavedTransformService.SavedList none = SavedTransformService.load(everything.recordId);
            System.assertEquals(1, none.droppedConditions);
            System.assertEquals(
                false,
                ((Map<String, Object>) JSON.deserializeUntyped(none.definitionJson))
                    .containsKey('filter'),
                'No condition left means no filter.'
            );

            SavedTransformService.SavedList fine = SavedTransformService.save(
                'Fine',
                withFilter(new List<Object>{ condition(1, 'Title') }, null)
            );
            System.assertEquals(0, SavedTransformService.load(fine.recordId).droppedConditions);
        }
    }

    @IsTest
    static void aListIsOrgWide() {
        String savedId;
        System.runAs(named('Maria')) {
            savedId = SavedTransformService.save('Shared list', definition()).recordId;
        }
        System.runAs(named('Joel')) {
            System.assertEquals(1, SavedTransformService.listAll().size(), 'Joel sees it.');
            System.assertEquals('Joels', SavedTransformService.rename(savedId, 'Joels').name);
            SavedTransformService.remove(savedId);
        }
        System.runAs(named('Maria')) {
            System.assertEquals(0, SavedTransformService.listAll().size(), 'It is gone for all.');
        }
    }

    @IsTest
    static void aNameIsKeptUniqueIgnoringCapitals() {
        System.runAs(named('Maria')) {
            SavedTransformService.SavedList first = SavedTransformService.save(
                'Phones',
                definition()
            );
            try {
                SavedTransformService.save('PHONES', definition());
                System.assert(false, 'A second list may not share the name.');
            } catch (BulkUpdateFields.BulkUpdateException taken) {
                System.assert(taken.getMessage().contains('PHONES'), taken.getMessage());
            }
            SavedTransformService.SavedList second = SavedTransformService.save(
                'Other',
                definition()
            );
            try {
                SavedTransformService.rename(second.recordId, 'phones');
                System.assert(false, 'A rename may not take another list name.');
            } catch (BulkUpdateFields.BulkUpdateException taken) {
                System.assertNotEquals(null, taken.getMessage());
            }
            System.assertEquals(
                'Phones',
                SavedTransformService.rename(first.recordId, 'Phones').name,
                'A list may keep its own name.'
            );
        }
    }

    @IsTest
    static void aBadNameIsRefused() {
        System.runAs(named('Maria')) {
            assertRefused(definition(), null, 'no name');
            assertRefused(definition(), '   ', 'blank name');
            assertRefused(
                definition(),
                'x'.repeat(SavedTransformService.MAX_NAME + 1),
                'long name'
            );
        }
    }

    @IsTest
    static void aBadDocumentIsRefused() {
        System.runAs(named('Maria')) {
            assertRefused(null, 'Empty', 'no document');
            assertRefused('not json', 'Text', 'unreadable');
            assertRefused('[]', 'Array', 'not an object');
            assertRefused(
                JSON.serialize(
                    new Map<String, Object>{
                        'version' => 2,
                        'object' => 'Contact',
                        'changes' => new List<Object>()
                    }
                ),
                'Version',
                'unknown version'
            );
            assertRefused(
                JSON.serialize(
                    new Map<String, Object>{
                        'version' => 1,
                        'object' => 'Nothing__c',
                        'changes' => new List<Object>()
                    }
                ),
                'Object',
                'unknown object'
            );
            assertRefused(
                JSON.serialize(
                    new Map<String, Object>{
                        'version' => 1,
                        'object' => 'Contact',
                        'filter' => 'x',
                        'changes' => new List<Object>()
                    }
                ),
                'Filter',
                'filter is not a document'
            );
            assertRefused(
                JSON.serialize(new Map<String, Object>{ 'version' => 1, 'object' => 'Contact' }),
                'NoChanges',
                'no changes list'
            );
            assertRefused(
                withChanges(
                    new List<Object>{
                        new Map<String, Object>{ 'field' => 'Title', 'action' => 'shred' }
                    }
                ),
                'Action',
                'unknown action'
            );
            assertRefused(
                withChanges(new List<Object>{ new Map<String, Object>{ 'action' => 'set' } }),
                'Field',
                'no field'
            );
            assertRefused(
                withChanges(new List<Object>{ 'Title' }),
                'Shape',
                'change is not an object'
            );
            List<Object> tooMany = new List<Object>();
            for (Integer count = 0; count <= BulkUpdateService.MAX_CHANGES; count++) {
                tooMany.add(new Map<String, Object>{ 'field' => 'Title', 'action' => 'clear' });
            }
            assertRefused(withChanges(tooMany), 'Many', 'too many changes');
            assertRefused(
                withChanges(
                    new List<Object>{
                        new Map<String, Object>{
                            'field' => 'Phone',
                            'action' => 'transform',
                            'transforms' => new List<Object>{
                                new Map<String, Object>{ 'op' => 'digits', 'pattern' => 'none' }
                            }
                        }
                    }
                ),
                'Steps',
                'steps with a problem'
            );
            assertRefused(
                JSON.serialize(
                    new Map<String, Object>{
                        'version' => 1,
                        'object' => 'Contact',
                        'changes' => new List<Object>(),
                        'pad' => 'x'.repeat(SavedTransformService.MAX_DOCUMENT)
                    }
                ),
                'Big',
                'too large'
            );
        }
    }

    @IsTest
    static void aMissingListIsSaidSo() {
        System.runAs(named('Maria')) {
            try {
                SavedTransformService.load(null);
                System.assert(false, 'No list.');
            } catch (BulkUpdateFields.BulkUpdateException gone) {
                System.assertEquals(Label.Core_SavedTransform_ErrorNotFound, gone.getMessage());
            }
            try {
                SavedTransformService.remove(
                    Saved_Transform__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000'
                );
                System.assert(false, 'No list.');
            } catch (BulkUpdateFields.BulkUpdateException gone) {
                System.assertEquals(Label.Core_SavedTransform_ErrorNotFound, gone.getMessage());
            }
        }
    }

    @IsTest
    static void theControllerRunsTheSameSteps() {
        System.runAs(named('Maria')) {
            SavedTransformService.SavedList saved = BulkUpdateController.saveSavedList(
                'Via page',
                definition()
            );
            System.assertEquals(1, BulkUpdateController.getSavedLists().size());
            System.assertEquals(
                'Via page',
                BulkUpdateController.loadSavedList(saved.recordId).name
            );
            System.assertEquals(
                'Renamed',
                BulkUpdateController.renameSavedList(saved.recordId, 'Renamed').name
            );
            BulkUpdateController.deleteSavedList(saved.recordId);
            System.assertEquals(0, BulkUpdateController.getSavedLists().size());
        }
    }

    @IsTest
    static void theControllerRefusesAPersonWithoutBulkUpdate() {
        System.runAs(named('David')) {
            try {
                BulkUpdateController.getSavedLists();
                System.assert(false, 'Find and Export alone may not use saved lists.');
            } catch (AuraHandledException refused) {
                System.assertNotEquals(null, refused);
            }
            try {
                BulkUpdateController.saveSavedList('Nope', definition());
                System.assert(false, 'Nor save one.');
            } catch (AuraHandledException refused) {
                System.assertNotEquals(null, refused);
            }
        }
    }
}
