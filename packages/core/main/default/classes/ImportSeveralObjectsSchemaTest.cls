/**
 * The template side of several objects in one upload (canonical model R-IT20; ADR-0147
 * `0147-several-objects-in-one-upload.md`): the load order and each object's link to the
 * row's parents, legacy related records as two steps, the refusals at save and at run time,
 * a new template, and what the wizard is offered for it.
 *
 * Organizations, people and affiliations stand for the objects. Names are compared as describe
 * gives them, never with a namespace written out. Every test that reads describe or records runs
 * as a minimal-profile user holding only BarnCRM Admin.
 */
@IsTest(
    testFor='ApexClass:ImportObjectSchema, ApexClass:ImportTemplateService, ApexClass:ImportController'
)
private class ImportSeveralObjectsSchemaTest {
    private static final String ACCOUNT_NAME = String.valueOf(Account.SObjectType);
    private static final String CONTACT_NAME = String.valueOf(Contact.SObjectType);
    private static final String AFFILIATION_NAME = String.valueOf(Affiliation__c.SObjectType);

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** Affiliations created and organizations updated by name, listed child first. */
    private static ImportMapping mapping() {
        ImportMapping mapping = new ImportMapping();
        mapping.objects = new List<ImportMapping.ObjectStep>{
            new ImportMapping.ObjectStep(
                AFFILIATION_NAME,
                ImportObjectSchema.OPERATION_INSERT,
                null
            ),
            new ImportMapping.ObjectStep(
                ACCOUNT_NAME,
                ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                'Name'
            )
        };
        mapping.columns.add(new ImportMapping.Column('Org', ACCOUNT_NAME + '.Name'));
        mapping.columns.add(new ImportMapping.Column('Role', AFFILIATION_NAME + '.Role__c'));
        return mapping;
    }

    private static Import_Template__c template(ImportMapping mapping) {
        Import_Template__c template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = ACCOUNT_NAME;
        update template;
        return ImportTemplateSelector.selectById(template.Id);
    }

