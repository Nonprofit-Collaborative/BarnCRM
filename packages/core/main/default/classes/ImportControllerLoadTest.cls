/**
 * The wizard's one-object path through the controller and the template service (canonical
 * model R-IT12 to R-IT14): the objects offered, a new mapping, the fields and keys a column can
 * use, the suggested mapping, and the load choices saved with the batch.
 *
 * Runs as a minimal-profile user holding only BarnCRM Admin, since every answer is that user's
 * describe.
 */
@IsTest(testFor='ApexClass:ImportController')
private class ImportControllerLoadTest {
    static {
        // Dismissals are the package's bookkeeping, which an import refuses; here they stand in
        // for an org's own object with an External ID, which Core does not otherwise have.
        DataProtectedFields.ordinaryForTest.add('duplicate_dismissal__c');
    }

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    @IsTest
    static void aNewMappingLoadsTheChosenObjectAndPeopleStartOnUpdate() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            DataProtectionExtensions.noneForTest = true;
            System.runAs(admin()) {
                Test.startTest();
                ImportController.TemplateView sessions = ImportController.createObjectTemplate(
                    'Dismissals',
                    'duplicate_dismissal__c'
                );
                ImportController.TemplateView people = ImportController.createObjectTemplate(
                    'Corrections',
                    'Contact'
                );
                String refused;
                try {
                    ImportController.createObjectTemplate('Batches', 'Import_Batch__c');
                } catch (Exception e) {
                    refused = e.getMessage();
                }
                String unnamed;
                try {
                    ImportController.createObjectTemplate(' ', 'Contact');
                } catch (Exception e) {
                    unnamed = e.getMessage();
                }
                Test.stopTest();

                Assert.isTrue(
                    sessions.targetObject.endsWithIgnoreCase('Duplicate_Dismissal__c'),
                    'Stored as describe names it.'
                );
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_INSERT,
                    sessions.loadOperation,
                    'Insert.'
                );
                Assert.areEqual(3, sessions.loadOperations.size(), 'All three operations offered.');
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_UPDATE,
                    people.loadOperation,
                    'People start on Update.'
                );
                Assert.areEqual(1, people.loadOperations.size(), 'And have nothing else.');
                Assert.isNotNull(refused, 'The package bookkeeping is never a target.');
                Assert.isTrue(
                    unnamed.contains(Label.Core_Import_ErrorObjectTemplateName),
                    'Named.'
                );
            }

        }
    }

    @IsTest
    static void theWizardIsOfferedObjectsFieldsLookupsAndKeys() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            System.runAs(admin()) {
                Import_Template__c affiliations = ImportTemplateService.createObjectTemplate(
                    'Affiliations',
                    'Affiliation__c'
                );
                Import_Template__c dismissals = ImportTemplateService.createObjectTemplate(
                    'Dismissals',
                    'Duplicate_Dismissal__c'
                );

                Test.startTest();
                List<ImportMapping.Target> objects = ImportController.getLoadableObjects();
                List<ImportController.FieldChoice> fields = ImportController.getObjectFields(
                    affiliations.Id
                );
                List<ImportMapping.Target> keys = ImportController.getKeyFields(dismissals.Id);
                Test.stopTest();

                Assert.isFalse(objects.isEmpty(), 'Objects are offered.');
                Assert.areEqual('Record.Id', fields[0].value, 'The record ID first.');
                ImportController.FieldChoice contact;
                for (ImportController.FieldChoice field : fields) {
                    if (field.value.endsWithIgnoreCase('Contact__c')) {
                        contact = field;
                    }
                }
                Assert.isTrue(contact.isLookup, 'A lookup is marked.');
                Assert.areEqual('Name', contact.lookupFields[1].value, 'Found by ID or by name.');
                Assert.areEqual(1, keys.size(), 'The pair key is the one external ID.');
            }

        }
    }

    @IsTest
    static void theSuggestionUsesTheObjectsFieldsAndKeepsSavedLookupChoices() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            System.runAs(admin()) {
                Import_Template__c template = ImportTemplateService.createObjectTemplate(
                    'Affiliations',
                    'Affiliation__c'
                );
                ImportMapping saved = new ImportMapping();
                ImportMapping.Column employer = new ImportMapping.Column(
                    'Employer',
                    'Record.Organization__c'
                );
                employer.lookupField = 'Name';
                saved.columns.add(employer);
                ImportTemplateService.saveMapping(template.Id, saved.serialize(), null);

                Test.startTest();
                ImportMapping suggested = ImportMapping.parse(
                    ImportController.suggestMapping(
                        template.Id,
                        new List<String>{ 'Role', 'Employer' }
                    )
                );
                Test.stopTest();

                Assert.isTrue(
                    suggested.columns[0].target.endsWithIgnoreCase('Role__c'),
                    'A heading that is a field.'
                );
                Assert.areEqual(
                    'Name',
                    suggested.columns[1].lookupField,
                    'The saved lookup choice.'
                );
            }

        }
    }

    @IsTest
    static void theLoadChoicesAreSavedWithTheBatch() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            System.runAs(admin()) {
                Import_Template__c template = ImportTemplateService.createObjectTemplate(
                    'Dismissals',
                    'Duplicate_Dismissal__c'
                );
                ImportMapping mapping = new ImportMapping();
                mapping.columns.add(new ImportMapping.Column('Pair Key', 'Record.Pair_Key__c'));
                ImportTemplateService.LoadChoices load = new ImportTemplateService.LoadChoices();
                load.operation = ImportObjectSchema.OPERATION_UPSERT;
                load.matchField = 'pair_key__c';
                load.lookupNotFound = ImportObjectSchema.LOOKUP_LEAVE_EMPTY;
                load.severalMatches = ImportTemplateService.SEVERAL_MOST_RECENT;
                Map<String, Object> options = new Map<String, Object>{ 'load' => load };

                Test.startTest();
                ImportController.createBatch(
                    template.Id,
                    null,
                    'dismissals.csv',
                    mapping.serialize(),
                    null,
                    JSON.serialize(options)
                );
                String unusable;
                try {
                    load.matchField = 'Reason__c';
                    ImportTemplateService.saveLoad(template.Id, load);
                } catch (ImportException e) {
                    unusable = e.getMessage();
                }
                Test.stopTest();

                Import_Template__c stored = ImportTemplateSelector.selectById(template.Id);
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_UPSERT,
                    stored.Load_Operation__c,
                    'Op.'
                );
                Assert.isTrue(stored.Load_Match_Field__c.endsWithIgnoreCase('Pair_Key__c'), 'Key.');
                Assert.areEqual(
                    ImportObjectSchema.LOOKUP_LEAVE_EMPTY,
                    stored.Lookup_Not_Found__c,
                    'Empty.'
                );
                Assert.isTrue(ImportTemplateService.usesMostRecent(stored), 'Most recent.');
                Assert.isTrue(
                    unusable.contains('Reason__c'),
                    'A field that is not a key is refused.'
                );
            }

        }
    }
}
