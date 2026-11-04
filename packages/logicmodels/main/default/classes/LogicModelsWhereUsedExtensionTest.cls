/**
 * Logic Models' part of Where Used (C-59): a computed indicator is found by the date field and the
 * summed field of its source, links to its logic model, a typed-in indicator is never listed, and
 * Core finds this extension by name.
 */
@IsTest(testFor='ApexClass:LogicModelsWhereUsedExtension')
private class LogicModelsWhereUsedExtensionTest {
    private static final String ADMIN = 'Logic_Models_Admin';
    private static final String PERIODS =
        '{"version": 1, "object": "Indicator_Period__c", "fields": ["Name"], ' +
        '"filter": {"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "equals", "value": "Session"}]}}';

    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith(ADMIN);
    }

    @IsTest
    static void aComputedIndicatorIsFoundByItsSourceFields() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Logic_Model__c model = new Logic_Model__c(Name = 'Where Used Model');
            insert as system model;
            Logic_Model_Element__c element = new Logic_Model_Element__c(
                Logic_Model__c = model.Id,
                Name = 'Sessions held',
                Type__c = 'Output'
            );
            insert as system element;
            Saved_Query__c query = new Saved_Query__c(
                Name = 'Periods',
                Object_Name__c = 'Indicator_Period__c',
                Query_JSON__c = PERIODS
            );
            insert as system query;
            Indicator__c computed = new Indicator__c(
                Element__c = element.Id,
                Name = 'Results summed',
                Source__c = IndicatorSourceService.COMPUTED,
                Source_Query__c = query.Id,
                Source_Definition__c = '{"version": 1, "dateField": "Start_Date__c", "function": "sum", "field": "Result_Value__c"}'
            );
            Indicator__c typed = new Indicator__c(Element__c = element.Id, Name = 'Typed in');
            insert as system new List<Indicator__c>{ computed, typed };
            LogicModelsWhereUsedExtension extension = new LogicModelsWhereUsedExtension();

            Test.startTest();
            List<WhereUsedService.Reference> byDate = extension.references(
                WhereUsedService.target('Indicator_Period__c', 'Start_Date__c')
            );
            List<WhereUsedService.Reference> bySum = extension.references(
                WhereUsedService.target('Indicator_Period__c', 'Result_Value__c')
            );
            List<WhereUsedService.Reference> other = extension.references(
                WhereUsedService.target('Indicator_Period__c', 'End_Date__c')
            );
            List<WhereUsedService.Reference> wholeObject = extension.references(
                WhereUsedService.target('Indicator_Period__c', null)
            );
            Test.stopTest();

            Assert.areEqual(1, byDate.size(), 'The date field the source counts by.');
            Assert.areEqual('Results summed', byDate[0].getName());
            Assert.areEqual(
                new List<String>{
                    Schema.SObjectType.Indicator__c.fields.Source_Definition__c.getLabel()
                },
                byDate[0].getParts()
            );
            Assert.areEqual(System.Label.Core_WhereUsed_BreaksModuleRecord, byDate[0].getBreaks());
            Assert.areEqual('/lightning/r/' + model.Id + '/view', byDate[0].editUrl);
            Assert.areEqual(1, bySum.size(), 'The field the source sums.');
            Assert.isTrue(other.isEmpty(), 'A field the source does not read is not listed.');
            Assert.isTrue(
                wholeObject.isEmpty(),
                'The counted object is the saved query\'s, in Core.'
            );
            Assert.isInstanceOfType(
                WhereUsedExtensions.findAll().get('LogicModelsWhereUsedExtension'),
                LogicModelsWhereUsedExtension.class
            );
        }
    }
}
