/**
 * What an import does with a column the importing user may not write: it is skipped, and the
 * run log says so, once per field. And what the Nonprofit Admin role lets an importer write:
 * the opt-out flags, which a migration file carries and which must never be dropped quietly.
 *
 * Both tests run as a user on the Minimum Access profile holding Nonprofit Admin, so what is
 * proved is what the permission set grants, not what a system administrator profile allows.
 */
@IsTest
private class ImportFieldAccessTest {
    private static Import_Template__c template;
    private static Import_Batch__c batch;

    /** A field Nonprofit Admin does not grant, standing for any the importer cannot write. */
    private static final String UNGRANTED_ATTRIBUTE = 'AssistantName';

    private static User importer() {
        Profile minimum = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        User person = new User(
            ProfileId = minimum.Id,
            LastName = 'Fieldaccess',
            Email = 'fieldaccess@barncrm.test.invalid',
            Username = 'fieldaccess' + DateTime.now().getTime() + '@barncrm.test.invalid',
            Alias = 'fldacc',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert person;
            insert new PermissionSetAssignment(
                AssigneeId = person.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Nonprofit_Admin']
                .Id
            );
        }
        return person;
    }

    private static void given() {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        mapping.columns.add(
            new ImportMapping.Column('Email Opt Out', 'Contact1.HasOptedOutOfEmail')
        );
        mapping.columns.add(new ImportMapping.Column('Do Not Call', 'Contact1.DoNotCall'));
        mapping.columns.add(
            new ImportMapping.Column('Assistant', 'Contact1.' + UNGRANTED_ATTRIBUTE)
        );
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> values = new List<Map<String, String>>();
        for (String first : new List<String>{ 'Ana', 'Ben' }) {
            Map<String, String> row = ImportTestDataFactory.donorRow(
                first,
                'Ramirez',
                first.toLowerCase() + '@example.org',
                null
            );
            row.put('Email Opt Out', 'Yes');
            row.put('Do Not Call', 'Yes');
            row.put('Assistant', 'Cy');
            values.add(row);
        }
        ImportTestDataFactory.rows(batch, values);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    /** Why rows were rejected, for an assertion message. */
    private static String rowErrors() {
        List<String> errors = new List<String>();
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            errors.add(row.Status__c + ': ' + row.Error_Message__c);
        }
        return String.join(errors, '; ');
    }

    private static String noAccessNote(Schema.SObjectField field) {
        return String.format(
            Label.Core_Import_LogAttributeNoAccess,
            new List<String>{ field.getDescribe().getLabel() }
        );
    }

    @IsTest
    static void aFieldTheImporterCannotWriteIsNamedOnceInTheRunLog() {
        given();
        User person = importer();
        ImportRowProcessor.Outcome preview;
        ImportRowProcessor.Outcome committed;
        Test.startTest();
        System.runAs(person) {
            Assert.isFalse(
                Contact.AssistantName.getDescribe().isUpdateable(),
                'Precondition: the importer may not write the field this test maps.'
            );
            preview = run(true);
            committed = run(false);
        }
        Test.stopTest();

        String note = noAccessNote(Contact.AssistantName);
        Assert.isTrue(
            preview.notes.contains(note),
            'The dry run says the column will not load, before anything is committed: ' +
            preview.notes
        );
        Assert.isTrue(committed.notes.contains(note), 'So does the commit: ' + committed.notes);
        Integer mentions = 0;
        for (String line : committed.notes) {
            if (line.contains(Contact.AssistantName.getDescribe().getLabel())) {
                mentions++;
            }
        }
        Assert.areEqual(1, mentions, 'Once for the field, not once for each of the two rows.');
        Assert.areEqual(
            2,
            committed.created,
            'The rest of each row still loads: ' + rowErrors() + ' ' + committed.notes
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Contact WHERE AssistantName != NULL],
            'And the skipped column wrote nothing.'
        );
    }

    @IsTest
    static void aNonprofitAdminLoadsTheOptOuts() {
        given();
        User person = importer();
        ImportRowProcessor.Outcome committed;
        Test.startTest();
        System.runAs(person) {
            committed = run(false);
        }
        Test.stopTest();

        Assert.areEqual(
            2,
            committed.created,
            'Both people were created: ' + rowErrors() + ' ' + committed.notes
        );
        for (Contact created : [SELECT HasOptedOutOfEmail, DoNotCall FROM Contact]) {
            Assert.isTrue(created.HasOptedOutOfEmail, 'The email opt-out from the file stuck.');
            Assert.isTrue(created.DoNotCall, 'So did Do Not Call.');
        }
        Assert.isFalse(
            committed.notes.contains(noAccessNote(Contact.HasOptedOutOfEmail)),
            'Nonprofit Admin may write the opt-outs, so none is reported skipped.'
        );
        Assert.isFalse(
            committed.notes.contains(noAccessNote(Contact.DoNotCall)),
            'Nor Do Not Call.'
        );
    }
}
