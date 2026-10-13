/**
 * C-32 values for every row of a file (R-IB14) and the matching choices the wizard sends
 * (R-IT2, R-IT8, R-IT9): a file value fills only a row's blanks, beats the template's default,
 * cannot make every row one person, and the wizard's choices are saved on the template.
 */
@IsTest(testFor='ApexClass:ImportMapping, ApexClass:ImportController')
private class ImportFileValuesTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static Import_Template__c template() {
        ImportMapping mapping = new ImportMapping();
        for (
            String target : new List<String>{
                'Contact1.FirstName',
                'Contact1.LastName',
                'Contact1.MailingCity'
            }
        ) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        return ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    private static Map<String, String> person(String firstName, String city) {
        return new Map<String, String>{
            'Contact1.FirstName' => firstName,
            'Contact1.LastName' => 'Rivera',
            'Contact1.MailingCity' => city
        };
    }

    /** Runs one pass the way the platform drives the batch, in chunks of 200. */
    private static Import_Batch__c run(Id batchId, Boolean dryRun) {
        ImportBatchService.beginPass(batchId);
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun);
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            chunk.add((Import_Row__c) rows.next());
            if (chunk.size() == 200 || !rows.hasNext()) {
                job.execute(null, chunk);
                chunk = new List<Import_Row__c>();
            }
        }
        job.finish(null);
        return ImportBatchSelector.selectById(batchId);
    }

    private static String cityOf(Id contactId) {
        return [SELECT MailingCity FROM Contact WHERE Id = :contactId].MailingCity;
    }

    @IsTest
    static void aFileValueComesBeforeTheTemplateDefaultForTheSameTarget() {
        System.runAs(TestUsers.admin()) {
            ImportMapping mapping = new ImportMapping();
            mapping.defaults.add(new ImportMapping.Assignment('Contact1.MailingCity', 'Eugene'));
            mapping.defaults.add(new ImportMapping.Assignment('Household.Name', 'Kept'));

            mapping.withFileValues(
                '{"version":1,"defaults":[{"target":"contact1.mailingcity","value":"Portland"}]}'
            );

            Assert.areEqual(
                2,
                mapping.defaults.size(),
                'The default for the same target is replaced.'
            );
            Assert.areEqual('Portland', mapping.defaults[0].value, 'The file value comes first.');
            Assert.areEqual('Kept', mapping.defaults[1].value, 'Other defaults stay.');
            Assert.areEqual(
                2,
                mapping.withFileValues(null).defaults.size(),
                'No file values change nothing.'
            );
        }
    }

    @IsTest
    static void twoHundredRowsTakeTheFileValueOnlyWhereBlank() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template();
            template.Default_Values_JSON__c = '{"version":1,"defaults":[{"target":"Contact1.MailingCity","value":"Eugene"}]}';
            update template;
            Import_Batch__c batch = ImportBatchService.create(
                template.Id,
                null,
                'cities.csv',
                null,
                null,
                new List<ImportMapping.Assignment>{
                    new ImportMapping.Assignment('Contact1.MailingCity', 'Portland'),
                    new ImportMapping.Assignment('Contact1.Phone', '  ')
                },
                false
            );
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                values.add(person('Ana' + i, Math.mod(i, 2) == 0 ? 'Salem' : ''));
            }
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            Import_Batch__c dryRun = run(batch.Id, true);
            Import_Batch__c committed = run(batch.Id, false);
            Test.stopTest();

            Assert.areEqual(200, dryRun.Rows_Created__c, 'The dry run counts every row.');
            Assert.areEqual(200, committed.Rows_Created__c, 'And the commit creates them.');
            List<Import_Row__c> rows = ImportTestDataFactory.reload(batch.Id);
            Assert.areEqual(
                'Salem',
                cityOf(rows[0].Contact_1__c),
                'A row with its own value keeps it.'
            );
            Assert.areEqual(
                'Portland',
                cityOf(rows[1].Contact_1__c),
                'A blank takes the file value, not the template default.'
            );
            Assert.areEqual(
                100,
                [SELECT COUNT() FROM Contact WHERE MailingCity = 'Portland'],
                'Every blank row, and only those.'
            );
            Import_Batch__c stored = ImportBatchSelector.selectById(batch.Id);
            Assert.isFalse(
                stored.File_Values_JSON__c.contains('Phone'),
                'A blank value is not kept.'
            );
        }
    }

    @IsTest
    static void aFileValueNamingAPersonIsRefused() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = template();
            for (
                String target : new List<String>{
                    'Contact1.LastName',
                    'Contact2.Email',
                    'Contact1.FullName'
                }
            ) {
                Boolean refused = false;
                try {
                    ImportBatchService.create(
                        template.Id,
                        null,
                        'one-person.csv',
                        null,
                        null,
                        new List<ImportMapping.Assignment>{
                            new ImportMapping.Assignment(target, 'x')
                        },
                        false
                    );
                } catch (ImportException e) {
                    refused = e.getMessage().contains(target);
                }
                Assert.isTrue(
                    refused,
                    'Every row would be one person, so it is refused: ' + target
                );
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Import_Batch__c], 'No batch is made.');
            Assert.isFalse(
                ImportMapping.namesAPerson('Organization.Name', null),
                'An organization may be given to every row.'
            );
            Assert.isTrue(
                ImportMapping.namesAPerson('Contact1.Member_Id__c', 'member_id__c'),
                'Nor may the field people are matched on.'
            );
        }
    }

    @IsTest
    static void theWizardSavesItsMatchingChoicesAndFileValues() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Import_Template__c template = template();
            Map<String, Object> options = new Map<String, Object>{
                'matching' => new Map<String, Object>{
                    'organizationRule' => ImportTemplateService.ORGANIZATION_RULE_NAME,
                    'severalMatches' => ImportTemplateService.SEVERAL_MOST_RECENT
                },
                'fileValues' => new List<Object>{
                    new Map<String, String>{ 'target' => 'Contact1.MailingCity', 'value' => 'Bend' }
                }
            };

            Test.startTest();
            ImportController.BatchView view = ImportController.createBatch(
                template.Id,
                null,
                'people.csv',
                template.Column_Mapping_JSON__c,
                ImportTemplateService.RULE_NAME_POSTAL,
                JSON.serialize(options)
            );
            Test.stopTest();

            Import_Template__c saved = ImportTemplateSelector.selectById(template.Id);
            Assert.areEqual(
                ImportTemplateService.RULE_NAME_POSTAL,
                saved.Matching_Rule__c,
                'The person rule.'
            );
            Assert.areEqual(
                ImportTemplateService.SEVERAL_MOST_RECENT,
                saved.Several_Matches__c,
                'The several-matches choice.'
            );
            Import_Batch__c batch = ImportBatchSelector.selectById(view.id);
            Assert.isTrue(
                batch.File_Values_JSON__c.contains('Bend'),
                'The file values, on the batch.'
            );
            Assert.isFalse(
                String.valueOf(saved.Default_Values_JSON__c).contains('Bend'),
                'And not on the template.'
            );
        }
    }

    @IsTest
    static void theWizardIsOfferedOnlyMatchableFields() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            Test.startTest();
            ImportController.MatchFieldsView view = ImportController.getMatchFields();
            Test.stopTest();
            for (ImportController.MatchFieldView field : view.contact) {
                Assert.areEqual(
                    field.value,
                    ImportMatcher.matchField(Contact.SObjectType, field.value),
                    'Each contact field offered is one matching accepts.'
                );
            }
            for (ImportController.MatchFieldView field : view.account) {
                Assert.isNotNull(
                    ImportMatcher.matchField(Account.SObjectType, field.value),
                    'And each account field.'
                );
            }
            Assert.isNull(
                ImportMatcher.matchField(Contact.SObjectType, 'Email'),
                'Email is neither External ID nor Unique.'
            );
        }
    }
}
