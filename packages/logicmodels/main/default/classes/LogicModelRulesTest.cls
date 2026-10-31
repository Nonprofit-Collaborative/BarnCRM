/**
 * The Logic Models records and their rules (canonical model Sections 29ZC to 29ZG): one model per
 * scope (R-LM1), the program named by identifier (R-LM2), parts deleted with their model (R-LM3),
 * outcome terms (R-LE1), indicators kept on outputs and outcomes (R-LE2, R-IN1), arrows within one
 * model and forward only (R-LL1, R-LL2), period dates (R-IP1), and what each permission set may do.
 */
@IsTest(
    testFor='ApexClass:LogicModelScope, ApexClass:LogicModelScopeHandler, ApexClass:LogicModelIntegritySelector, ApexTrigger:LogicModelTrigger'
)
private class LogicModelRulesTest {
    private static final String ADMIN = 'Logic_Models_Admin';

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
        TestUsers.standardUserWith(
            'Staffer',
            new List<String>{ 'BarnCRM_Staff', 'Logic_Models_Staff' }
        );
        TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
        );
    }

    private static User staffer() {
        return TestUsers.standardUserWith(
            'Staffer',
            new List<String>{ 'BarnCRM_Staff', 'Logic_Models_Staff' }
        );
    }

    private static User reader() {
        return TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Logic_Models_Read_Only' }
        );
    }

    private static Logic_Model__c newModel(String name, String programId) {
        return new Logic_Model__c(Name = name, Program_Id__c = programId);
    }

    private static Logic_Model_Element__c newElement(
        Id modelId,
        String name,
        String type,
        String term
    ) {
        return new Logic_Model_Element__c(
            Logic_Model__c = modelId,
            Name = name,
            Type__c = type,
            Outcome_Term__c = term
        );
    }

    /** A model with one part in each of five columns, keyed by type. */
    private static Map<String, Logic_Model_Element__c> chain(Id modelId) {
        Map<String, Logic_Model_Element__c> byType = new Map<String, Logic_Model_Element__c>{
            'Input' => newElement(modelId, 'Two tutors', 'Input', null),
            'Activity' => newElement(modelId, 'Weekly sessions', 'Activity', null),
            'Output' => newElement(modelId, 'Sessions held', 'Output', null),
            'Outcome' => newElement(modelId, 'Reads at home', 'Outcome', 'Short Term'),
            'Impact' => newElement(modelId, 'Every child reads', 'Impact', null)
        };
        insert byType.values();
        return byType;
    }

    private static String firstError(Database.SaveResult result) {
        return result.isSuccess() ? null : result.getErrors()[0].getMessage();
    }

    @IsTest
    static void theOrganizationHasOneModelInBulkAndAfter() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Test.startTest();
            List<Database.SaveResult> together = Database.insert(
                new List<Logic_Model__c>{ newModel('First', null), newModel('Second', ' ') },
                false
            );
            Database.SaveResult later = Database.insert(newModel('Third', null), false);
            Test.stopTest();

            Assert.isTrue(together[0].isSuccess(), 'The first is the organization\'s model');
            Assert.areEqual(
                Label.LogicModels_Scope_OrganizationTaken,
                firstError(together[1]),
                'A second in the same save is refused'
            );
            Assert.areEqual(
                Label.LogicModels_Scope_OrganizationTaken,
                firstError(later),
                'And so is one saved later'
            );
            Logic_Model__c saved = [
                SELECT Program_Id__c, Scope_Key__c
                FROM Logic_Model__c
                WITH USER_MODE
            ];
            Assert.areEqual(LogicModelScope.ORGANIZATION, saved.Scope_Key__c, 'Keyed');
            Assert.isNull(saved.Program_Id__c, 'No program');
        }
    }

    @IsTest
    static void eachProgramHasOneModelNamedByItsFullIdentifier() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            // Any record identifiers stand in for programs: Logic Models never reads the program.
            String tutoring = UserInfo.getUserId();
            String pantry = UserInfo.getOrganizationId();
            insert new List<Logic_Model__c>{
                newModel('Organization', null),
                newModel('Tutoring', tutoring.left(15))
            };

            Test.startTest();
            Database.SaveResult again = Database.insert(newModel('Tutoring 2', tutoring), false);
            Database.SaveResult other = Database.insert(newModel('Pantry', pantry), false);
            Database.SaveResult bad = Database.insert(newModel('Typed', 'not a program'), false);
            Test.stopTest();

            Assert.areEqual(
                Label.LogicModels_Scope_ProgramTaken,
                firstError(again),
                'The program has a model, saved under its short identifier'
            );
            Assert.isTrue(other.isSuccess(), 'Another program may have its own');
            Assert.areEqual(Label.LogicModels_Scope_BadProgram, firstError(bad), 'Refused');
            Logic_Model__c saved = [
                SELECT Program_Id__c, Scope_Key__c
                FROM Logic_Model__c
                WHERE Name = 'Tutoring'
                WITH USER_MODE
            ];
            Assert.areEqual(tutoring, saved.Program_Id__c, 'Stored as 18 characters');
            Assert.areEqual(tutoring, saved.Scope_Key__c, 'And keyed by it');
        }
    }

    @IsTest
    static void aModelKeepsItsScopeAndCannotMoveOntoATakenOne() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Logic_Model__c organization = newModel('Organization', null);
            Logic_Model__c tutoring = newModel('Tutoring', UserInfo.getUserId());
            insert new List<Logic_Model__c>{ organization, tutoring };

            Test.startTest();
            organization.Name = 'Our Theory of Change';
            Database.SaveResult renamed = Database.update(organization, false);
            tutoring.Program_Id__c = null;
            Database.SaveResult moved = Database.update(tutoring, false);
            Test.stopTest();

            Assert.isTrue(renamed.isSuccess(), 'Keeping its own scope is fine');
            Assert.areEqual(
                Label.LogicModels_Scope_OrganizationTaken,
                firstError(moved),
                'Moving onto the organization, which has a model, is refused'
            );
        }
    }

    @IsTest
    static void anOutcomeHasATermAndNothingElseDoes() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Logic_Model__c model = newModel('Model', null);
            insert model;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Logic_Model_Element__c>{
                    newElement(model.Id, 'No term', 'Outcome', null),
                    newElement(model.Id, 'Termed activity', 'Activity', 'Long Term'),
                    newElement(model.Id, 'Fine', 'Outcome', 'Long Term')
                },
                false
            );
            Test.stopTest();

            Assert.isFalse(results[0].isSuccess(), 'An outcome needs a term');
            Assert.isFalse(results[1].isSuccess(), 'Only an outcome has one');
            Assert.isTrue(results[2].isSuccess(), 'An outcome with a term is saved');
            Assert.areEqual(
                6,
                [
                    SELECT Stage_Rank__c
                    FROM Logic_Model_Element__c
                    WHERE Id = :results[2].getId()
                    WITH USER_MODE
                ]
                .Stage_Rank__c,
                'A long term outcome ranks sixth'
            );
        }
    }

    @IsTest
    static void arrowsGoForwardWithinOneModel() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Logic_Model__c model = newModel('Model', null);
            Logic_Model__c other = newModel('Other', UserInfo.getUserId());
            insert new List<Logic_Model__c>{ model, other };
            Map<String, Logic_Model_Element__c> parts = chain(model.Id);
            Logic_Model_Element__c elsewhere = newElement(other.Id, 'Elsewhere', 'Output', null);
            insert elsewhere;

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Logic_Model_Link__c>{
                    link(model.Id, parts.get('Input'), parts.get('Activity')),
                    link(model.Id, parts.get('Activity'), parts.get('Outcome')),
                    link(model.Id, parts.get('Outcome'), parts.get('Output')),
                    link(model.Id, parts.get('Output'), parts.get('Output')),
                    link(model.Id, parts.get('Activity'), elsewhere),
                    new Logic_Model_Link__c(
                        Logic_Model__c = model.Id,
                        From_Element__c = parts.get('Input').Id
                    )
                },
                false
            );
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'Input to activity');
            Assert.isTrue(results[1].isSuccess(), 'Skipping a column is fine');
            Assert.isFalse(results[2].isSuccess(), 'Never backwards');
            Assert.isFalse(results[3].isSuccess(), 'Never within one column');
            Assert.isFalse(results[4].isSuccess(), 'Never into another model');
            Assert.isFalse(results[5].isSuccess(), 'Never with an end missing');
        }
    }

    private static Logic_Model_Link__c link(
        Id modelId,
        Logic_Model_Element__c fromPart,
        Logic_Model_Element__c toPart
    ) {
        return new Logic_Model_Link__c(
            Logic_Model__c = modelId,
            From_Element__c = fromPart.Id,
            To_Element__c = toPart.Id,
            Assumption__c = 'Because it does.'
        );
    }

    @IsTest
    static void indicatorsStayOnOutputsAndOutcomes() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Logic_Model__c model = newModel('Model', null);
            insert model;
            Map<String, Logic_Model_Element__c> parts = chain(model.Id);

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Indicator__c>{
                    new Indicator__c(Element__c = parts.get('Output').Id, Name = 'Sessions'),
                    new Indicator__c(Element__c = parts.get('Outcome').Id, Name = 'Readers'),
                    new Indicator__c(Element__c = parts.get('Activity').Id, Name = 'Planned'),
                    new Indicator__c(Element__c = parts.get('Impact').Id, Name = 'Literacy')
                },
                false
            );
            Logic_Model_Element__c output = parts.get('Output');
            output.Type__c = 'Activity';
            Database.SaveResult retyped = Database.update(output, false);
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'On an output');
            Assert.isTrue(results[1].isSuccess(), 'On an outcome');
            Assert.isFalse(results[2].isSuccess(), 'Never on an activity');
            Assert.isFalse(results[3].isSuccess(), 'Never on the impact');
            Assert.isFalse(retyped.isSuccess(), 'A measured output cannot become an activity');
            Indicator__c saved = [
                SELECT Better_When__c
                FROM Indicator__c
                WHERE Id = :results[0].getId()
                WITH USER_MODE
            ];
            Assert.areEqual('Higher', saved.Better_When__c, 'Higher is better by default');
        }
    }

    @IsTest
    static void aPeriodEndsOnOrAfterItStartsAndGoesWithItsModel() {
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Logic_Model__c model = newModel('Model', null);
            insert model;
            Map<String, Logic_Model_Element__c> parts = chain(model.Id);
            insert link(model.Id, parts.get('Input'), parts.get('Activity'));
            Indicator__c readers = new Indicator__c(
                Element__c = parts.get('Outcome').Id,
                Name = 'Readers'
            );
            insert readers;
            Date start = Date.newInstance(2026, 1, 1);

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Indicator_Period__c>{
                    period(readers.Id, '2026 Q1', start, start.addDays(89)),
                    period(readers.Id, 'Backwards', start, start.addDays(-1))
                },
                false
            );
            delete model;
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'A quarter');
            Assert.isFalse(results[1].isSuccess(), 'An end before the start');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Logic_Model_Element__c WITH USER_MODE] +
                    [SELECT COUNT() FROM Logic_Model_Link__c WITH USER_MODE] +
                    [SELECT COUNT() FROM Indicator__c WITH USER_MODE] +
                    [SELECT COUNT() FROM Indicator_Period__c WITH USER_MODE],
                'Its parts, arrows, indicators and periods went with the model'
            );
        }
    }

    private static Indicator_Period__c period(Id indicatorId, String name, Date start, Date last) {
        return new Indicator_Period__c(
            Indicator__c = indicatorId,
            Name = name,
            Start_Date__c = start,
            End_Date__c = last,
            Target_Value__c = 30,
            Result_Value__c = 20
        );
    }

    @IsTest
    static void staffBuildModelsAndNeverDeleteOneAndReadersOnlyLook() {
        Logic_Model__c model = newModel('Model', null);
        Logic_Model_Element__c part;
        System.runAs(staffer()) {
            insert as user model;
            part = newElement(model.Id, 'Two tutors', 'Input', null);
            insert as user part;
        }

        Test.startTest();
        Boolean staffDeletedModel = true;
        System.runAs(staffer()) {
            delete as user part;
            try {
                delete as user model;
            } catch (Exception e) {
                // User mode refuses the delete: no delete permission on a whole model.
                staffDeletedModel = false;
            }
        }
        Boolean readerCreated = true;
        System.runAs(reader()) {
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Logic_Model__c WITH USER_MODE],
                'A reader sees the model'
            );
            try {
                insert as user newElement(model.Id, 'More', 'Input', null);
            } catch (Exception e) {
                // User mode refuses the insert: Read Only has no create permission.
                readerCreated = false;
            }
        }
        Test.stopTest();

        Assert.isFalse(staffDeletedModel, 'Staff never delete a whole model');
        Assert.isFalse(readerCreated, 'A reader changes nothing');
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Logic_Model_Element__c WITH USER_MODE],
                'Staff removed the part they added'
            );
        }
    }
}
