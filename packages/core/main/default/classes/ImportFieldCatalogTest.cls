/**
 * C-32 custom fields on people and organizations (R-IT11, ADR-0069
 * `0069-import-record-id-matching-and-match-only.md`): the wizard is offered the fields the
 * user may write that a cell can fill, and not formulas, lookups, system fields or the
 * package's own; a column mapped to one is written by the import.
 */
@IsTest
private class ImportFieldCatalogTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    private static Set<String> names(List<ImportMapping.Target> targets) {
        Set<String> result = new Set<String>();
        for (ImportMapping.Target target : targets) {
            result.add(target.value.toLowerCase());
        }
        return result;
    }

    private static void assertWritable(Schema.SObjectType type, List<ImportMapping.Target> found) {
        Map<String, Schema.SObjectField> fields = type.getDescribe().fields.getMap();
        for (ImportMapping.Target target : found) {
            Schema.DescribeFieldResult describe = fields.get(target.value.toLowerCase())
                .getDescribe();
            Assert.isTrue(describe.isAccessible(), 'Readable: ' + target.value);
            Assert.isTrue(
                describe.isCreateable() || describe.isUpdateable(),
                'Writable: ' + target.value
            );
            Assert.isFalse(describe.isCalculated(), 'Not a formula: ' + target.value);
            Assert.areNotEqual(
                Schema.DisplayType.REFERENCE,
                describe.getType(),
                'Not a lookup: ' + target.value
            );
            Assert.areEqual(describe.getLabel(), target.label, 'Listed by its label.');
        }
    }

    @IsTest
    static void aPersonIsOfferedTheFieldsTheUserMayWrite() {
        Test.startTest();
        List<ImportMapping.Target> found = ImportFieldCatalog.personFields();
        Test.stopTest();

        assertWritable(Contact.SObjectType, found);
        Set<String> offered = names(found);
        Assert.isTrue(offered.contains('department'), 'A standard field not in the fixed list.');
        Assert.isFalse(offered.contains('accountid'), 'No lookup.');
        Assert.isFalse(offered.contains('name'), 'No compound name.');
        Assert.isFalse(offered.contains('mailingaddress'), 'No compound address.');
        Assert.isFalse(offered.contains('jigsaw'), 'No system field.');
        Assert.isFalse(
            offered.contains(
                Contact.Created_By_Import_Batch__c.getDescribe().getName().toLowerCase()
            ),
            'Not the package bookkeeping.'
        );
        for (Integer i = 1; i < found.size(); i++) {
            Assert.isTrue(found[i - 1].label.compareTo(found[i].label) <= 0, 'In label order.');
        }
    }

    @IsTest
    static void anOrganizationIsOfferedItsOwnFieldsNotAPersonsOrAHouseholds() {
        Test.startTest();
        List<ImportMapping.Target> found = ImportFieldCatalog.organizationFields();
        Test.stopTest();

        assertWritable(Account.SObjectType, found);
        Set<String> offered = names(found);
        Assert.isTrue(offered.contains('industry'), 'An organization field.');
        Assert.isFalse(offered.contains('parentid'), 'No lookup.');
        Assert.isFalse(offered.contains('personemail'), 'No person account field.');
        Assert.isFalse(
            offered.contains(Account.Deceased__c.getDescribe().getName().toLowerCase()),
            'Not a person field the package puts on Account.'
        );
        Assert.isFalse(
            offered.contains(Account.Custom_Name__c.getDescribe().getName().toLowerCase()),
            'Not a household field.'
        );
        for (ImportMapping.Target target : found) {
            Assert.isFalse(target.value.toLowerCase().endsWith('__pc'), 'No __pc field.');
        }
    }

    @IsTest
    static void theWizardGetsBothLists() {
        ImportController.permissionOverride = true;
        Test.startTest();
        ImportController.MatchFieldsView view = ImportController.getMatchFields();
        Test.stopTest();
        Assert.areEqual(
            names(ImportFieldCatalog.personFields()),
            names(view.personFields),
            'The person list.'
        );
        Assert.areEqual(
            names(ImportFieldCatalog.organizationFields()),
            names(view.organizationFields),
            'The organization list.'
        );
    }

    @IsTest
    static void twoHundredRowsWriteFieldsOutsideTheFixedList() {
        ImportMapping mapping = new ImportMapping();
        for (
            String target : new List<String>{
                'Contact1.LastName',
                'Contact1.Department',
                'Organization.Name',
                'Organization.Industry'
            }
        ) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        Import_Template__c template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_NAME_POSTAL
        );
        Import_Batch__c batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (Integer i = 0; i < 200; i++) {
            values.add(
                new Map<String, String>{
                    'Contact1.LastName' => 'Lopez' + i,
                    'Contact1.Department' => 'Volunteers',
                    'Organization.Name' => 'Harbor Trust',
                    'Organization.Industry' => 'Education'
                }
            );
        }
        ImportTestDataFactory.rows(batch, values);

        Test.startTest();
        ImportBatchService.beginPass(batch.Id);
        ImportProcessorBatch job = new ImportProcessorBatch(batch.Id, false);
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            chunk.add((Import_Row__c) rows.next());
        }
        job.execute(null, chunk);
        job.finish(null);
        Test.stopTest();

        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Contact WHERE Department = 'Volunteers'],
            'Every person carries the field.'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Name = 'Harbor Trust' AND Industry = 'Education'],
            'The one organization carries its field.'
        );
    }
}
