/**
 * Load one object matching by any field (canonical model R-IT13): lookups that name their
 * parent by a phone or any text field, at 200 rows, and the large object guard.
 *
 * Duplicate dismissals stand for an org's own object with an External ID (Pair Key) and a plain
 * text field (Reason), and affiliations for one with a lookup to organizations, as in
 * `ImportObjectLoaderTest`. Every test runs as a minimal-profile user holding only BarnCRM
 * Admin, since every read and save is in that user's own mode.
 */
@IsTest
private class ImportMatchAnyFieldTest {
    static {
        // Dismissals are the package's bookkeeping, which an import refuses; here they stand in
        // for an org's own object, which Core does not otherwise have.
        DataProtectedFields.ordinaryForTest.add('duplicate_dismissal__c');
    }

    private static final Integer MANY = 200;

    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** A template loading this object, with these columns (source, target, lookup field). */
    private static void given(
        String objectName,
        String operation,
        String matchField,
        List<List<String>> columns,
        List<Map<String, String>> values
    ) {
        ImportMapping mapping = new ImportMapping();
        for (List<String> column : columns) {
            ImportMapping.Column mapped = new ImportMapping.Column(column[0], column[1]);
            mapped.lookupField = column.size() > 2 ? column[2] : null;
            mapping.columns.add(mapped);
        }
        template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = objectName;
        template.Load_Operation__c = operation;
        template.Load_Match_Field__c = matchField;
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
    }

