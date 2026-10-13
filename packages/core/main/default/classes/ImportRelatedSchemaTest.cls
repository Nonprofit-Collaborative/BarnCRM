/**
 * The template side of related records (canonical model R-IT17; ADR-NEXT
 * `NEXT-load-related-records.md`): which related records an object offers, saving the choice
 * with describe's names, and the refusals, at save and at run time, of Insert and of a field
 * that does not point at the object. The `Related` entity of the mapping document is read
 * apart from `Record`.
 *
 * Organizations stand for the parent and affiliations for the related object. Every test runs
 * as a minimal-profile user holding only BarnCRM Admin.
 */
@IsTest
private class ImportRelatedSchemaTest {
    static {
        // Dismissals are the package's bookkeeping, which an import refuses; here they stand in
        // for an org's own object, which Core does not otherwise have.
        DataProtectedFields.ordinaryForTest.add('duplicate_dismissal__c');
    }

    private static Import_Template__c template;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static ImportMapping mapping() {
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Org', 'Record.Name'));
        ImportMapping.Column employer = new ImportMapping.Column('Person', 'Related.Contact__c');
        employer.lookupField = 'Email';
        mapping.columns.add(employer);
        mapping.columns.add(new ImportMapping.Column('Role', 'Related.Role__c'));
        return mapping;
    }

    /** Organizations updated by name, each row also creating an affiliation. */
    private static void given() {
        template = ImportTestDataFactory.template(mapping().serialize(), null);
        template.Target_Object__c = 'Account';
        template.Load_Operation__c = ImportObjectSchema.OPERATION_UPDATE_BY_FIELD;
        template.Load_Match_Field__c = 'Name';
        template.Related_Object__c = 'Affiliation__c';
        template.Related_Parent_Field__c = 'Organization__c';
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
    }

    private static String refused() {
        return ImportObjectSchema.refusal(
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c)
        );
    }

    private static Set<String> optionValues() {
        Set<String> result = new Set<String>();
        for (ImportMapping.Target option : ImportObjectSchema.relatedOptions(Account.SObjectType)) {
            result.add(option.value);
        }
        return result;
    }

    @IsTest
    static void theRelatedEntityIsReadApartFromTheRecord() {
        // runs-as: deploying user (reads a mapping document only, no records or describe)
        ImportMapping parsed = mapping();
        Assert.areEqual(
            new Set<String>{ 'name' },
            parsed.recordAttributes(),
            'Record columns alone.'
        );
        Assert.areEqual(
            new Set<String>{ 'contact__c', 'role__c' },
            parsed.attributesOf(ImportMapping.ENTITY_RELATED),
            'Related columns alone.'
        );
        Assert.areEqual(
            new Map<String, String>{ 'contact__c' => 'Email' },
            parsed.lookupFieldsByAttribute(ImportMapping.ENTITY_RELATED),
            'With their lookups.'
        );
        Assert.isTrue(parsed.lookupFieldsByAttribute().isEmpty(), 'None for the record.');
    }

    @IsTest
    static void anObjectOffersTheRelatedRecordsThatPointAtItAlone() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Set<String> offered = optionValues();
                Assert.isTrue(
                    offered.contains('Affiliation__c.Organization__c'),
                    'Affiliations, by their organization field: ' + offered
                );
                Assert.isFalse(
                    offered.contains('Affiliation__c.Contact__c'),
                    'Never by a field pointing elsewhere.'
                );
                for (String value : offered) {
                    Assert.isFalse(value.startsWithIgnoreCase('Household_Member__c.'), value);
                    Assert.isFalse(value.startsWithIgnoreCase('Contact.'), 'People: ' + value);
                }
            }
        }
    }

    @IsTest
    static void theChoiceIsSavedWithDescribesNamesAndRefusedWhenItCannotLoad() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given();
                Assert.isNull(refused(), 'The template as given loads.');

                ImportTemplateService.LoadChoices choices = new ImportTemplateService.LoadChoices();
                choices.operation = ImportObjectSchema.OPERATION_UPDATE_BY_FIELD;
                choices.matchField = 'name';
                choices.related = 'affiliation__c.organization__c';
                template = ImportTemplateService.saveLoad(template.Id, choices);
                Assert.areEqual('Affiliation__c', template.Related_Object__c, 'Describe names it.');
                Assert.areEqual('Organization__c', template.Related_Parent_Field__c, 'Likewise.');

                choices.related = 'Affiliation__c.Contact__c';
                try {
                    ImportTemplateService.saveLoad(template.Id, choices);
                    Assert.fail('A field pointing at people does not link to organizations.');
                } catch (ImportException e) {
                    Assert.isTrue(
                        e.getMessage()
                            .contains(
                                Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                                    .getLabel()
                            ),
                        'Naming the object: ' + e.getMessage()
                    );
                }

                choices.related = '';
                template = ImportTemplateService.saveLoad(template.Id, choices);
                Assert.isNull(template.Related_Object__c, 'Cleared when none is chosen.');

                template.Related_Object__c = 'Affiliation__c';
                template.Related_Parent_Field__c = 'Contact__c';
                Assert.isNotNull(refused(), 'Refused at run time too.');
            }
        }
    }

    @IsTest
    static void insertCannotLoadRelatedRecords() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given();
                template.Target_Object__c = 'Duplicate_Dismissal__c';
                template.Load_Operation__c = ImportObjectSchema.OPERATION_INSERT;
                Assert.areEqual(
                    Label.Core_Import_ErrorRelatedNeedsKey,
                    refused(),
                    'Related records need a parent key.'
                );
                Assert.isNotNull(
                    ImportObjectSchema.insertRefusal(Account.SObjectType),
                    'Organizations are never created by a load, related or not.'
                );
            }
        }
    }
}
