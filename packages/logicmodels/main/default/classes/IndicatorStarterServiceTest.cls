/**
 * Computed indicator starters (canonical model R-IN8; v1.0 modules-22), through the builder's
 * controller. The shipped starters name other modules' objects, which a Core plus Logic Models
 * org lacks, so these tests swap in starters on Logic Models' own objects: offered only when
 * their object is there, the records to choose from, the saved query written as the admin and the
 * indicator computed from it, and the refusals.
 */
@IsTest(
    testFor='ApexClass:IndicatorStarterService, ApexClass:LogicModelBuilderController, ApexClass:IndicatorSourceService'
)
private class IndicatorStarterServiceTest {
    private static final String ADMIN = 'Logic_Models_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
    }

    /** Periods named Session, by start date, for the indicator chosen. */
    private static void useTestStarters() {
        IndicatorStarterService.starters = new List<IndicatorStarterService.Starter>{
            new IndicatorStarterService.Starter(
                    'sessions',
                    'Indicator_Period__c',
                    'Start_Date__c',
                    'count'
                )
                .filtered(
                    new List<Object>{
                        new Map<String, Object>{
                            'field' => 'Name',
                            'operator' => 'equals',
                            'value' => 'Session'
                        }
                    }
                )
                .asking('Indicator__c', 'Indicator__c', true),
            new IndicatorStarterService.Starter('missing', 'No_Such_Object__c', 'Date__c', 'count'),
            new IndicatorStarterService.Starter(
                    'targets',
                    'Indicator_Period__c',
                    'Start_Date__c',
                    'sum'
                )
                .measuring('Target_Value__c')
                .asking('No_Such_Object__c', 'Notes__c', false)
        };
    }

    private class Fixture {
        Id modelId;
        Id indicatorId;
        Id dataId;

        Fixture() {
            Logic_Model__c model = new Logic_Model__c(Name = 'Starter Model');
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
            dataId = data.Id;
            indicatorId = measured.Id;
        }

        String starter(String key, String choiceId) {
            return JSON.serialize(
                new Map<String, Object>{
                    'id' => indicatorId,
                    'starter' => key,
                    'choiceId' => choiceId,
                    'queryName' => 'Sessions: Data'
                }
            );
        }
    }

    private static String refusal(Fixture fixture, String starterJson) {
        try {
            LogicModelBuilderController.saveStarterSource(fixture.modelId, starterJson);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void onlyStartersWhoseObjectIsThereAreOffered() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            useTestStarters();
            Fixture fixture = new Fixture();

            Test.startTest();
            List<Map<String, Object>> offered = LogicModelBuilderController.getSourceStarters();
            List<Map<String, String>> choices = LogicModelBuilderController.getStarterChoices(
                'sessions'
            );
            List<Map<String, String>> none = LogicModelBuilderController.getStarterChoices(
                'targets'
            );
            Test.stopTest();

            Assert.areEqual(2, offered.size(), 'The starter on a missing object is left out');
            Assert.areEqual('sessions', offered[0].get('value'), 'In order');
            Assert.areEqual(
                Indicator__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel(),
                offered[0].get('choiceLabel'),
                'Named by the chosen object'
            );
            Assert.isNull(offered[1].get('choiceLabel'), 'An optional choice that is missing');
            Assert.areEqual(2, choices.size(), 'Both indicators can be chosen');
            Assert.areEqual(fixture.dataId, choices[0].get('value'), 'By name: Data first');
            Assert.areEqual(0, none.size(), 'Nothing to choose from a missing object');
        }
    }

    @IsTest
    static void aStarterWritesTheQueryAndComputesTheIndicator() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            useTestStarters();
            Fixture fixture = new Fixture();

            Test.startTest();
            Map<String, Object> model = LogicModelBuilderController.saveStarterSource(
                fixture.modelId,
                fixture.starter('sessions', fixture.dataId)
            );
            Test.stopTest();

            Saved_Query__c query = [
                SELECT Name, Object_Name__c, Query_JSON__c, Shared__c, OwnerId
                FROM Saved_Query__c
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            Assert.areEqual('Sessions: Data', query.Name, 'Named as the builder asks');
            Assert.areEqual('Indicator_Period__c', query.Object_Name__c, 'Its object');
            Assert.isFalse(query.Shared__c, 'Private to the admin');
            Assert.areEqual(UserInfo.getUserId(), query.OwnerId, 'The admin owns it');
            Assert.isTrue(query.Query_JSON__c.contains(fixture.dataId), 'The record chosen');
            Assert.isTrue(query.Query_JSON__c.contains('Session'), 'The fixed condition');
            Indicator__c indicator = [
                SELECT Source__c, Source_Query__c, Source_Definition__c
                FROM Indicator__c
                WHERE Id = :fixture.indicatorId
                WITH SYSTEM_MODE
            ];
            Assert.areEqual('Computed', indicator.Source__c, 'Computed');
            Assert.areEqual(query.Id, indicator.Source_Query__c, 'From the new query');
            Assert.isTrue(
                indicator.Source_Definition__c.contains('Start_Date__c'),
                'By the starter date field'
            );
            Assert.isNotNull(model.get('indicators'), 'The model comes back');
        }
    }

    @IsTest
    static void anOptionalChoiceMayBeLeftOut() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            useTestStarters();
            Fixture fixture = new Fixture();

            Test.startTest();
            LogicModelBuilderController.saveStarterSource(
                fixture.modelId,
                fixture.starter('targets', null)
            );
            Test.stopTest();

            Indicator__c indicator = [
                SELECT Source_Definition__c
                FROM Indicator__c
                WHERE Id = :fixture.indicatorId
                WITH SYSTEM_MODE
            ];
            Assert.isTrue(indicator.Source_Definition__c.contains('sum'), 'A sum');
            Assert.isTrue(
                indicator.Source_Definition__c.contains('Target_Value__c'),
                'Of the starter field'
            );
        }
    }

    @IsTest
    static void aMissingOrWrongChoiceAndAnUnknownStarterAreRefused() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            useTestStarters();
            Fixture fixture = new Fixture();

            Test.startTest();
            String missing = refusal(fixture, fixture.starter('sessions', null));
            String wrongObject = refusal(fixture, fixture.starter('sessions', fixture.modelId));
            String notAnId = refusal(fixture, fixture.starter('sessions', 'nonsense'));
            String unknown = refusal(fixture, fixture.starter('nope', null));
            String unavailable = refusal(fixture, fixture.starter('missing', null));
            Test.stopTest();

            String choose = BarnHelp.text('LogicModels', 'LogicModels_Starter_ChooseRecord');
            String gone = BarnHelp.text('LogicModels', 'LogicModels_Starter_Unavailable');
            Assert.areEqual(choose, missing, 'A required choice');
            Assert.areEqual(choose, wrongObject, 'A record of another object');
            Assert.areEqual(choose, notAnId, 'Not a record identifier');
            Assert.areEqual(gone, unknown, 'Not a starter');
            Assert.areEqual(gone, unavailable, 'Its object is not here');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Saved_Query__c WITH SYSTEM_MODE],
                'No query written'
            );
        }
    }

    @IsTest
    static void theShippedStartersNameOnlyObjectsByApiName() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Test.startTest();
            List<Map<String, Object>> offered = IndicatorStarterService.available();
            Test.stopTest();

            Set<String> keys = new Set<String>();
            for (Map<String, Object> starter : offered) {
                keys.add((String) starter.get('value'));
            }
            Assert.areEqual(
                NamespaceUtil.packagedObjectType('Service_Delivery__c') != null,
                keys.contains('servicesDelivered'),
                'Offered exactly when Programs is installed'
            );
            Assert.areEqual(
                NamespaceUtil.packagedObjectType('Grant__c') != null,
                keys.contains('grantsAwarded'),
                'Offered exactly when Funders is installed'
            );
        }
    }
}
