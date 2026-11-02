/**
 * The Indicator Results import template (L-03, canonical model R-IN3): shipped as a one-object
 * template that updates Indicator Periods by record Id, it loads the result, target and notes of
 * each row's period, ignores the sheet's other columns, and rejects a row whose Period Id names
 * no period, creating nothing.
 */
@IsTest(testFor='ApexClass:LogicModelsPostInstall')
private class IndicatorResultsImportTest {
    private static final String ADMIN = 'Logic_Models_Admin';
    private static final String TEMPLATE_KEY = 'indicator_results';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
    }

    private static Import_Template__c template() {
        ImportTemplateService.materializeDefaults();
        return [
            SELECT
                Id,
                Target_Object__c,
                Load_Operation__c,
                Column_Mapping_JSON__c,
                Default_Values_JSON__c,
                Active__c
            FROM Import_Template__c
            WHERE Template_Key__c = :TEMPLATE_KEY
            WITH SYSTEM_MODE
        ];
    }

    private static Id period() {
        Logic_Model__c model = new Logic_Model__c(Name = 'Import Model');
        insert as user model;
        Logic_Model_Element__c element = new Logic_Model_Element__c(
            Logic_Model__c = model.Id,
            Name = 'Students read more',
            Type__c = 'Outcome',
            Outcome_Term__c = 'Short Term'
        );
        insert as user element;
        Indicator__c indicator = new Indicator__c(
            Element__c = element.Id,
            Name = 'Students reading',
            Source__c = 'Import'
        );
        insert as user indicator;
        Indicator_Period__c period = new Indicator_Period__c(
            Indicator__c = indicator.Id,
            Name = '2026 Q1',
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c = Date.newInstance(2026, 3, 31),
            Target_Value__c = 30
        );
        insert as user period;
        return period.Id;
    }

    @IsTest
    static void theSheetUpdatesEachRowsPeriodAndCreatesNothing() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Import_Template__c shipped = template();
            Id periodId = period();
            Import_Batch__c batch = ImportTestDataFactory.batch(shipped);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Period Id' => periodId,
                        'Indicator' => 'Students reading',
                        'Period' => '2026 Q1',
                        'Target' => '30',
                        'Result' => '25',
                        'Notes' => 'From the spring survey'
                    },
                    new Map<String, String>{
                        'Period Id' => 'a0Z000000000000AAA',
                        'Target' => '1',
                        'Result' => '2'
                    }
                }
            );

            Test.startTest();
            ImportBatchService.beginPass(batch.Id);
            ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
                ImportBatchSelector.selectById(batch.Id),
                ImportTemplateSelector.selectById(shipped.Id),
                ImportMapping.parse(shipped.Column_Mapping_JSON__c, shipped.Default_Values_JSON__c),
                ImportTestDataFactory.reload(batch.Id),
                false
            );
            Test.stopTest();

            Assert.areEqual('Indicator_Period__c', shipped.Target_Object__c, 'Loads periods');
            Assert.areEqual(ImportObjectSchema.OPERATION_UPDATE, shipped.Load_Operation__c);
            Assert.isTrue(shipped.Active__c, 'Offered');
            Assert.areEqual(1, outcome.updated, 'The named period is updated');
            Assert.areEqual(1, outcome.rejected, 'A row naming no period is rejected');
            Assert.areEqual(0, outcome.created, 'Nothing is created');
            Indicator_Period__c loaded = [
                SELECT Result_Value__c, Target_Value__c, Notes__c
                FROM Indicator_Period__c
                WHERE Id = :periodId
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(25, loaded.Result_Value__c, 'Result loaded');
            Assert.areEqual(30, loaded.Target_Value__c, 'Target unchanged');
            Assert.areEqual('From the spring survey', loaded.Notes__c, 'Notes loaded');
        }
    }
}
