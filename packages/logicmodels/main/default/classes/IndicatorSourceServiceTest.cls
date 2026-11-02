/**
 * Where an indicator's results come from (L-03, canonical model R-IN3 and R-IN4), through the
 * builder's controller: the saved queries and fields offered, a computed source checked as the
 * admin and worked out at once, the refusals, a computed result never typed over, and what staff
 * and readers may do.
 */
@IsTest(
    testFor='ApexClass:IndicatorSourceService, ApexClass:LogicModelBuilderController, ApexClass:LogicModelService'
)
private class IndicatorSourceServiceTest {
    private static final String ADMIN = 'Logic_Models_Admin';
    private static final String SESSIONS =
        '{"version": 1, "object": "Indicator_Period__c", "fields": ["Name"], ' +
        '"filter": {"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "equals", "value": "Session"}]}}';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith(
            'Staff',
            new List<String>{ 'BarnCRM_Staff', 'Logic_Models_Staff' }
        );
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
        );
    }

    private static User person(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName WITH SYSTEM_MODE LIMIT 1];
    }

    /** A model, an output, an indicator with this month's period, one session today, a query. */
    private class Fixture {
        Id modelId;
        Id indicatorId;
        Id periodId;
        Id queryId;

        Fixture() {
            Logic_Model__c model = new Logic_Model__c(Name = 'Sources Model');
            insert as user model;
            modelId = model.Id;
            Logic_Model_Element__c element = new Logic_Model_Element__c(
                Logic_Model__c = modelId,
                Name = 'Sessions held',
                Type__c = 'Output'
            );
            insert as user element;
            Indicator__c data = new Indicator__c(Element__c = element.Id, Name = 'Data');
            Indicator__c measured = new Indicator__c(Element__c = element.Id, Name = 'Sessions');
            insert as user new List<Indicator__c>{ data, measured };
            indicatorId = measured.Id;
            Indicator_Period__c month = new Indicator_Period__c(
                Indicator__c = indicatorId,
                Name = 'This month',
                Start_Date__c = Date.today().toStartOfMonth(),
                End_Date__c = Date.today().toStartOfMonth().addMonths(1).addDays(-1),
                Result_Value__c = 50
            );
            insert as user new List<Indicator_Period__c>{
                month,
                new Indicator_Period__c(
                    Indicator__c = data.Id,
                    Name = 'Session',
                    Start_Date__c = Date.today(),
                    End_Date__c = Date.today()
                )
            };
            periodId = month.Id;
            Saved_Query__c query = new Saved_Query__c(
                Name = 'Sessions',
                Object_Name__c = 'Indicator_Period__c',
                Query_JSON__c = SESSIONS
            );
            insert as user query;
            queryId = query.Id;
        }

        String source(String source, String dateField, String function, String field) {
            return JSON.serialize(
                new Map<String, Object>{
                    'id' => indicatorId,
                    'source' => source,
                    'queryId' => queryId,
                    'dateField' => dateField,
                    'function' => function,
                    'field' => field
                }
            );
        }
    }

    private static Map<String, Object> indicatorOf(Map<String, Object> model, Id indicatorId) {
        for (Object row : (List<Object>) model.get('indicators')) {
            Map<String, Object> fields = (Map<String, Object>) row;
            if (fields.get('id') == indicatorId) {
                return fields;
            }
        }
        return null;
    }

    private static String refusal(Fixture fixture, String sourceJson) {
        try {
            LogicModelBuilderController.saveSource(fixture.modelId, sourceJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    private static Decimal resultOf(Id periodId) {
        return [
            SELECT Result_Value__c
            FROM Indicator_Period__c
            WHERE Id = :periodId
            WITH SYSTEM_MODE
        ]
        .Result_Value__c;
    }

    @IsTest
    static void theQueriesAndFieldsOfferedAreThePersons() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Fixture fixture = new Fixture();

            Test.startTest();
            List<Map<String, String>> queries = LogicModelBuilderController.getSourceQueries();
            Map<String, Object> fields = LogicModelBuilderController.getSourceFields(
                fixture.queryId
            );
            Test.stopTest();

            Assert.areEqual(1, queries.size(), 'The saved query');
            Assert.areEqual('Sessions', queries[0].get('label'), 'By name');
            Assert.areEqual('Indicator_Period__c', fields.get('objectName'), 'Its object');
            Assert.isTrue(
                JSON.serialize(fields.get('dateFields')).contains('Start_Date__c'),
                'Start Date places records'
            );
            Assert.isTrue(
                JSON.serialize(fields.get('numberFields')).contains('Target_Value__c'),
                'Target can be summed'
            );
            Assert.isFalse(
                JSON.serialize(fields.get('numberFields')).contains('"Name"'),
                'Name is not a number'
            );
            Assert.isTrue(
                JSON.serialize(fields.get('uniqueFields')).contains('Indicator__c'),
                'The indicator can be counted once'
            );
        }
    }

    @IsTest
    static void aComputedSourceIsCheckedSavedAndWorkedOutAtOnce() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Fixture fixture = new Fixture();

            Test.startTest();
            Map<String, Object> model = LogicModelBuilderController.saveSource(
                fixture.modelId,
                fixture.source('Computed', 'Start_Date__c', 'count', 'Ignored__c')
            );
            Test.stopTest();

            Map<String, Object> indicator = indicatorOf(model, fixture.indicatorId);
            Assert.areEqual('Computed', indicator.get('source'), 'Computed');
            Assert.areEqual('Sessions', indicator.get('queryName'), 'The query named');
            Map<String, Object> definition = (Map<String, Object>) indicator.get('definition');
            Assert.areEqual('Start_Date__c', definition.get('dateField'), 'Its date field');
            Assert.isNull(definition.get('field'), 'A count keeps no field');
            Assert.areEqual(true, model.get('canSetSource'), 'An admin sets sources');
            Assert.areEqual(1, resultOf(fixture.periodId), 'One session this month');

            // A computed result is never typed over; the target still saves.
            LogicModelBuilderController.savePeriod(
                JSON.serialize(
                    new Map<String, Object>{
                        'id' => fixture.periodId,
                        'name' => 'This month',
                        'startDate' => Date.today().toStartOfMonth(),
                        'endDate' => Date.today().toStartOfMonth().addMonths(1).addDays(-1),
                        'targetValue' => 5,
                        'resultValue' => 77
                    }
                )
            );
            Assert.areEqual(1, resultOf(fixture.periodId), 'The computed result stays');

            model = LogicModelBuilderController.saveSource(
                fixture.modelId,
                fixture.source('Import', null, null, null)
            );
            indicator = indicatorOf(model, fixture.indicatorId);
            Assert.areEqual('Import', indicator.get('source'), 'Imported now');
            Assert.isNull(indicator.get('queryId'), 'The query is cleared');
        }
    }

    @IsTest
    static void aSourceThatCannotWorkIsRefusedWithItsReason() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Fixture fixture = new Fixture();

            Test.startTest();
            String notDate = refusal(fixture, fixture.source('Computed', 'Name', 'count', null));
            String notNumber = refusal(
                fixture,
                fixture.source('Computed', 'Start_Date__c', 'sum', 'Name')
            );
            String notCountable = refusal(
                fixture,
                fixture.source('Computed', 'Start_Date__c', 'unique', 'Notes__c')
            );
            String noSuchField = refusal(
                fixture,
                fixture.source('Computed', 'Missing__c', 'count', null)
            );
            String badSource = refusal(fixture, fixture.source('Guessed', null, null, null));
            String badFunction = refusal(
                fixture,
                fixture.source('Computed', 'Start_Date__c', 'average', null)
            );
            delete as user new Saved_Query__c(Id = fixture.queryId);
            String noQuery = refusal(
                fixture,
                fixture.source('Computed', 'Start_Date__c', 'count', null)
            );
            String notComputed;
            try {
                LogicModelBuilderController.refreshResults(fixture.modelId, fixture.indicatorId);
            } catch (AuraHandledException e) {
                notComputed = e.getMessage();
            }
            Test.stopTest();

            Assert.isTrue(notDate.contains('Period'), 'Name is not a date: ' + notDate);
            Assert.isTrue(notNumber.contains('Period'), 'Name is not a number: ' + notNumber);
            Assert.isTrue(
                notCountable.contains('Notes'),
                'Notes is not groupable: ' + notCountable
            );
            Assert.isNotNull(noSuchField, 'An unknown field is refused');
            Assert.areEqual(Label.LogicModels_Source_Invalid, badSource, 'Unknown source');
            Assert.areEqual(Label.LogicModels_Source_Invalid, badFunction, 'Unknown function');
            Assert.areEqual(Label.LogicModels_Source_QueryMissing, noQuery, 'Deleted query');
            Assert.areEqual(Label.LogicModels_Source_NotComputed, notComputed, 'Typed in');
            Assert.areEqual(50, resultOf(fixture.periodId), 'Nothing changed');
        }
    }

    @IsTest
    static void staffSeeTheSourceButOnlyAnAdminChangesIt() {
        Fixture fixture;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            fixture = new Fixture();
            // Set directly: saving through the builder would start a refresh before the test's.
            update as user new Indicator__c(
                Id = fixture.indicatorId,
                Source__c = 'Computed',
                Source_Query__c = fixture.queryId,
                Source_Definition__c = '{"version": 1, "dateField": "Start_Date__c", "function": "count"}'
            );
        }
        String refused;
        Map<String, Object> model;
        Map<String, Object> readerModel;
        String readerRefresh;
        Test.startTest();
        System.runAs(person('Staff')) {
            model = LogicModelBuilderController.getModel(fixture.modelId);
            refused = refusal(fixture, fixture.source('Manual', null, null, null));
            LogicModelBuilderController.refreshResults(fixture.modelId, fixture.indicatorId);
        }
        System.runAs(person('Reader')) {
            readerModel = LogicModelBuilderController.getModel(fixture.modelId);
            try {
                LogicModelBuilderController.refreshResults(fixture.modelId, fixture.indicatorId);
            } catch (AuraHandledException e) {
                readerRefresh = e.getMessage();
            }
        }
        Test.stopTest();

        Map<String, Object> seen = indicatorOf(model, fixture.indicatorId);
        Assert.areEqual('Computed', seen.get('source'), 'Seen');
        Assert.isNull(seen.get('queryName'), 'A query staff cannot open is not named');
        Assert.areEqual(
            'Computed',
            indicatorOf(readerModel, fixture.indicatorId).get('source'),
            'A reader sees it too'
        );
        Assert.areEqual(1, resultOf(fixture.periodId), 'Staff refreshed it');
        Assert.areEqual(false, model.get('canSetSource'), 'Staff do not set sources');
        Assert.areEqual(true, model.get('canRefresh'), 'Staff may refresh');
        Assert.isNotNull(refused, 'Staff cannot change a source');
        Assert.areEqual(
            Label.LogicModels_Source_CannotRefresh,
            readerRefresh,
            'A reader cannot refresh'
        );
    }

    @IsTest
    static void aStoredDefinitionIsReadOnlyWhenComplete() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Assert.isNull(IndicatorSourceService.parse(null), 'Blank');
            Assert.isNull(IndicatorSourceService.parse('not json'), 'Unreadable');
            Assert.isNull(
                IndicatorSourceService.parse('{"dateField": "X__c", "function": "median"}'),
                'Unknown function'
            );
            IndicatorSourceService.Definition read = IndicatorSourceService.parse(
                '{"version": 1, "dateField": "X__c", "function": "sum", "field": "Y__c"}'
            );
            Assert.areEqual('Y__c', read.field, 'Read');
        }
    }
}
