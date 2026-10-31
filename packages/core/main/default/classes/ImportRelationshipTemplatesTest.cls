/**
 * The shipped Relationships and Affiliations import templates (C-49f1, D-136): they are added
 * like the other shipped templates, and a 50 row file loaded through each behaves under bulk:
 * reciprocal relationships are created once, repeats are rejected without new records, and a
 * person keeps exactly one primary affiliation.
 */
@IsTest(testFor='ApexClass:ImportTemplateService')
private class ImportRelationshipTemplatesTest {
    private static final Integer ROWS = 50;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < ROWS; i++) {
                people.add(
                    new Contact(
                        FirstName = 'Pat',
                        LastName = 'Rel' + i,
                        Email = 'pat' + i + '@rel.example.org'
                    )
                );
                people.add(
                    new Contact(
                        FirstName = 'Quinn',
                        LastName = 'Rel' + i,
                        Email = 'quinn' + i + '@rel.example.org'
                    )
                );
            }
            insert people;
            List<Account> organizations = new List<Account>();
            for (Integer i = 0; i < 5; i++) {
                organizations.add(
                    new Account(
                        Name = 'Rel Org ' + i,
                        RecordTypeId = AccountKindsTestData.organizationRecordTypeId()
                    )
                );
            }
            insert organizations;
        }
    }

    private static Import_Template__c shipped(String key) {
        ImportTemplateService.materializeDefaults();
        Import_Template__c found = [
            SELECT Id
            FROM Import_Template__c
            WHERE Template_Key__c = :key
            WITH SYSTEM_MODE
        ];
        return ImportTemplateSelector.selectById(found.Id);
    }

    private static ImportRowProcessor.Outcome load(
        Import_Template__c template,
        List<Map<String, String>> values
    ) {
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
        ImportBatchService.beginPass(batch.Id);
        return ImportRowProcessor.process(
            ImportBatchSelector.selectById(batch.Id),
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            false
        );
    }

    private static List<Map<String, String>> parentRows() {
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < ROWS; i++) {
            values.add(
                new Map<String, String>{
                    'Person Email' => 'pat' +
                    i +
                    '@rel.example.org',
                    'Related Person Email' => 'quinn' +
                    i +
                    '@rel.example.org',
                    'Relationship Type' => 'Parent',
                    'Start Date' => '2026-01-15'
                }
            );
        }
        return values;
    }

    @IsTest
    static void bothTemplatesAreAddedAsOneObjectTemplates() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Import_Template__c relationships = shipped('relationships');
            Import_Template__c affiliations = shipped('affiliations');
            Test.stopTest();

            Assert.areEqual('Relationships', relationships.Name);
            Assert.areEqual('Relationship__c', relationships.Target_Object__c);
            Assert.areEqual(ImportObjectSchema.OPERATION_INSERT, relationships.Load_Operation__c);
            Assert.areEqual('Affiliations', affiliations.Name);
            Assert.areEqual('Affiliation__c', affiliations.Target_Object__c);
            Assert.areEqual(ImportObjectSchema.OPERATION_INSERT, affiliations.Load_Operation__c);
            Assert.isTrue(relationships.Active__c && affiliations.Active__c, 'Both are active.');
        }
    }

    @IsTest
    static void fiftyRelationshipsCreateEachReciprocalOnceAndRepeatsAreRejected() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = shipped('relationships');

            Test.startTest();
            ImportRowProcessor.Outcome first = load(template, parentRows());
            Integer afterFirst = [SELECT COUNT() FROM Relationship__c];
            ImportRowProcessor.Outcome again = load(template, parentRows());
            Test.stopTest();

            Assert.areEqual(ROWS, first.created, 'Every row creates: ' + first.notes);
            Assert.areEqual(2 * ROWS, afterFirst, 'Each row and its reciprocal, once.');
            Assert.areEqual(
                ROWS,
                [
                    SELECT COUNT()
                    FROM Relationship__c
                    WHERE Type__c = 'Child' AND Reciprocal_Relationship__c != NULL
                ],
                'Every Child side is linked to its Parent side.'
            );
            Assert.areEqual(0, again.created, 'A second load creates nothing.');
            Assert.areEqual(ROWS, again.rejected, 'Every repeat is rejected.');
            Assert.areEqual(afterFirst, [SELECT COUNT() FROM Relationship__c], 'No new records.');
        }
    }

    @IsTest
    static void aPersonKeepsOnePrimaryAffiliationWhenSeveralRowsSayPrimary() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = shipped('affiliations');
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < ROWS / 2; i++) {
                String email = 'pat' + i + '@rel.example.org';
                values.add(
                    new Map<String, String>{
                        'Person Email' => email,
                        'Organization Name' => 'Rel Org ' + Math.mod(i, 5),
                        'Role' => 'Board',
                        'Is Primary' => 'true',
                        'Start Date' => '2026-01-01'
                    }
                );
                values.add(
                    new Map<String, String>{
                        'Person Email' => email,
                        'Organization Name' => 'Rel Org ' + Math.mod(i + 1, 5),
                        'Role' => 'Volunteer',
                        'Is Primary' => 'true',
                        'Start Date' => '2026-02-01'
                    }
                );
            }

            Test.startTest();
            ImportRowProcessor.Outcome outcome = load(template, values);
            Test.stopTest();

            Assert.areEqual(ROWS, outcome.created, 'Every row creates: ' + outcome.notes);
            Assert.areEqual(
                ROWS / 2,
                [SELECT COUNT() FROM Affiliation__c WHERE Is_Primary__c = TRUE],
                'One primary for each person.'
            );
            for (Contact person : [
                SELECT
                    Id,
                    Primary_Affiliation__c,
                    (SELECT Organization__c FROM Affiliations__r WHERE Is_Primary__c = TRUE)
                FROM Contact
                WHERE
                    Email LIKE 'pat%@rel.example.org'
                    AND Id IN (SELECT Contact__c FROM Affiliation__c)
            ]) {
                Assert.areEqual(1, person.Affiliations__r.size(), 'Exactly one primary.');
                Assert.areEqual(
                    person.Affiliations__r[0].Organization__c,
                    person.Primary_Affiliation__c,
                    'The person names the primary organization.'
                );
            }
        }
    }
}
