/**
 * Checking and previewing a bulk update (C-35, canonical model R-BU1, R-BU2 and R-BU4): the
 * query compiled as the person, up to five checked changes, and a count that is the number the
 * person confirms.
 *
 * No org has run these yet; they are written against the behaviour the class documents.
 */
@IsTest
private class BulkUpdateServiceTest {
    private static String query(String title) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => 'Contact',
                'fields' => new List<Object>{ 'LastName', 'Title' },
                'filter' => new Map<String, Object>{
                    'version' => 1,
                    'conditions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 1,
                            'field' => 'Title',
                            'operator' => 'equals',
                            'value' => title
                        }
                    }
                },
                'limit' => 200
            }
        );
    }

    private static String changes(List<Map<String, Object>> changes) {
        return JSON.serialize(changes);
    }

    private static Map<String, Object> setTitle(String value) {
        return new Map<String, Object>{ 'field' => 'Title', 'action' => 'set', 'value' => value };
    }

    /** `volunteers` contacts titled Volunteer and `staff` titled Staff, with work emails. */
    private static void makePeople(Integer volunteers, Integer staff) {
        Account organization = new Account(Name = 'Springfield Food Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < volunteers + staff; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = 'Person ' + String.valueOf(index).leftPad(4, '0'),
                    Title = index < volunteers ? 'Volunteer' : 'Staff',
                    Work_Email__c = 'person' + index + '@example.org'
                )
            );
        }
        insert people;
    }

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    @IsTest
    static void previewCountsTwoHundredAndShowsFiveSetBeforeAndAfter() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        makePeople(200, 30);
        BulkUpdateService.Preview preview;
        Test.startTest();
        System.runAs(maria()) {
            preview = BulkUpdateService.preview(
                query('Volunteer'),
                changes(new List<Map<String, Object>>{ setTitle('Coordinator') })
            );
        }
        Test.stopTest();
        System.Assert.areEqual(200, preview.count, 'Only matching records are counted');
        System.Assert.areEqual(BulkUpdateService.MAX_RUN_LIMIT, preview.runLimit, 'The default');
        System.Assert.areEqual(BulkUpdateService.SAMPLE_SIZE, preview.sample.size(), 'Five shown');
        BulkUpdateService.FieldChange shown = preview.sample[0].changes[0];
        System.Assert.areEqual('Volunteer', shown.before, 'The value before');
        System.Assert.areEqual('Coordinator', shown.after, 'The value after');
        System.Assert.areEqual(
            [SELECT COUNT() FROM Contact WHERE Title = 'Volunteer'],
            200,
            'A preview saves nothing'
        );
    }

    @IsTest
    static void previewShowsClearAndCopyOverTwoHundred() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        makePeople(200, 0);
        BulkUpdateService.Preview preview;
        System.runAs(maria()) {
            preview = BulkUpdateService.preview(
                query('Volunteer'),
                changes(
                    new List<Map<String, Object>>{
                        new Map<String, Object>{ 'field' => 'Title', 'action' => 'clear' },
                        new Map<String, Object>{
                            'field' => 'Personal_Email__c',
                            'action' => 'copy',
                            'source' => 'Work_Email__c'
                        }
                    }
                )
            );
        }
        System.Assert.areEqual(200, preview.count, 'Every match is counted');
        for (BulkUpdateService.SampleRecord sample : preview.sample) {
            System.Assert.isNull(sample.changes[0].after, 'Clear empties the field');
            System.Assert.isNull(sample.changes[1].before, 'No personal email yet');
            System.Assert.isTrue(
                String.valueOf(sample.changes[1].after).endsWith('@example.org'),
                'Copy takes the record\'s own work email'
            );
        }
    }

    @IsTest
    static void refusesMoreRecordsThanTheRunLimit() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Bulk_Update_Run_Limit__c = 150;
        TestDataFactory.saveSettings(settings);
        makePeople(200, 0);
        System.runAs(maria()) {
            try {
                BulkUpdateService.preview(
                    query('Volunteer'),
                    changes(new List<Map<String, Object>>{ setTitle('Coordinator') })
                );
                System.Assert.fail('200 records are more than the run limit of 150');
            } catch (BulkUpdateFields.BulkUpdateException refused) {
                System.Assert.areEqual(
                    BulkUpdateService.overLimit(150),
                    refused.getMessage(),
                    'The refusal names the limit'
                );
            }
        }
    }

    @IsTest
    static void refusesAQueryThatMatchesNothing() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        makePeople(5, 0);
        System.runAs(maria()) {
            try {
                BulkUpdateService.preview(
                    query('Astronaut'),
                    changes(new List<Map<String, Object>>{ setTitle('Coordinator') })
                );
                System.Assert.fail('Nothing matches');
            } catch (BulkUpdateFields.BulkUpdateException refused) {
                System.Assert.areEqual(
                    System.Label.Core_BulkUpdate_ErrorNothingMatches,
                    refused.getMessage(),
                    'The refusal says nothing matches'
                );
            }
        }
    }

    @IsTest
    static void refusesChangesThatCannotBeMade() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        Map<String, List<Map<String, Object>>> cases = new Map<String, List<Map<String, Object>>>{
            'none' => new List<Map<String, Object>>(),
            'six' => new List<Map<String, Object>>{
                setTitle('a'),
                setTitle('b'),
                setTitle('c'),
                setTitle('d'),
                setTitle('e'),
                setTitle('f')
            },
            'twice' => new List<Map<String, Object>>{ setTitle('a'), setTitle('b') },
            'required' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'field' => 'LastName', 'action' => 'clear' }
            },
            'incompatible' => new List<Map<String, Object>>{
                new Map<String, Object>{
                    'field' => 'Personal_Email__c',
                    'action' => 'copy',
                    'source' => 'Deceased__c'
                }
            },
            'unknown action' => new List<Map<String, Object>>{
                new Map<String, Object>{ 'field' => 'Title', 'action' => 'delete' }
            }
        };
        System.runAs(maria()) {
            for (String name : cases.keySet()) {
                try {
                    BulkUpdateService.plan(query('Volunteer'), changes(cases.get(name)));
                    System.Assert.fail('Refused: ' + name);
                } catch (BulkUpdateFields.BulkUpdateException refused) {
                    System.Assert.isTrue(String.isNotBlank(refused.getMessage()), name);
                }
            }
        }
    }

    @IsTest
    static void aJobsDefinitionHoldsTheQueryTheChangesAndTheCount() {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        System.runAs(maria()) {
            BulkUpdateService.Plan checked = BulkUpdateService.plan(
                query('Volunteer'),
                changes(
                    new List<Map<String, Object>>{
                        setTitle('Coordinator'),
                        new Map<String, Object>{
                            'field' => 'Personal_Email__c',
                            'action' => 'copy',
                            'source' => 'Work_Email__c'
                        }
                    }
                )
            );
            String definition = checked.definition(200);
            BulkUpdateService.Plan again = BulkUpdateService.planFromDefinition(definition);
            System.Assert.areEqual(200, BulkUpdateService.confirmedCountOf(definition), 'Count');
            System.Assert.areEqual('Contact', again.objectName, 'The object');
            System.Assert.areEqual(2, again.changes.size(), 'Both changes');
            System.Assert.areEqual('Coordinator', again.changes[0].value, 'The value to set');
            System.Assert.areEqual(
                'Work_Email__c',
                again.changes[1].source.getName(),
                'The copied field'
            );
        }
    }
}
