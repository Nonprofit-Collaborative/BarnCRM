/**
 * The Create a Field panel's generator (Rollup Builder ease of use U8, ADR-0136): the field is
 * written as Setup steps, a source file and a Metadata API package, and nothing is created.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupFieldGenerator')
private class RollupFieldGeneratorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin' }
        );
    }

    private static String refusal(String objectApiName, String fieldLabel, String kind) {
        try {
            RollupFieldGenerator.generate(objectApiName, fieldLabel, kind);
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return null;
    }

    @IsTest
    static void aNumberFieldIsWrittenAsStepsASourceFileAndAPackage() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupFieldGenerator.GeneratedField field;
            System.runAs(maria()) {
                field = RollupFieldGenerator.generate('Account', 'Gift Count', 'NUMBER');
            }

            System.Assert.areEqual('Gift_Count__c', field.apiName);
            System.Assert.areEqual(
                'objects/Account/fields/Gift_Count__c.field-meta.xml',
                field.fieldPath
            );
            System.Assert.isTrue(field.fieldXml.contains('<fullName>Gift_Count__c</fullName>'));
            System.Assert.isTrue(field.fieldXml.contains('<label>Gift Count</label>'));
            System.Assert.isTrue(field.fieldXml.contains('<type>Number</type>'));
            System.Assert.isTrue(field.fieldXml.contains('<scale>0</scale>'));
            System.Assert.areEqual(4, field.steps.size(), 'Open, type and name, access, back');
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_FieldStepType,
                    new List<String>{ Label.Core_RollupEase_KindNumber, 'Gift Count', 'Gift_Count' }
                ),
                field.steps[1]
            );
            System.Assert.areEqual('BarnRollupField_Account_Gift_Count__c.zip', field.fileName);

            Compression.ZipReader deploy = new Compression.ZipReader(
                EncodingUtil.base64Decode(field.deployPackage)
            );
            Set<String> entries = new Set<String>();
            for (Compression.ZipEntry entry : deploy.getEntries()) {
                entries.add(entry.getName());
            }
            System.Assert.areEqual(
                new Set<String>{ 'package.xml', 'objects/Account.object' },
                entries
            );
            System.Assert.isTrue(
                deploy.extract(deploy.getEntry('package.xml'))
                    .toString()
                    .contains('<members>Account.Gift_Count__c</members>')
            );
            String objectXml = deploy.extract(deploy.getEntry('objects/Account.object')).toString();
            System.Assert.isTrue(objectXml.contains('<fields>'));
            System.Assert.isTrue(objectXml.contains('<type>Number</type>'));
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing saved');
        }
    }

    @IsTest
    static void eachTypeWritesTheElementsSetupNeeds() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('Total', 'CURRENCY').contains('<scale>2</scale>')
            );
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('First', 'DATE').contains('<type>Date</type>')
            );
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('Last', 'DATETIME').contains('<type>DateTime</type>')
            );
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('Name', 'TEXT').contains('<length>255</length>')
            );
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('List', 'LONGTEXT')
                    .contains('<type>LongTextArea</type>')
            );
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('Has', 'CHECKBOX')
                    .contains('<defaultValue>false</defaultValue>')
            );
            System.Assert.isTrue(
                RollupFieldGenerator.bodyOf('Gifts & <Pledges>', 'NUMBER')
                    .contains('<label>Gifts &amp; &lt;Pledges&gt;</label>'),
                'The label is escaped'
            );
            System.Assert.areEqual(7, RollupFieldGenerator.KINDS.size());
        }
    }

    @IsTest
    static void theFieldNameFollowsSetupRules() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.areEqual(
                'Total_giving_FY',
                RollupFieldGenerator.nameFor('  Total giving (FY)!')
            );
            System.Assert.areEqual('X2025_Gifts', RollupFieldGenerator.nameFor('2025 Gifts'));
            System.Assert.areEqual('', RollupFieldGenerator.nameFor('!!!'));
            System.Assert.areEqual(
                40,
                RollupFieldGenerator.nameFor('A very long label for a rollup field total').length()
            );
        }
    }

    @IsTest
    static void aFieldThatExistsAnEmptyLabelOrNoTypeIsRefused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.runAs(maria()) {
                System.Assert.areEqual(
                    String.format(
                        Label.Core_RollupEase_FieldExists,
                        new List<String>{ 'Member_Count__c' }
                    ),
                    refusal('Account', 'Member Count', 'NUMBER')
                );
                System.Assert.areEqual(
                    Label.Core_RollupEase_FieldLabelProblem,
                    refusal('Account', '  ', 'NUMBER')
                );
                System.Assert.areEqual(
                    Label.Core_RollupEase_FieldLabelProblem,
                    refusal('No_Such_Object__c', 'Gift Count', 'NUMBER')
                );
                System.Assert.areEqual(
                    Label.Core_RollupEase_FieldKindProblem,
                    refusal('Account', 'Gift Count', 'PICKLIST')
                );
            }
        }
    }

    @IsTest
    static void someoneWithoutTheSettingsPermissionCannotWriteAField() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String message;
            System.runAs(david) {
                message = refusal('Account', 'Gift Count', 'NUMBER');
            }
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message);
        }
    }
}
