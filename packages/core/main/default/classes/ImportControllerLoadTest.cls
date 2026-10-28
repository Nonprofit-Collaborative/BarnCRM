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
                Assert.areEqual(4, sessions.loadOperations.size(), 'All four operations offered.');
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_UPDATE,
                    people.loadOperation,
                    'People start on Update.'
                );
                Assert.areEqual(2, people.loadOperations.size(), 'And the two updates only.');
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
    static void theWizardIsOfferedRelatedRecordsAndTheirFieldsAndShownTheChoice() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            System.runAs(admin()) {
                Import_Template__c orgs = ImportTemplateService.createObjectTemplate(
                    'Organizations',
                    'Account'
                );
                ImportTemplateService.LoadChoices choices = new ImportTemplateService.LoadChoices();
                choices.operation = ImportObjectSchema.OPERATION_UPDATE;
                choices.related = 'Affiliation__c.Organization__c';
                ImportTemplateService.saveLoad(orgs.Id, choices);

                Test.startTest();
                List<ImportMapping.Target> options = ImportController.getRelatedOptions(orgs.Id);
                List<ImportController.FieldChoice> fields = ImportController.getRelatedFields(
                    orgs.Id,
                    'Affiliation__c.Organization__c'
                );
                List<ImportController.FieldChoice> none = ImportController.getRelatedFields(
                    orgs.Id,
                    'Affiliation__c.Contact__c'
                );
                ImportController.TemplateView shown;
                for (ImportController.TemplateView view : ImportController.getTemplates()) {
                    shown = view.id == orgs.Id ? view : shown;
                }
                Test.stopTest();

                Set<String> offered = new Set<String>();
                for (ImportMapping.Target option : options) {
                    offered.add(option.value);
                }
                Assert.isTrue(offered.contains('Affiliation__c.Organization__c'), 'Offered.');
                Map<String, ImportController.FieldChoice> byValue = new Map<String, ImportController.FieldChoice>();
                for (ImportController.FieldChoice field : fields) {
                    byValue.put(field.value, field);
                }
                Assert.isTrue(byValue.containsKey('Related.Role__c'), 'Its fields: ' + byValue);
                Assert.isTrue(byValue.get('Related.Contact__c').isLookup, 'With its lookups.');
                Assert.isFalse(byValue.containsKey('Related.Id'), 'Never the record ID.');
                Assert.isFalse(
                    byValue.containsKey('Related.Organization__c'),
                    'Nor the field the load fills with the parent.'
                );
                Assert.isTrue(
                    byValue.get('Related.Role__c')
                        .label.startsWith(
                            Affiliation__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                                .getLabel()
                        ),
                    'Named with the related object.'
                );
                Assert.isTrue(none.isEmpty(), 'Nothing for a field pointing elsewhere.');
                Assert.areEqual(
                    Affiliation__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getLabel(),
                    shown.relatedLabel,
                    'The related object is named for what the template loads (D-136).'
                );
                Assert.areEqual(
                    'Affiliation__c.Organization__c',
                    shown.related,
                    'The saved choice is shown.'
                );
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

    @IsTest
    static void startsANewPeopleTemplateFromAnotherWithItsChoices() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = true;
            DataProtectionExtensions.noneForTest = true;
            System.runAs(admin()) {
                Import_Template__c source = ImportTestDataFactory.template(
                    ImportTestDataFactory.donorMapping(),
                    ImportTemplateService.RULE_NAME_POSTAL
                );
                source.Is_Package_Default__c = true;
                source.Is_Recurring__c = true;
                source.Source_Name__c = 'Monthly export';
                source.Several_Matches__c = ImportTemplateService.SEVERAL_MOST_RECENT;
                source.Use_Duplicate_Rules__c = true;
                source.Last_Import_Date__c = Date.today();
                update source;
                Import_Template__c oneObject = ImportTemplateService.createObjectTemplate(
                    'Organizations',
                    'Account'
                );

                Test.startTest();
                ImportController.TemplateView copy = ImportController.copyTemplate(
                    source.Id,
                    '  Event sign-ups '
                );
                String unnamed;
                try {
                    ImportController.copyTemplate(source.Id, ' ');
                } catch (Exception e) {
                    unnamed = e.getMessage();
                }
                String objectRefused;
                try {
                    ImportController.copyTemplate(oneObject.Id, 'Copy of organizations');
                } catch (Exception e) {
                    objectRefused = e.getMessage();
                }
                Test.stopTest();

                Assert.areEqual('Event sign-ups', copy.name, 'The new name, trimmed.');
                Assert.areNotEqual(source.Id, copy.id, 'A new template.');
                Assert.areEqual(source.Column_Mapping_JSON__c, copy.mapping, 'Its columns.');
                Assert.areEqual(
                    ImportTemplateService.RULE_NAME_POSTAL,
                    copy.matchingRule,
                    'Its matching.'
                );
                Assert.areEqual(
                    ImportTemplateService.SEVERAL_MOST_RECENT,
                    copy.severalMatches,
                    'Its choice for several matches.'
                );
                Assert.isTrue(copy.useDuplicateRules, 'Its duplicate rule choice.');
                Assert.isFalse(copy.isPackageDefault, 'The copy is the admin\'s own.');
                Assert.isFalse(copy.isRecurring, 'Not recurring.');
                Assert.isNull(copy.sourceName, 'With no source name.');
                Assert.isNull(copy.lastImportDate, 'Never loaded.');
                Assert.isTrue(copy.templateKey.startsWith('copy_'), 'Its own key.');
                Import_Template__c after = [
                    SELECT Name, Is_Recurring__c
                    FROM Import_Template__c
                    WHERE Id = :source.Id
                ];
                Assert.isTrue(after.Is_Recurring__c, 'The source is unchanged.');
                Assert.areEqual(
                    Label.Core_Import_ErrorObjectTemplateName,
                    unnamed,
                    'A name is needed.'
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorCopyOneObject,
                    objectRefused,
                    'A one-object template is not copied.'
                );
            }
        }
    }

    @IsTest
    static void startingANewTemplateNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            ImportController.permissionOverride = false;
            Import_Template__c source = ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Test.startTest();
            try {
                ImportController.copyTemplate(source.Id, 'Another');
                Assert.fail('Copying a template needs Manage BarnCRM Settings.');
            } catch (Exception e) {
                Assert.areEqual(Label.Core_Import_ErrorNoPermission, e.getMessage(), 'Refused.');
            }
            Test.stopTest();
            Assert.areEqual(1, [SELECT COUNT() FROM Import_Template__c], 'Nothing was created.');
        }
    }
}
