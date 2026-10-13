/**
 * Changing values with steps in a bulk update (C-37, canonical model R-BU7): the DataTransform
 * engine applied to each record's own value, other fields of the same record added, the result
 * typed for the field, and a result the field cannot take refused for that record alone.
 *
 * No org has run these yet; they are written against the behaviour the classes document.
 */
@IsTest
private class BulkUpdateTransformTest {
    private static final String VOLUNTEERS = JSON.serialize(
        new Map<String, Object>{
            'version' => 1,
            'object' => 'Contact',
            'fields' => new List<Object>{ 'LastName' },
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
            }
        }
    );

    /** One change with steps on `field`. */
    private static String transform(String field, List<Map<String, Object>> steps) {
        return JSON.serialize(
            new List<Object>{
                new Map<String, Object>{
                    'field' => field,
                    'action' => BulkUpdateService.ACTION_TRANSFORM,
                    'transforms' => steps
                }
            }
        );
    }

    private static Map<String, Object> step(String op) {
        return new Map<String, Object>{ 'op' => op };
    }

    private static Map<String, Object> replace(String text, String replaceWith) {
        return new Map<String, Object>{
            'op' => DataTransform.OP_REPLACE,
            'text' => text,
            'replaceWith' => replaceWith
        };
    }

    private static Map<String, Object> append(List<String> fields, String separator) {
        return new Map<String, Object>{
            'op' => DataTransform.OP_APPEND,
            'columns' => fields,
            'separator' => separator
        };
    }

    /** `count` contacts titled Volunteer, each with its own last name. */
    private static List<Contact> makeVolunteers(Integer count) {
        DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
        Account organization = new Account(Name = 'Springfield Food Bank');
        insert organization;
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < count; index++) {
            people.add(
                new Contact(
                    AccountId = organization.Id,
                    LastName = 'Person ' + String.valueOf(index).leftPad(4, '0'),
                    Title = 'Volunteer'
                )
            );
        }
        insert people;
        return people;
    }

    private static Import_Batch__c run(String changesJson, Integer confirmed) {
        Import_Batch__c job;
        Test.startTest();
        job = BulkUpdateService.start(VOLUNTEERS, changesJson, confirmed);
        Test.stopTest();
        return [
            SELECT Status__c, Rows_Updated__c, Rows_Matched__c, Rows_Rejected__c, Run_Log__c
            FROM Import_Batch__c
            WHERE Id = :job.Id
        ];
    }

    private static List<Map<String, Object>> journal(Id jobId) {
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :jobId AND Phase__c = :ImportJournalService.PHASE_COMMIT
        ]) {
            entries.addAll(ImportJournalService.entries(page));
        }
        return entries;
    }

    @IsTest
    static void stepsChangeEachOfTwoHundredRecordsWithItsOwnFields() {
        System.runAs(TestUsers.admin()) {
            makeVolunteers(200);
            Import_Batch__c job = run(
                transform(
                    'Title',
                    new List<Map<String, Object>>{
                        replace('Volunteer', 'Coordinator'),
                        append(new List<String>{ 'LastName' }, ': ')
                    }
                ),
                200
            );

            System.Assert.areEqual(
                ImportBatchService.STATUS_COMPLETE,
                job.Status__c,
                job.Run_Log__c
            );
            System.Assert.areEqual(200, job.Rows_Updated__c, 'Every record is changed');
            for (Contact person : [SELECT LastName, Title FROM Contact]) {
                System.Assert.areEqual(
                    'Coordinator: ' + person.LastName,
                    person.Title,
                    'Its own name'
                );
            }
            List<Map<String, Object>> entries = journal(job.Id);
            System.Assert.areEqual(200, entries.size(), 'One entry per record saved');
            Map<String, Object> title = (Map<String, Object>) ((Map<String, Object>) entries[0]
                    .get('fields'))
                .get('Title');
            System.Assert.areEqual('Volunteer', title.get('before'), 'The value before');
        }
    }

    @IsTest
    static void newerStepsChangeTwoHundredRecords() {
        System.runAs(TestUsers.admin()) {
            makeVolunteers(200);
            Map<String, Object> mapValues = step(DataTransform.OP_MAP);
            mapValues.put(
                'pairs',
                new List<Object>{
                    new Map<String, Object>{ 'text' => 'volunteer', 'value' => 'Helper, Events' }
                }
            );
            Map<String, Object> keepPart = step(DataTransform.OP_PART);
            keepPart.putAll(new Map<String, Object>{ 'separator' => ',', 'position' => 2 });
            Map<String, Object> ifThen = step(DataTransform.OP_IF_THEN);
            ifThen.putAll(
                new Map<String, Object>{
                    'test' => 'equals',
                    'text' => 'events',
                    'value' => 'Event lead'
                }
            );
            Import_Batch__c job = run(
                transform('Title', new List<Map<String, Object>>{ mapValues, keepPart, ifThen }),
                200
            );

            System.Assert.areEqual(
                ImportBatchService.STATUS_COMPLETE,
                job.Status__c,
                job.Run_Log__c
            );
            System.Assert.areEqual(200, job.Rows_Updated__c, 'Every record is changed');
            System.Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE Title = 'Event lead'],
                'Mapped, split and tested in order'
            );
        }
    }

    @IsTest
    static void aChangeOnlyInCapitalsIsStillWritten() {
        System.runAs(TestUsers.admin()) {
            makeVolunteers(200);
            Import_Batch__c job = run(
                transform('Title', new List<Map<String, Object>>{ step(DataTransform.OP_UPPER) }),
                200
            );

            System.Assert.areEqual(200, job.Rows_Updated__c, 'Compared exactly, not with ==');
            System.Assert.areEqual(0, job.Rows_Matched__c, 'None reads as unchanged');
            System.Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE Title = 'VOLUNTEER'],
                'Saved'
            );
        }
    }

    @IsTest
    static void aResultTheFieldCannotTakeFailsThatRecordOnly() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = makeVolunteers(200);
            Contact tooLong = people[7];
            update new Contact(Id = tooLong.Id, Description = 'x'.repeat(200));
            Import_Batch__c job = run(
                transform(
                    'Title',
                    new List<Map<String, Object>>{ append(new List<String>{ 'Description' }, ' ') }
                ),
                200
            );

            System.Assert.areEqual(1, job.Rows_Rejected__c, job.Run_Log__c);
            System.Assert.areEqual(0, job.Rows_Updated__c, 'An empty Description adds nothing');
            System.Assert.areEqual(199, job.Rows_Matched__c, 'The rest hold their value');
            System.Assert.areEqual(
                'Volunteer',
                [SELECT Title FROM Contact WHERE Id = :tooLong.Id].Title,
                'Never shortened'
            );
            List<Map<String, Object>> entries = journal(job.Id);
            System.Assert.areEqual(1, entries.size(), 'Only the refusal is journaled');
            System.Assert.areEqual(ImportJournalService.ACTION_FAILED, entries[0].get('action'));
            System.Assert.areEqual(String.valueOf(tooLong.Id), entries[0].get('id'));
        }
    }

    @IsTest
    static void previewShowsEachRecordsResultAndWhyOneCannotBeSaved() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = makeVolunteers(5);
            update new Contact(Id = people[0].Id, Description = 'x'.repeat(200));
            BulkUpdateService.Preview preview = BulkUpdateService.preview(
                VOLUNTEERS,
                transform(
                    'Title',
                    new List<Map<String, Object>>{
                        append(new List<String>{ 'LastName', 'Description' }, ' ')
                    }
                )
            );

            System.Assert.areEqual(5, preview.count, 'Counted');
            Integer refused = 0;
            for (BulkUpdateService.SampleRecord shown : preview.sample) {
                BulkUpdateService.FieldChange title = shown.changes[0];
                if (title.problem != null) {
                    refused++;
                    System.Assert.isNull(title.after, 'No result shown for a refusal');
                } else {
                    System.Assert.areEqual('Volunteer ' + shown.name, title.after, 'Own name');
                }
            }
            System.Assert.areEqual(1, refused, 'The record whose result is too long');
        }
    }

    @IsTest
    static void stepsAreRefusedWhenEmptyInvalidOnALookupOrNamingAnUnknownField() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            List<String> refused = new List<String>{
                transform('Title', new List<Map<String, Object>>()),
                transform('Title', new List<Map<String, Object>>{ step(DataTransform.OP_REPLACE) }),
                transform('Title', new List<Map<String, Object>>{ step('evaluate') }),
                transform(
                    'AccountId',
                    new List<Map<String, Object>>{ step(DataTransform.OP_TRIM) }
                ),
                transform(
                    'Title',
                    new List<Map<String, Object>>{
                        append(new List<String>{ 'No_Such_Field__c' }, ' ')
                    }
                )
            };
            for (String changesJson : refused) {
                try {
                    BulkUpdateService.plan(VOLUNTEERS, changesJson);
                    System.Assert.fail('Refused: ' + changesJson);
                } catch (BulkUpdateFields.BulkUpdateException expected) {
                    System.Assert.isTrue(String.isNotBlank(expected.getMessage()), changesJson);
                }
            }
        }
    }

    @IsTest
    static void aJobsDefinitionKeepsTheStepsAndTheFieldsTheyRead() {
        System.runAs(TestUsers.admin()) {
            DataProtectedFields.definitionsOverride = new List<Rollup_Definition__c>();
            BulkUpdateService.Plan checked = BulkUpdateService.plan(
                VOLUNTEERS,
                transform(
                    'Title',
                    new List<Map<String, Object>>{
                        replace('St.', 'Street'),
                        append(new List<String>{ 'lastname' }, ' ')
                    }
                )
            );
            BulkUpdateService.Plan again = BulkUpdateService.planFromDefinition(
                checked.definition(10)
            );

            BulkUpdateService.Change change = again.changes[0];
            System.Assert.areEqual(BulkUpdateService.ACTION_TRANSFORM, change.action);
            System.Assert.areEqual(2, change.steps.size(), 'Both steps');
            System.Assert.areEqual('Street', change.steps[0].replaceWith, 'Kept as stored');
            System.Assert.isTrue(again.readFields().contains('LastName'), 'Read with the record');
        }
    }

    @IsTest
    static void aResultIsTypedForItsFieldAsAnImportReadsIt() {
        System.runAs(TestUsers.admin()) {
            Map<String, Schema.SObjectField> account = Schema.SObjectType.Account.fields.getMap();
            Map<String, Schema.SObjectField> contact = Schema.SObjectType.Contact.fields.getMap();
            Schema.DescribeFieldResult employees = account.get('NumberOfEmployees').getDescribe();
            Schema.DescribeFieldResult revenue = account.get('AnnualRevenue').getDescribe();
            Schema.DescribeFieldResult birthdate = contact.get('Birthdate').getDescribe();
            Schema.DescribeFieldResult optOut = contact.get('HasOptedOutOfEmail').getDescribe();
            Schema.DescribeFieldResult lastName = contact.get('LastName').getDescribe();

            System.Assert.areEqual(1250, BulkUpdateFields.fromText(employees, '1,250'));
            System.Assert.isTrue(
                (Decimal) BulkUpdateFields.fromText(revenue, '$1,250.50') == 1250.5,
                'Symbols and separators are dropped'
            );
            System.Assert.areEqual(
                Date.newInstance(2025, 12, 31),
                BulkUpdateFields.fromText(birthdate, '2025-12-31')
            );
            System.Assert.areEqual(true, BulkUpdateFields.fromText(optOut, 'Yes'));
            System.Assert.areEqual(false, BulkUpdateFields.fromText(optOut, ''));
            System.Assert.isNull(BulkUpdateFields.fromText(birthdate, ' '), 'Blank clears');
            for (
                List<Object> refused : new List<List<Object>>{
                    new List<Object>{ birthdate, '31/12/2025' },
                    new List<Object>{ employees, 'many' },
                    new List<Object>{ lastName, '' }
                }
            ) {
                try {
                    BulkUpdateFields.fromText(
                        (Schema.DescribeFieldResult) refused[0],
                        (String) refused[1]
                    );
                    System.Assert.fail('Refused: ' + refused[1]);
                } catch (BulkUpdateFields.BulkUpdateException expected) {
                    System.Assert.isTrue(String.isNotBlank(expected.getMessage()));
                }
            }
        }
    }
}
