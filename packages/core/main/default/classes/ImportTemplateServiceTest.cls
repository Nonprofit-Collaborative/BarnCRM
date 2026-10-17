/**
 * Templates: the shipped ones are materialized once and never overwritten (R-IT4), the
 * matching rule is always one the picklist accepts, and a mapping that identifies nobody is
 * refused before it can be saved.
 */
@IsTest(testFor='ApexClass:ImportTemplateService')
private class ImportTemplateServiceTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    @IsTest
    static void materializesEveryShippedTemplateOnce() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Integer firstRun = ImportTemplateService.materializeDefaults();
            Integer secondRun = ImportTemplateService.materializeDefaults();
            Test.stopTest();

            Assert.isTrue(firstRun > 0, 'The package ships at least one template.');
            Assert.areEqual(0, secondRun, 'A second run creates nothing: the keys already exist.');
            List<Import_Template__c> templates = [
                SELECT Id, Template_Key__c, Is_Package_Default__c
                FROM Import_Template__c
            ];
            Assert.areEqual(firstRun, templates.size(), 'One record per shipped template.');
            for (Import_Template__c template : templates) {
                Assert.isTrue(
                    template.Is_Package_Default__c,
                    'Each is marked as a shipped default.'
                );
            }
        }
    }

    @IsTest
    static void neverOverwritesAnEditedTemplate() {
        System.runAs(TestUsers.admin()) {
            ImportTemplateService.materializeDefaults();
            Import_Template__c template = [
                SELECT Id, Name, Column_Mapping_JSON__c
                FROM Import_Template__c
                LIMIT 1
            ];
            template.Name = 'Maria renamed this';
            template.Column_Mapping_JSON__c = ImportTestDataFactory.donorMapping();
            update template;

            Test.startTest();
            ImportTemplateService.materializeDefaults();
            Test.stopTest();

            Import_Template__c after = [
                SELECT Name, Column_Mapping_JSON__c
                FROM Import_Template__c
                WHERE Id = :template.Id
            ];
            Assert.areEqual('Maria renamed this', after.Name, 'The administrator edit survives.');
            Assert.areEqual(
                ImportTestDataFactory.donorMapping(),
                after.Column_Mapping_JSON__c,
                'So does the mapping they corrected.'
            );
        }
    }

    @IsTest
    static void listingTemplatesMaterializesTheShippedOnesOnFirstUse() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<Import_Template__c> templates = ImportTemplateService.listActive();
            Test.stopTest();
            Assert.isFalse(
                templates.isEmpty(),
                'An org that has never imported still sees the shipped mappings.'
            );
        }
    }

    @IsTest
    static void savesAMappingBackToItsTemplate() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            ImportMapping changed = ImportMapping.parse(ImportTestDataFactory.donorMapping());
            changed.columns.add(new ImportMapping.Column('Phone', 'Contact1.Phone'));

            Test.startTest();
            ImportTemplateService.saveMapping(
                template.Id,
                changed.serialize(),
                ImportTemplateService.RULE_NAME_POSTAL
            );
            Test.stopTest();

            Import_Template__c after = [
                SELECT Column_Mapping_JSON__c, Matching_Rule__c
                FROM Import_Template__c
                WHERE Id = :template.Id
            ];
            Assert.areEqual(
                ImportTemplateService.RULE_NAME_POSTAL,
                after.Matching_Rule__c,
                'The rule the administrator chose is stored.'
            );
            Assert.isTrue(
                after.Column_Mapping_JSON__c.contains('Contact1.Phone'),
                'And so is the column they added.'
            );
        }
    }

    @IsTest
    static void refusesAMappingThatIdentifiesNobody() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            ImportMapping useless = new ImportMapping();
            useless.columns.add(new ImportMapping.Column('City', 'Contact1.MailingCity'));

            Test.startTest();
            try {
                ImportTemplateService.saveMapping(
                    template.Id,
                    useless.serialize(),
                    ImportTemplateService.RULE_EMAIL
                );
                Assert.fail('A mapping that identifies nobody must be refused.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorMappingIdentifiesNobody,
                    e.getMessage(),
                    'And refused with the message the admin guide quotes.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void refusesToSaveAgainstATemplateThatIsGone() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Id templateId = template.Id;
            delete template;

            Test.startTest();
            try {
                ImportTemplateService.saveMapping(
                    templateId,
                    ImportTestDataFactory.donorMapping(),
                    ImportTemplateService.RULE_EMAIL
                );
                Assert.fail('A deleted template cannot be saved to.');
            } catch (ImportException e) {
                Assert.areEqual(
                    Label.Core_Import_ErrorTemplateGone,
                    e.getMessage(),
                    'Said plainly.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void normalizesTheMatchingRule() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                ImportTemplateService.RULE_EMAIL,
                ImportTemplateService.normalizedRule('email EXACT'),
                'Capitalization and spacing do not matter.'
            );
            Assert.areEqual(
                ImportTemplateService.RULE_EMAIL,
                ImportTemplateService.normalizedRule('something else'),
                'An unrecognized rule falls back to the safe one rather than failing a save.'
            );
            Assert.areEqual(
                ImportTemplateService.RULE_EXTERNAL_ID,
                ImportTemplateService.normalizedRule(ImportTemplateService.RULE_EXTERNAL_ID),
                'A real rule is kept.'
            );
        }
    }

    @IsTest
    static void recordsWhenATemplateWasLastUsed() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Test.startTest();
            ImportTemplateService.recordImport(template.Id, Date.today());
            Test.stopTest();
            Assert.areEqual(
                Date.today(),
                [SELECT Last_Import_Date__c FROM Import_Template__c WHERE Id = :template.Id]
                .Last_Import_Date__c,
                'The Hub can say how long it is since this feed was loaded.'
            );
        }
    }

    @IsTest
    static void personModeFollowsTheOrgShape() {
        System.runAs(TestUsers.admin()) {
            // Asked of the org this test runs in, so that it holds on a Platform-only org and on
            // one with person accounts alike (ADR-0013).
            if (OrgShapeDetector.detect().hasPersonAccounts) {
                Assert.areEqual(
                    ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS,
                    ImportTemplateService.defaultPersonMode(),
                    'An org with person accounts stores people as accounts.'
                );
            } else {
                Assert.areEqual(
                    ImportTemplateService.PERSON_MODE_CONTACTS,
                    ImportTemplateService.defaultPersonMode(),
                    'A platform-only org stores people as contacts.'
                );
            }
        }
    }

    private static Import_Template__c recurring(String sourceName, Date lastImport) {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        ImportTemplateService.saveRecurring(template.Id, true, sourceName);
        if (lastImport != null) {
            ImportTemplateService.recordImport(template.Id, lastImport);
        }
        return template;
    }

    @IsTest
    static void aRecurringTemplateNeedsItsSourceNamed() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            try {
                ImportTemplateService.saveRecurring(template.Id, true, '  ');
                Assert.fail('A recurring file with no name cannot be told apart on the Hub.');
            } catch (ImportException expected) {
                Assert.areEqual(
                    Label.Core_Import_ErrorSourceNameRequired,
                    expected.getMessage(),
                    'Saying so.'
                );
            }
            ImportTemplateService.saveRecurring(template.Id, true, ' Monthly processor export ');
            ImportTemplateService.saveRecurring(template.Id, false, null);
            Import_Template__c saved = [
                SELECT Is_Recurring__c, Source_Name__c
                FROM Import_Template__c
                WHERE Id = :template.Id
            ];
            Assert.isFalse(saved.Is_Recurring__c, 'The mark can be taken off.');
            Assert.areEqual('Monthly processor export', saved.Source_Name__c, 'The name is kept.');
        }
    }

    @IsTest
    static void recurringSourcesListTheOneLoadedLongestAgoFirst() {
        System.runAs(TestUsers.admin()) {
            recurring('Monthly processor export', Date.today().addDays(-3));
            recurring('Quarterly partner list', Date.today().addDays(-40));
            recurring('Event sign-ups', null);
            ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );

            List<Import_Template__c> sources = ImportTemplateService.recurringSources();

            Assert.areEqual(3, sources.size(), 'Only templates marked recurring are listed.');
            Assert.areEqual(
                'Event sign-ups',
                sources[0].Source_Name__c,
                'Never loaded comes first.'
            );
            Assert.areEqual(
                'Quarterly partner list',
                sources[1].Source_Name__c,
                'Then the oldest.'
            );
        }
    }

    @IsTest
    static void paymentMatchingIsHeldOnTheTemplateAndCheckedFirst() {
        System.runAs(TestUsers.admin()) {
            Import_Template__c template = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );

            Test.startTest();
            ImportTemplateService.savePaymentMatching(template.Id, 'match only', 3, 0.5);
            Import_Template__c saved = ImportTemplateSelector.selectById(template.Id);
            List<String> refusals = new List<String>();
            for (
                List<Object> attempt : new List<List<Object>>{
                    new List<Object>{ 'Sometimes', null, null },
                    new List<Object>{ null, -1, null },
                    new List<Object>{ null, null, -0.01 }
                }
            ) {
                try {
                    ImportTemplateService.savePaymentMatching(
                        template.Id,
                        (String) attempt[0],
                        (Integer) attempt[1],
                        (Decimal) attempt[2]
                    );
                } catch (ImportException e) {
                    refusals.add(e.getMessage());
                }
            }
            ImportTemplateService.savePaymentMatching(template.Id, null, null, null);
            Test.stopTest();

            Assert.areEqual(
                'Match only',
                saved.Payment_Matching__c,
                'Stored as the picklist spells it.'
            );
            Assert.areEqual(3, saved.Match_Date_Window_Days__c, 'The window.');
            Assert.isTrue(saved.Match_Amount_Tolerance__c == 0.5, 'The tolerance.');
            Assert.areEqual(
                new List<String>{
                    Label.Core_Import_ErrorPaymentMatchingUnknown,
                    Label.Core_Import_ErrorPaymentMatchingRange,
                    Label.Core_Import_ErrorPaymentMatchingRange
                },
                refusals,
                'An unknown behaviour and a negative number are refused.'
            );
            Import_Template__c cleared = ImportTemplateSelector.selectById(template.Id);
            Assert.isNull(cleared.Payment_Matching__c, 'Empty means the default.');
            Assert.isNull(cleared.Match_Date_Window_Days__c, 'And the setting is used.');
        }
    }

    private static final String ONE_OBJECT_MAPPING = '{"version":1,"columns":[{"source":"Context","target":"Record.Context__c"}]}';

    /** An in-memory shipped row loading one object; custom metadata cannot be inserted. */
    private static Import_Template_Default__mdt oneObjectRow(
        String name,
        String objectName,
        String mapping,
        String operation,
        String matchField,
        String personMode
    ) {
        return new Import_Template_Default__mdt(
            DeveloperName = name,
            MasterLabel = name,
            Template_Key__c = 'one_object_key',
            Column_Mapping_JSON__c = mapping,
            Default_Values_JSON__c = '{"version":1,"defaults":[]}',
            Matching_Rule__c = ImportTemplateService.RULE_EMAIL,
            Person_Mode__c = personMode,
            Default_Active__c = true,
            Target_Object__c = objectName,
            Load_Operation__c = operation,
            Load_Match_Field__c = matchField
        );
    }

    private static List<Import_Template__c> templatesWithKey() {
        return [
            SELECT Name, Target_Object__c, Load_Operation__c, Load_Match_Field__c, Person_Mode__c
            FROM Import_Template__c
            WHERE Template_Key__c = 'one_object_key'
        ];
    }

    private static String otherMode() {
        return ImportTemplateService.defaultPersonMode() ==
            ImportTemplateService.PERSON_MODE_CONTACTS
            ? ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS
            : ImportTemplateService.PERSON_MODE_CONTACTS;
    }

    @IsTest
    static void aOneObjectDefaultMaterializesWithItsOperationAndMatchField() {
        System.runAs(TestUsers.admin()) {
            ImportTemplateSelector.shippedOverride = new List<Import_Template_Default__mdt>{
                oneObjectRow(
                    'Load_One',
                    'Error_Log__c',
                    ONE_OBJECT_MAPPING,
                    ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                    'Context__c',
                    null
                )
            };

            Test.startTest();
            Integer created = ImportTemplateService.materializeDefaults();
            Integer again = ImportTemplateService.materializeDefaults();
            Test.stopTest();

            Assert.areEqual(1, created, 'The row becomes one template.');
            Assert.areEqual(0, again, 'And only once.');
            Import_Template__c template = templatesWithKey()[0];
            Assert.areEqual('Error_Log__c', template.Target_Object__c, 'The object is copied.');
            Assert.areEqual(
                ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                template.Load_Operation__c,
                'The operation is copied.'
            );
            Assert.areEqual('Context__c', template.Load_Match_Field__c, 'The match field too.');
            Assert.areEqual(
                ImportTemplateService.defaultPersonMode(),
                template.Person_Mode__c,
                'The people mode is the org\'s.'
            );
        }
    }

    @IsTest
    static void aBlankOperationInsertsAndNeedsNoMatchField() {
        System.runAs(TestUsers.admin()) {
            ImportTemplateSelector.shippedOverride = new List<Import_Template_Default__mdt>{
                oneObjectRow('Load_One', 'Error_Log__c', ONE_OBJECT_MAPPING, null, null, null)
            };

            ImportTemplateService.materializeDefaults();

            Import_Template__c template = templatesWithKey()[0];
            Assert.areEqual(ImportObjectSchema.OPERATION_INSERT, template.Load_Operation__c);
            Assert.isNull(template.Load_Match_Field__c, 'Insert finds nothing.');
        }
    }

    @IsTest
    static void aDefaultNamingAMissingObjectOrFieldIsSkippedAndLogged() {
        System.runAs(TestUsers.admin()) {
            String missingField = '{"version":1,"columns":[{"source":"X","target":"Record.No_Such_Field__c"}]}';
            String missingLookup = '{"version":1,"columns":[{"source":"X","target":"Record.User__c","lookupField":"No_Such_Lookup__c"}]}';
            ImportTemplateSelector.shippedOverride = new List<Import_Template_Default__mdt>{
                oneObjectRow(
                    'No_Object',
                    'No_Such_Object__c',
                    ONE_OBJECT_MAPPING,
                    null,
                    null,
                    null
                ),
                oneObjectRow('No_Field', 'Error_Log__c', missingField, null, null, null),
                oneObjectRow('No_Lookup', 'Error_Log__c', missingLookup, null, null, null),
                oneObjectRow(
                    'No_Match',
                    'Error_Log__c',
                    ONE_OBJECT_MAPPING,
                    ImportObjectSchema.OPERATION_UPSERT,
                    'No_Such_Key__c',
                    null
                ),
                oneObjectRow(
                    'Not_External_Id',
                    'Error_Log__c',
                    ONE_OBJECT_MAPPING,
                    ImportObjectSchema.OPERATION_UPSERT,
                    'Context__c',
                    null
                )
            };

            Test.startTest();
            Integer created = ImportTemplateService.materializeDefaults();
            ImportTemplateService.materializeDefaults();
            Test.stopTest();

            Assert.areEqual(0, created, 'Nothing that cannot run is added.');
            Assert.areEqual(0, templatesWithKey().size());
            Assert.areEqual(
                5,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'ImportTemplateService.oneObjectTemplate'
                ],
                'Each skipped row is logged once per run.'
            );
        }
    }

    @IsTest
    static void onlyTheRowForTheOrgsPeopleModeIsMaterialized() {
        System.runAs(TestUsers.admin()) {
            ImportTemplateSelector.shippedOverride = new List<Import_Template_Default__mdt>{
                oneObjectRow(
                    'Other_Mode',
                    'Error_Log__c',
                    ONE_OBJECT_MAPPING,
                    null,
                    null,
                    otherMode()
                ),
                oneObjectRow(
                    'This_Mode',
                    'Error_Log__c',
                    ONE_OBJECT_MAPPING,
                    null,
                    null,
                    ImportTemplateService.defaultPersonMode()
                )
            };

            Integer created = ImportTemplateService.materializeDefaults();

            Assert.areEqual(1, created, 'One template for the one key.');
            List<Import_Template__c> templates = templatesWithKey();
            Assert.areEqual(1, templates.size());
            Assert.areEqual('This_Mode', templates[0].Name, 'The matching row, not the other.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'ImportTemplateService.oneObjectTemplate'
                ],
                'A row for the other mode is passed over without a log entry.'
            );
        }
    }
}
