/**
 * The Logic Model Builder's server side (L-01, L-02): building a model part by part, arrows with
 * their assumptions, one arrow per pair (R-LL3), indicators and periods with one row per period
 * (R-IP2), deleting a part with its arrows and indicators (R-LE3), whose model it is (R-LM2), and
 * what a reader may do.
 */
@IsTest(testFor='ApexClass:LogicModelBuilderController, ApexClass:LogicModelService')
private class LogicModelBuilderControllerTest {
    private static final String ADMIN = 'Logic_Models_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
        );
    }

    private static Id newModel() {
        Logic_Model__c model = new Logic_Model__c(Name = 'Reading Program Model');
        insert as user model;
        return model.Id;
    }

    private static Map<String, Object> addPart(Id modelId, String name, String type, String term) {
        return LogicModelBuilderController.saveElement(
            JSON.serialize(
                new Map<String, Object>{
                    'modelId' => modelId,
                    'name' => name,
                    'type' => type,
                    'term' => term,
                    'sortOrder' => 10
                }
            )
        );
    }

    private static Id idOf(Map<String, Object> model, String listKey, String name) {
        for (Object row : (List<Object>) model.get(listKey)) {
            Map<String, Object> fields = (Map<String, Object>) row;
            if (fields.get('name') == name) {
                return (Id) fields.get('id');
            }
        }
        return null;
    }

    private static Integer sizeOf(Map<String, Object> model, String listKey) {
        return ((List<Object>) model.get(listKey)).size();
    }

    private static String refusal(Callable call) {
        try {
            call.call('run', null);
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    /** One builder call, so a refusal can be caught and read. */
    private class Save implements Callable {
        private final String kind;
        private final String payload;

        Save(String kind, Map<String, Object> fields) {
            this.kind = kind;
            this.payload = JSON.serialize(fields);
        }

        public Object call(String action, Map<String, Object> args) {
            if (kind == 'link') {
                return LogicModelBuilderController.saveLink(payload);
            }
            if (kind == 'period') {
                return LogicModelBuilderController.savePeriod(payload);
            }
            return LogicModelBuilderController.saveElement(payload);
        }
    }

    @IsTest
    static void aModelIsBuiltPartByPartWithArrowsAndAssumptions() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Id modelId = newModel();

            Test.startTest();
            addPart(modelId, 'Two tutors', 'Input', null);
            addPart(modelId, 'Weekly sessions', 'Activity', null);
            Map<String, Object> model = addPart(modelId, 'Reads at home', 'Outcome', 'Short Term');
            Id tutors = idOf(model, 'elements', 'Two tutors');
            Id sessions = idOf(model, 'elements', 'Weekly sessions');
            Id reads = idOf(model, 'elements', 'Reads at home');
            Map<String, Object> link = new Map<String, Object>{
                'modelId' => modelId,
                'fromId' => tutors,
                'toId' => sessions,
                'assumption' => 'Tutors run the sessions.'
            };
            model = LogicModelBuilderController.saveLink(JSON.serialize(link));
            String again = refusal(new Save('link', link));
            String backwards = refusal(
                new Save(
                    'link',
                    new Map<String, Object>{
                        'modelId' => modelId,
                        'fromId' => reads,
                        'toId' => tutors
                    }
                )
            );
            Id linkId = (Id) ((Map<String, Object>) ((List<Object>) model.get('links'))[0])
                .get('id');
            model = LogicModelBuilderController.saveLink(
                JSON.serialize(
                    new Map<String, Object>{ 'id' => linkId, 'assumption' => 'Changed.' }
                )
            );
            model = LogicModelBuilderController.saveOrder(
                modelId,
                JSON.serialize(
                    new List<Object>{ new Map<String, Object>{ 'id' => tutors, 'sortOrder' => 5 } }
                )
            );
            Test.stopTest();

            Assert.areEqual(3, sizeOf(model, 'elements'), 'Three parts');
            Assert.areEqual(1, sizeOf(model, 'links'), 'One arrow');
            Assert.areEqual(Label.LogicModels_Builder_ArrowExists, again, 'One arrow per pair');
            Assert.isNotNull(backwards, 'Backwards is refused by the platform, with its message');
            Map<String, Object> saved = (Map<String, Object>) ((List<Object>) model.get(
                'links'
            ))[0];
            Assert.areEqual('Changed.', saved.get('assumption'), 'The assumption changed');
            Assert.areEqual(true, model.get('canEdit'), 'An admin builds');
            Assert.areEqual(true, model.get('canDelete'), 'And deletes');
            Assert.isNull(model.get('programId'), 'The organization\'s model');
        }
    }

    @IsTest
    static void aColumnChangeThatWouldTurnAnArrowBackwardIsRefusedByName() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Id modelId = newModel();
            addPart(modelId, 'Two tutors', 'Input', null);
            Map<String, Object> model = addPart(modelId, 'Weekly sessions', 'Activity', null);
            Id tutors = idOf(model, 'elements', 'Two tutors');
            Id sessions = idOf(model, 'elements', 'Weekly sessions');
            LogicModelBuilderController.saveLink(
                JSON.serialize(
                    new Map<String, Object>{
                        'modelId' => modelId,
                        'fromId' => tutors,
                        'toId' => sessions
                    }
                )
            );

            String refused = refusal(
                new Save(
                    'element',
                    new Map<String, Object>{
                        'id' => sessions,
                        'name' => 'Weekly sessions',
                        'type' => 'Input'
                    }
                )
            );
            String allowed = refusal(
                new Save(
                    'element',
                    new Map<String, Object>{
                        'id' => sessions,
                        'name' => 'Weekly sessions',
                        'type' => 'Outcome',
                        'term' => 'Long Term'
                    }
                )
            );

            Assert.areEqual(
                String.format(
                    Label.LogicModels_Builder_BackwardArrows,
                    new List<String>{
                        String.format(
                            Label.LogicModels_Builder_ArrowPair,
                            new List<String>{ 'Two tutors', 'Weekly sessions' }
                        )
                    }
                ),
                refused,
                'R-LL2: the move is refused and the arrow named.'
            );
            Assert.isNull(allowed, 'A move that keeps every arrow forward saves.');
            Assert.areEqual(
                6,
                [SELECT Stage_Rank__c FROM Logic_Model_Element__c WHERE Id = :sessions]
                .Stage_Rank__c,
                'The Apex rank matches the formula.'
            );
            Assert.areEqual(4, LogicModelService.rankFor('Outcome', null));
            Assert.areEqual(0, LogicModelService.rankFor('Nothing', null));
        }
    }

    @IsTest
    static void indicatorsHoldATargetAndResultPerPeriod() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Id modelId = newModel();
            Id reads = idOf(
                addPart(modelId, 'Reads at home', 'Outcome', 'Short Term'),
                'elements',
                'Reads at home'
            );

            Test.startTest();
            Map<String, Object> model = LogicModelBuilderController.saveIndicator(
                JSON.serialize(
                    new Map<String, Object>{
                        'elementId' => reads,
                        'name' => 'Students reading daily',
                        'unit' => 'students',
                        'baselineValue' => 10,
                        'baselineDate' => '2025-12-31'
                    }
                )
            );
            Id indicatorId = idOf(model, 'indicators', 'Students reading daily');
            Map<String, Object> quarter = new Map<String, Object>{
                'indicatorId' => indicatorId,
                'name' => '2026 Q1',
                'startDate' => '2026-01-01',
                'endDate' => '2026-03-31',
                'targetValue' => 30,
                'resultValue' => 20
            };
            model = LogicModelBuilderController.savePeriod(JSON.serialize(quarter));
            String twice = refusal(new Save('period', quarter));
            model = LogicModelBuilderController.saveIndicator(
                JSON.serialize(
                    new Map<String, Object>{
                        'id' => indicatorId,
                        'name' => 'Students reading daily',
                        'betterWhen' => 'Lower'
                    }
                )
            );
            Test.stopTest();

            Map<String, Object> indicator = (Map<String, Object>) ((List<Object>) model.get(
                'indicators'
            ))[0];
            List<Object> periods = (List<Object>) indicator.get('periods');
            Assert.areEqual(1, periods.size(), 'One period');
            Map<String, Object> period = (Map<String, Object>) periods[0];
            Assert.areEqual(Date.newInstance(2026, 1, 1), period.get('startDate'), 'Its start');
            Assert.areEqual(20, (Decimal) period.get('resultValue'), 'Its result');
            Assert.areEqual(Label.LogicModels_Builder_PeriodExists, twice, 'Same dates refused');
            Assert.areEqual('Lower', indicator.get('betterWhen'), 'Which way is better changed');
        }
    }

    @IsTest
    static void deletingAPartTakesItsArrowsAndIndicators() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Id modelId = newModel();
            addPart(modelId, 'Sessions held', 'Output', null);
            Map<String, Object> model = addPart(modelId, 'Reads more', 'Outcome', 'Long Term');
            Id held = idOf(model, 'elements', 'Sessions held');
            Id reads = idOf(model, 'elements', 'Reads more');
            LogicModelBuilderController.saveLink(
                JSON.serialize(
                    new Map<String, Object>{
                        'modelId' => modelId,
                        'fromId' => held,
                        'toId' => reads
                    }
                )
            );
            model = LogicModelBuilderController.saveIndicator(
                JSON.serialize(new Map<String, Object>{ 'elementId' => held, 'name' => 'Held' })
            );
            Id indicatorId = idOf(model, 'indicators', 'Held');
            model = LogicModelBuilderController.savePeriod(
                JSON.serialize(
                    new Map<String, Object>{
                        'indicatorId' => indicatorId,
                        'name' => '2026',
                        'startDate' => '2026-01-01',
                        'endDate' => '2026-12-31'
                    }
                )
            );
            Id periodId = (Id) ((Map<String, Object>) ((List<Object>) ((Map<String, Object>) ((List<Object>) model.get(
                        'indicators'
                    ))[0])
                    .get('periods'))[0])
                .get('id');

            Test.startTest();
            LogicModelBuilderController.remove(periodId);
            model = LogicModelBuilderController.remove(held);
            Test.stopTest();

            Assert.areEqual(1, sizeOf(model, 'elements'), 'The part is gone');
            Assert.areEqual(0, sizeOf(model, 'links'), 'With its arrow');
            Assert.areEqual(0, sizeOf(model, 'indicators'), 'And its indicator');
        }
    }

    @IsTest
    static void aModelIsTheOrganizationsUnlessGivenAProgram() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Id modelId = newModel();

            Test.startTest();
            List<Map<String, String>> programs = LogicModelBuilderController.getPrograms();
            String notAProgram;
            try {
                LogicModelBuilderController.setProgram(modelId, UserInfo.getUserId());
            } catch (AuraHandledException e) {
                notAProgram = e.getMessage();
            }
            Map<String, Object> model = LogicModelBuilderController.setProgram(modelId, null);
            Test.stopTest();

            Assert.isNotNull(programs, 'A list, empty without Programs');
            Assert.areEqual(
                Label.LogicModels_Scope_BadProgram,
                notAProgram,
                'A person is not a program'
            );
            Assert.isNull(model.get('programId'), 'Still the organization\'s');
            Assert.areEqual(false, model.get('programMissing'), 'Nothing missing');
        }
    }

    @IsTest
    static void aReaderLooksAndChangesNothing() {
        Id modelId;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            modelId = newModel();
        }

        Test.startTest();
        Map<String, Object> model;
        String refused;
        System.runAs(TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
        )) {
            model = LogicModelBuilderController.getModel(modelId);
            refused = refusal(
                new Save(
                    'element',
                    new Map<String, Object>{
                        'modelId' => modelId,
                        'name' => 'More',
                        'type' => 'Input'
                    }
                )
            );
        }
        Test.stopTest();

        Assert.areEqual(false, model.get('canEdit'), 'No editing');
        Assert.isNotNull(refused, 'A save is refused');
    }

    @IsTest
    static void anUnexpectedFailureIsLoggedAndShownPlainly() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Test.startTest();
            AuraHandledException shown = LogicModelBuilderController.handled(
                new System.MathException('boom')
            );
            String missing;
            try {
                LogicModelBuilderController.getModel(UserInfo.getUserId());
            } catch (AuraHandledException e) {
                missing = e.getMessage();
            }
            String unreadable;
            try {
                LogicModelBuilderController.saveElement('[1]');
            } catch (AuraHandledException e) {
                unreadable = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.LogicModels_Builder_ActionFailed, shown.getMessage(), 'Plain');
            Assert.areEqual(Label.LogicModels_Builder_NotFound, missing, 'Not a model');
            Assert.areEqual(Label.LogicModels_Builder_ActionFailed, unreadable, 'Not an object');
        }
    }
}
