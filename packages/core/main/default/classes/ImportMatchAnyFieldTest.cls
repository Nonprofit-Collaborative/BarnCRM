/**
 * Load one object matching by any field (canonical model R-IT12, R-IT13): Update by a matching
 * field at 200 rows, its several-matches and not-found rules and its refusals; lookups that name
 * their parent by a phone or any text field; and the large object guard.
 *
 * Duplicate dismissals stand for an org's own object with an External ID (Pair Key) and a plain
 * text field (Reason), and affiliations for one with a lookup to organizations, as in
 * `ImportObjectLoaderTest`. Every test runs as a minimal-profile user holding only BarnCRM
 * Admin, since every read and save is in that user's own mode.
 */
@IsTest(testFor='ApexClass:ImportObjectSchema, ApexClass:ImportObjectLoader')
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

    private static void set(Schema.SObjectField field, String value) {
        template.put(field, value);
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
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
            WITH SYSTEM_MODE
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
            RecordTypeId = AccountKindsTestData.organizationRecordTypeId()
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
    // Update by a matching field (R-IT12)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void twoHundredUpdatesFindTheirRecordByTheChosenFieldAndCreateNothing() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                dismissals(MANY, 'Old');
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY - 1; i++) {
                    // Ignoring case: the file writes the key in lower case.
                    values.add(new Map<String, String>{ 'Key' => 'k' + i, 'Reason' => 'New' });
                }
                values.add(new Map<String, String>{ 'Key' => 'Nobody', 'Reason' => 'New' });
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                    'Pair_Key__c',
                    new List<List<String>>{
                        new List<String>{ 'Key', 'Record.Pair_Key__c' },
                        new List<String>{ 'Reason', 'Record.Reason__c' }
                    },
                    values
                );

                Test.startTest();
                ImportRowProcessor.Outcome preview = run(true);
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(MANY - 1, preview.updated, 'The dry run decides as the commit.');
                Assert.areEqual(MANY - 1, committed.updated, 'Every found row: ' + rowErrors());
                Assert.areEqual(0, committed.created, 'An update never creates.');
                Assert.areEqual(1, committed.rejected, 'The value no record holds.');
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorNoRecordMatched,
                        new List<String>{
                            Duplicate_Dismissal__c.Pair_Key__c.getDescribe().getLabel()
                        }
                    ),
                    rows()[MANY - 1].Error_Message__c,
                    'Named on its row.'
                );
                Assert.areEqual(
                    MANY,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c],
                    'Nothing was created.'
                );
                Assert.areEqual(
                    MANY - 1,
                    [SELECT COUNT() FROM Duplicate_Dismissal__c WHERE Reason__c = 'New'],
                    'The new reasons are saved.'
                );
            }
        }
    }

    @IsTest
    static void aValueSeveralRecordsHoldRejectsOrTakesTheMostRecentlyChanged() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                dismissals(2, 'Same');
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                    'Reason__c',
                    new List<List<String>>{ new List<String>{ 'Reason', 'Record.Reason__c' } },
                    new List<Map<String, String>>{ new Map<String, String>{ 'Reason' => 'same' } }
                );

                Test.startTest();
                ImportRowProcessor.Outcome rejecting = run(true);
                Import_Row__c rejected = rows()[0];
                set(
                    Import_Template__c.Several_Matches__c,
                    ImportTemplateService.SEVERAL_MOST_RECENT
                );
                ImportRowProcessor.Outcome taking = run(true);
                Test.stopTest();

                Assert.areEqual(1, rejecting.rejected, 'Several records reject by default.');
                Assert.areEqual(
                    Label.Core_Import_ErrorSeveralRecords,
                    rejected.Error_Message__c,
                    'Saying why.'
                );
                Assert.isTrue(rejected.Several_Matches__c, 'The row says several matched.');
                Assert.areEqual(
                    1,
                    taking.matched + taking.updated,
                    'The most recently changed is taken when asked: ' + rowErrors()
                );
            }
        }
    }

    @IsTest
    static void anUpdateByAFieldIsRefusedWithoutAUsableMappedField() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                given(
                    'Duplicate_Dismissal__c',
                    ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                    null,
                    new List<List<String>>{ new List<String>{ 'Reason', 'Record.Reason__c' } },
                    new List<Map<String, String>>{ new Map<String, String>{ 'Reason' => 'x' } }
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorMatchFieldRequired,
                    ImportObjectSchema.refusal(template, mapping()),
                    'A field must be chosen.'
                );
                set(Import_Template__c.Load_Match_Field__c, 'CreatedDate');
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorMatchFieldUnusable,
                        new List<String>{ 'CreatedDate' }
                    ),
                    ImportObjectSchema.refusal(template, mapping()),
                    'Only a text, email or phone field.'
                );
                set(Import_Template__c.Load_Match_Field__c, 'Pair_Key__c');
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_ErrorMatchColumnMissing,
                        new List<String>{
                            Duplicate_Dismissal__c.Pair_Key__c.getDescribe().getLabel()
                        }
                    ),
                    ImportObjectSchema.refusal(template, mapping()),
                    'A column must feed it.'
                );
                set(Import_Template__c.Load_Match_Field__c, 'Reason__c');
                Assert.isNull(ImportObjectSchema.refusal(template, mapping()), 'Now it can run.');
            }
        }
    }

    @IsTest
    static void peopleMayBeUpdatedByAMatchingFieldButNothingElseNew() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Contact ana = person('Ramirez', 'ana@example.org');
                Assert.isTrue(
                    ImportObjectSchema.operationsFor(Contact.SObjectType)
                        .contains(ImportObjectSchema.OPERATION_UPDATE_BY_FIELD),
                    'People may be updated by a field.'
                );
                Assert.isFalse(
                    ImportObjectSchema.operationsFor(Contact.SObjectType)
                        .contains(ImportObjectSchema.OPERATION_UPSERT),
                    'But still not upserted.'
                );
                given(
                    'Contact',
                    ImportObjectSchema.OPERATION_INSERT,
                    null,
                    new List<List<String>>{
                        new List<String>{ 'Email', 'Record.Email' },
                        new List<String>{ 'Title', 'Record.Title' }
                    },
                    new List<Map<String, String>>{
                        new Map<String, String>{
                            'Email' => 'ANA@example.org',
                            'Title' => 'Treasurer'
                        }
                    }
                );
                ImportTemplateService.LoadChoices choices = new ImportTemplateService.LoadChoices();
                choices.operation = ImportObjectSchema.OPERATION_UPDATE_BY_FIELD;
                choices.matchField = 'email';
                template = ImportTemplateService.saveLoad(template.Id, choices);
                Assert.areEqual(
                    ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                    template.Load_Operation__c,
                    'Kept for people.'
                );
                Assert.areEqual('Email', template.Load_Match_Field__c, 'As describe names it.');
                choices.matchField = 'Birthdate';
                try {
                    ImportTemplateService.saveLoad(template.Id, choices);
                    Assert.fail('A date cannot match rows.');
                } catch (ImportException e) {
                    Assert.areEqual(
                        String.format(
                            Label.Core_Import_ErrorMatchFieldUnusable,
                            new List<String>{ 'Birthdate' }
                        ),
                        e.getMessage(),
                        'Naming the field.'
                    );
                }
                template = ImportTemplateSelector.selectById(template.Id);

                Test.startTest();
                ImportRowProcessor.Outcome committed = run(false);
                Test.stopTest();

                Assert.areEqual(1, committed.updated, 'Found by email: ' + rowErrors());
                Assert.areEqual(
                    'Treasurer',
                    [SELECT Title FROM Contact WHERE Id = :ana.Id].Title,
                    'The title is saved.'
                );
            }
        }
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