    private static String refused(Import_Template__c template) {
        return ImportObjectSchema.refusal(
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c)
        );
    }

    private static String labelOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
    }

    @IsTest
    static void parentsLoadFirstAndEachChildLinksToTheRowsParent() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Import_Template__c template = template(mapping());

                List<ImportObjectSchema.Step> steps = ImportObjectSchema.steps(
                    template,
                    ImportMapping.parse(template.Column_Mapping_JSON__c)
                );

                Assert.areEqual(2, steps.size(), 'One step an object.');
                Assert.areEqual(ACCOUNT_NAME, steps[0].entity, 'The parent first.');
                Assert.areEqual(AFFILIATION_NAME, steps[1].entity, 'The child after it.');
                Assert.areEqual(
                    new Map<Integer, String>{ 0 => String.valueOf(Affiliation__c.Organization__c) },
                    steps[1].links,
                    'The child links through the field named for its parent.'
                );
                Assert.isTrue(steps[0].groupsRepeats, 'A keyed parent groups its repeats.');
                Assert.isTrue(steps[0].keepsDigest, 'The first keyed object keeps the digest.');
                Assert.isFalse(steps[1].keepsDigest, 'One digest a row.');
                Assert.areEqual(
                    'Record.Name',
                    steps[0].mapping.columns[0].target,
                    'Each step reads its own columns as Record columns.'
                );
                Assert.isNull(refused(template), 'The template can load.');
            }
        }
    }

    @IsTest
    static void aLinkSkipsFieldsThePackageKeepsAndAnObjectAndItself() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Assert.areEqual(
                    'AccountId',
                    ImportObjectSchema.linkField(Contact.SObjectType, Account.SObjectType),
                    'Not the primary affiliation the package keeps.'
                );
                Assert.isNull(
                    ImportObjectSchema.linkField(Account.SObjectType, Contact.SObjectType),
                    'Not the primary contact the package keeps.'
                );
                Assert.isNull(
                    ImportObjectSchema.linkField(Account.SObjectType, Account.SObjectType),
                    'Never an object and itself.'
                );
            }
        }
    }

    @IsTest
    static void relatedRecordsRunAsASecondStepLinkedToTheRecord() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportMapping legacy = new ImportMapping();
                legacy.columns.add(new ImportMapping.Column('Org', 'Record.Name'));
                legacy.columns.add(new ImportMapping.Column('Role', 'Related.Role__c'));
                Import_Template__c template = ImportTestDataFactory.template(
                    legacy.serialize(),
                    null
                );
                template.Target_Object__c = 'Account';
                template.Load_Operation__c = ImportObjectSchema.OPERATION_UPDATE_BY_FIELD;
                template.Load_Match_Field__c = 'Name';
                template.Related_Object__c = 'Affiliation__c';
                template.Related_Parent_Field__c = 'Organization__c';
                update template;
                template = ImportTemplateSelector.selectById(template.Id);

                List<ImportObjectSchema.Step> steps = ImportObjectSchema.steps(template, legacy);

                Assert.areEqual(2, steps.size(), 'The record, then its related record.');
                Assert.isTrue(steps[0].everyRow && steps[0].groupsRepeats, 'Every row, grouped.');
                Assert.isTrue(steps[1].related, 'The related records keep their results.');
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_INSERT,
                    steps[1].template.Load_Operation__c,
                    'Always created.'
                );
                Assert.areEqual(
                    String.valueOf(Affiliation__c.Organization__c),
                    steps[1].links.get(0),
                    'Linked through the Related Parent Field.'
                );
                Assert.areEqual(
                    new Set<String>{ 'role__c' },
                    steps[1].mapping.recordAttributes(),
                    'Read as its own Record columns.'
                );
            }
        }
    }

    @IsTest
    static void theObjectsAreRefusedAtSaveAndARunNamesTheObject() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportMapping twice = mapping();
                twice.objects.add(
                    new ImportMapping.ObjectStep(
                        ACCOUNT_NAME,
                        ImportObjectSchema.OPERATION_UPDATE,
                        null
                    )
                );
                ImportMapping deletes = mapping();
                deletes.objects[0].operation = ImportObjectSchema.OPERATION_DELETE;
                ImportMapping elsewhere = mapping();
                elsewhere.columns.add(new ImportMapping.Column('Title', CONTACT_NAME + '.Title'));
                ImportMapping noKey = mapping();
                noKey.objects[1].keyField = null;
                ImportMapping unmapped = mapping();
                unmapped.columns.clear();

                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorSeveralObjectsRepeated,
                        new List<String>{ labelOf(Account.SObjectType) }
                    ),
                    ImportObjectSchema.severalObjectsProblem(twice),
                    'An object listed twice.'
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorSeveralObjectsDelete,
                    ImportObjectSchema.severalObjectsProblem(deletes),
                    'No delete.'
                );
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorSeveralObjectsColumn,
                        new List<String>{ 'Title', CONTACT_NAME }
                    ),
                    ImportObjectSchema.severalObjectsProblem(elsewhere),
                    'A column for an object not listed.'
                );
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorOnObject,
                        new List<String>{
                            labelOf(Account.SObjectType),
                            Label.Core_Import_ErrorMatchFieldRequired
                        }
                    ),
                    refused(template(noKey)),
                    'A run names the object that cannot load.'
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorNothingMapped,
                    refused(template(unmapped)),
                    'Nothing mapped at all.'
                );
                Import_Template__c saved = template(mapping());
                try {
                    ImportTemplateService.saveMapping(saved.Id, elsewhere.serialize(), null);
                    Assert.fail('A column for an object not listed is refused on save.');
                } catch (ImportException expected) {
                    Assert.areEqual(
                        ImportObjectSchema.severalObjectsProblem(elsewhere),
                        expected.getMessage(),
                        'Saying why.'
                    );
                }
            }
        }
    }

    @IsTest
    static void aNewTemplateListsEachObjectAndTheWizardIsOfferedThemInLoadOrder() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportController.TemplateView view = ImportController.createSeveralObjectsTemplate(
                    'Members',
                    new List<String>{ AFFILIATION_NAME, ACCOUNT_NAME }
                );

                Assert.isTrue(view.severalObjects, 'Several objects.');
                Assert.areEqual(ACCOUNT_NAME, view.targetObject, 'The first listed is the target.');
                Assert.areEqual(
                    labelOf(Account.SObjectType) + ', ' + labelOf(Affiliation__c.SObjectType),
                    view.targetObjectLabel,
                    'What it loads, in load order.'
                );
                List<ImportController.SeveralObjectView> objects = ImportController.getSeveralObjects(
                    view.id
                );
                Assert.areEqual(2, objects.size(), 'Both, before any column is mapped.');
                Assert.areEqual(ACCOUNT_NAME, objects[0].objectName, 'The parent first.');
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_UPDATE,
                    objects[0].operation,
                    'Organizations start on an update.'
                );
                Assert.isFalse(
                    objects[0].operations.contains(ImportObjectSchema.OPERATION_DELETE),
                    'Never a delete.'
                );
                Assert.areEqual(1, objects[1].links.size(), 'The child says how it links.');
                Assert.isFalse(objects[1].fields.isEmpty(), 'Its fields are offered.');
                Assert.isTrue(
                    objects[1].fields[0].value.startsWith(AFFILIATION_NAME + '.'),
                    'As the object and the field: ' + objects[1].fields[0].value
                );
                try {
                    ImportController.createSeveralObjectsTemplate(
                        'Twice',
                        new List<String>{ ACCOUNT_NAME, ACCOUNT_NAME }
                    );
                    Assert.fail('An object listed twice is refused.');
                } catch (AuraHandledException expected) {
                    Assert.isNotNull(expected.getMessage(), 'Saying why.');
                }
            }
        }
    }

    @IsTest
    static void aSheetsHeadingsMapToItsObjectAndTwoPartHeadingsToTheObjectTheyName() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportController.TemplateView view = ImportController.createSeveralObjectsTemplate(
                    'Members',
                    new List<String>{ ACCOUNT_NAME, AFFILIATION_NAME }
                );
                String twoPart =
                    labelOf(Affiliation__c.SObjectType) +
                    ': ' +
                    Affiliation__c.Role__c.getDescribe().getLabel();

                ImportMapping suggested = ImportMapping.parse(
                    ImportController.suggestSheetMapping(
                        view.id,
                        ACCOUNT_NAME,
                        new List<String>{ 'Name', twoPart, 'Not a field at all' }
                    )
                );

                Assert.areEqual(
                    ACCOUNT_NAME + '.Name',
                    suggested.columns[0].target,
                    'Its own object.'
                );
                Assert.areEqual(
                    AFFILIATION_NAME + '.' + String.valueOf(Affiliation__c.Role__c),
                    suggested.columns[1].target,
                    'The object a two-part heading names.'
                );
                Assert.areEqual(
                    ImportMapping.TARGET_IGNORE,
                    suggested.columns[2].target,
                    'Anything else is not loaded.'
                );
            }
        }
    }
}