    /** One pass over every row as one chunk. */
    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        ImportBatchService.beginPass(batch.Id);
        batch = ImportBatchSelector.selectById(batch.Id);
        return ImportRowProcessor.process(
            batch,
            template,
            mapping(),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static ImportMapping mapping() {
        return ImportMapping.parse(
            template.Column_Mapping_JSON__c,
            template.Default_Values_JSON__c
        );
    }

    private static List<Import_Row__c> rows() {
        return [
            SELECT Row_Number__c, Status__c, Error_Message__c, Gift_Id__c, Several_Matches__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    private static String rowErrors() {
        List<String> errors = new List<String>();
        for (Import_Row__c row : rows()) {
            if (row.Error_Message__c != null) {
                errors.add(row.Row_Number__c + ': ' + row.Error_Message__c);
            }
        }
        return String.join(errors, '; ');
    }

    private static List<Duplicate_Dismissal__c> dismissals(Integer count, String reason) {
        List<Duplicate_Dismissal__c> result = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < count; i++) {
            result.add(new Duplicate_Dismissal__c(Pair_Key__c = 'K' + i, Reason__c = reason));
        }
        insert result;
        return result;
    }

    private static Account organization(String name, String phone) {
        Account created = new Account(
            Name = name,
            Phone = phone,
            RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
        insert created;
        return created;
    }

    private static List<List<String>> affiliationColumns(String employerField) {
        return new List<List<String>>{
            new List<String>{ 'Person', 'Record.Contact__c' },
            new List<String>{ 'Employer', 'Record.Organization__c', employerField },
            new List<String>{ 'Role', 'Record.Role__c' }
        };
    }

    private static Map<String, String> affiliation(Id personId, String employer, String role) {
        return new Map<String, String>{
            'Person' => personId,
            'Employer' => employer,
            'Role' => role
        };
    }

    private static Contact person(String lastName, String email) {
        Contact created = new Contact(FirstName = 'Ana', LastName = lastName, Email = email);
        insert created;
        return created;
    }

    // -------------------------------------------------------------------------------------
    // Lookups by any field (R-IT13)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void lookupsFindTheirParentByAPhoneOrAnyTextField() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez', null);
                Account rose = organization('Rose City Arts', '555-0100');
                Account oak = organization('Oak Street Food Bank', '555-0101');
                List<String> offered = new List<String>();
                for (
                    ImportMapping.Target field : ImportObjectSchema.parentFields(
                        Affiliation__c.SObjectType,
                        'Organization__c'
                    )
                ) {
                    offered.add(field.value);
                }
                Assert.isTrue(offered.contains('Phone'), 'A phone is offered: ' + offered);
                Assert.isTrue(offered.contains('Preferred_Name__c'), 'And any text field.');
                Assert.isTrue(offered.contains('Work_Email__c'), 'And any email field.');
                Assert.isFalse(offered.contains('Anniversary__c'), 'A date is not.');
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY; i++) {
                    values.add(
                        affiliation(
                            ana.Id,
                            Math.mod(i, 2) == 0 ? '555-0100' : ' 555-0101 ',
                            'Volunteer ' + i
                        )
                    );
                }
                given(
                    'Affiliation__c',
                    ImportObjectSchema.OPERATION_INSERT,
                    null,
                    affiliationColumns('Phone'),
                    values
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(MANY, committed.created, 'Every row: ' + rowErrors());
                Assert.areEqual(
                    MANY / 2,
                    [SELECT COUNT() FROM Affiliation__c WHERE Organization__c = :rose.Id],
                    'Half found the first organization by its phone.'
                );
                Assert.areEqual(
                    MANY / 2,
                    [SELECT COUNT() FROM Affiliation__c WHERE Organization__c = :oak.Id],
                    'And half the second.'
                );
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // The large object guard (R-IT13)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void anUnindexedFieldIsRefusedOnAnObjectOverTheCeilingAndAnIndexedOneIsNot() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                ImportObjectSchema.largeObjectRows = 1;
                Contact ana = person('Ramirez', null);
                organization('Rose City Arts', '555-0100');
                organization('Oak Street Food Bank', '555-0101');
                given(
                    'Affiliation__c',
                    ImportObjectSchema.OPERATION_INSERT,
                    null,
                    affiliationColumns('Phone'),
                    new List<Map<String, String>>{ affiliation(ana.Id, '555-0100', 'Volunteer') }
                );
                String expected = String.format(
                    Label.Core_Import_ErrorFieldNotSelective,
                    new List<String>{
                        Account.Phone.getDescribe().getLabel(),
                        Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabelPlural(),
                        '1'
                    }
                );
                Assert.areEqual(
                    expected,
                    ImportObjectSchema.refusal(template, mapping()),
                    'A phone is not indexed.'
                );

                Test.startTest();
                ImportRowProcessor.Outcome refused = run(true);
                Test.stopTest();
                Assert.areEqual(1, refused.rejected, 'Every row carries the reason.');
                Assert.areEqual(expected, rows()[0].Error_Message__c, 'In words to act on.');

                Assert.isTrue(ImportObjectSchema.isIndexed(Account.SObjectType, 'Name'), 'Name.');
                Assert.isTrue(ImportObjectSchema.isIndexed(Contact.SObjectType, 'Email'), 'Email.');
                Assert.isFalse(
                    ImportObjectSchema.isIndexed(Contact.SObjectType, 'Work_Email__c'),
                    'A custom email field is not.'
                );
                Assert.isNull(
                    ImportObjectSchema.unselective(Account.SObjectType, 'Name'),
                    'The name may always be searched.'
                );

                dismissals(2, 'Old');
                Assert.isNull(
                    ImportObjectSchema.unselective(
                        Duplicate_Dismissal__c.SObjectType,
                        'Pair_Key__c'
                    ),
                    'An External ID may always be searched.'
                );
                Assert.isNotNull(
                    ImportObjectSchema.unselective(Duplicate_Dismissal__c.SObjectType, 'Reason__c'),
                    'A plain text field may not, over the ceiling.'
                );
            }
        }
    }

    @IsTest
    static void anUnindexedFieldIsMatchedOnAnObjectUnderTheCeiling() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                organization('Rose City Arts', '555-0100');
                Assert.isNull(
                    ImportObjectSchema.unselective(Account.SObjectType, 'Phone'),
                    'A small object is read whole without harm.'
                );
            }
        }
    }
}
