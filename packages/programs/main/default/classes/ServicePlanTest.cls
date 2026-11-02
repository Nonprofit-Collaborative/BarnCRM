/**
 * Participant service plans (P-10, canonical model 29ZA2 and 29ZA3): the Service Plan panel's
 * reads and writes, the closed and completed dates (R-GL2, R-GS1), reviews (R-GL3), who may write
 * (R-GL4), goals seen as their enrollment is (R-GL1), notes about a goal (R-CN5), the optional
 * Logic Models outcome (R-GL5) and erasure (R-GL6).
 */
@IsTest(
    testFor='ApexClass:ServicePlanController, ApexClass:ServicePlanService, ApexClass:ServicePlanDatesHandler'
)
private class ServicePlanTest {
    private static final String ADMIN = 'Programs_Admin';
    private static final List<String> STAFF = new List<String>{ 'BarnCRM_Staff', 'Programs_Staff' };
    private static final List<String> READER = new List<String>{
        'BarnCRM_Read_Only',
        'Programs_Read_Only'
    };

    // standardUserWith inserts a new user on every call, so each test keeps the one it made.
    private static User plannerUser;
    private static User readerUser;

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(ADMIN);
    }

    private static User planner() {
        if (plannerUser == null) {
            plannerUser = TestUsers.standardUserWith('Planner', STAFF);
        }
        return plannerUser;
    }

    private static User reader() {
        if (readerUser == null) {
            readerUser = TestUsers.standardUserWith('Reader', READER);
        }
        return readerUser;
    }

    /** A person enrolled in a program, created by the admin and shared with whoever is named. */
    private static Enrollment__c enrollment(List<Id> sharedWith) {
        BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        TestDataFactory.saveSettings(settings);
        Contact person = HouseholdTestDataFactory.newContact('Pat', 'Rivera');
        insert person;
        Program__c pantry = new Program__c(Name = 'Pantry');
        insert pantry;
        Enrollment__c enrolled = new Enrollment__c(Program__c = pantry.Id, Contact__c = person.Id);
        insert enrolled;
        // As the Private preset would have it, whatever this org's group holds: only the
        // people named here see the enrollment, beside its owner and Programs Admin.
        delete [
            SELECT Id
            FROM Enrollment__Share
            WHERE
                ParentId = :enrolled.Id
                AND RowCause = :Schema.Enrollment__Share.RowCause.Programs_Participants__c
            WITH SYSTEM_MODE
        ];
        List<Enrollment__Share> shares = new List<Enrollment__Share>();
        for (Id userId : sharedWith) {
            shares.add(
                new Enrollment__Share(
                    ParentId = enrolled.Id,
                    UserOrGroupId = userId,
                    AccessLevel = 'Edit',
                    RowCause = Schema.Enrollment__Share.RowCause.Manual
                )
            );
        }
        insert shares;
        return enrolled;
    }

    private static Enrollment__c sharedEnrollment() {
        Enrollment__c enrolled;
        List<Id> sharedWith = new List<Id>{ planner().Id, reader().Id };
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrolled = enrollment(sharedWith);
        }
        return enrolled;
    }

    private static Map<String, Object> goalJson(Id enrollmentId, String name) {
        return new Map<String, Object>{
            'enrollmentId' => enrollmentId,
            'name' => name,
            'description' => 'Signed lease',
            'status' => 'In Progress'
        };
    }

    private static List<Object> goalsOf(Map<String, Object> plan) {
        return (List<Object>) plan.get('goals');
    }

    @IsTest
    static void staffBuildAPlanWithGoalsAndSteps() {
        Enrollment__c enrolled = sharedEnrollment();
        Map<String, Object> plan;
        Test.startTest();
        System.runAs(planner()) {
            Map<String, Object> goal = goalJson(enrolled.Id, 'Find stable housing');
            goal.put('targetDate', '2027-03-01');
            goal.put('assignedToId', UserInfo.getUserId());
            plan = ServicePlanController.saveGoal(JSON.serialize(goal));
            Id goalId = (Id) ((Map<String, Object>) goalsOf(plan)[0]).get('id');
            ServicePlanController.saveStep(
                JSON.serialize(new Map<String, Object>{ 'goalId' => goalId, 'name' => 'Apply' })
            );
            plan = ServicePlanController.saveStep(
                JSON.serialize(
                    new Map<String, Object>{
                        'goalId' => goalId,
                        'name' => 'Visit',
                        'targetDate' => '2027-01-10'
                    }
                )
            );
            goal.put('id', goalId);
            goal.put('name', 'Find a home');
            plan = ServicePlanController.saveGoal(JSON.serialize(goal));
        }
        Test.stopTest();

        Assert.isTrue((Boolean) plan.get('canEdit'), 'Staff may add and change goals.');
        Assert.areEqual('Pat Rivera', plan.get('personName'));
        Assert.areEqual('Pantry', plan.get('programName'));
        Assert.areEqual(1, goalsOf(plan).size(), 'One goal, changed in place.');
        Map<String, Object> goal = (Map<String, Object>) goalsOf(plan)[0];
        Assert.areEqual('Find a home', goal.get('name'));
        Assert.areEqual('In Progress', goal.get('status'));
        Assert.areEqual(Date.newInstance(2027, 3, 1), goal.get('targetDate'));
        List<Object> steps = (List<Object>) goal.get('steps');
        Assert.areEqual(2, steps.size(), 'Both steps.');
        Assert.areEqual(
            'Visit',
            ((Map<String, Object>) steps[0]).get('name'),
            'A dated step comes first.'
        );
        Assert.isNotNull(plan.get('outcomesAvailable'), 'Says whether outcomes can be linked.');
    }

    @IsTest
    static void closingAGoalOrFinishingAStepStampsTheDateAndReopeningClearsIt() {
        Enrollment__c enrolled = sharedEnrollment();
        User staff = planner();
        Date today;
        Goal__c goal;
        Goal_Step__c step;
        Test.startTest();
        System.runAs(staff) {
            today = Date.today();
            goal = new Goal__c(Enrollment__c = enrolled.Id, Name = 'Open a bank account');
            insert goal;
            step = new Goal_Step__c(Goal__c = goal.Id, Name = 'Bring ID', Status__c = 'Done');
            insert step;
            update new Goal__c(Id = goal.Id, Status__c = 'Achieved');
        }
        Goal__c closed = [SELECT Closed_Date__c FROM Goal__c WHERE Id = :goal.Id WITH SYSTEM_MODE];
        Goal_Step__c done = [
            SELECT Completed_Date__c
            FROM Goal_Step__c
            WHERE Id = :step.Id
            WITH SYSTEM_MODE
        ];
        System.runAs(staff) {
            update new Goal__c(Id = goal.Id, Status__c = 'In Progress');
            update new Goal_Step__c(Id = step.Id, Status__c = 'In Progress');
        }
        Test.stopTest();

        Assert.areEqual(today, closed.Closed_Date__c, 'Closed today.');
        Assert.areEqual(today, done.Completed_Date__c, 'Done today.');
        Assert.isNull(
            [SELECT Closed_Date__c FROM Goal__c WHERE Id = :goal.Id WITH SYSTEM_MODE]
            .Closed_Date__c,
            'Reopened, so no closed date.'
        );
        Assert.isNull(
            [SELECT Completed_Date__c FROM Goal_Step__c WHERE Id = :step.Id WITH SYSTEM_MODE]
            .Completed_Date__c,
            'Reopened, so no completed date.'
        );
    }

    @IsTest
    static void aTypedClosedDateIsKept() {
        Enrollment__c enrolled = sharedEnrollment();
        Date typed = Date.newInstance(2025, 6, 30);
        Test.startTest();
        System.runAs(planner()) {
            insert new Goal__c(
                Enrollment__c = enrolled.Id,
                Name = 'Graduate',
                Status__c = 'Achieved',
                Closed_Date__c = typed
            );
        }
        Test.stopTest();
        Assert.areEqual(
            typed,
            [SELECT Closed_Date__c FROM Goal__c WITH SYSTEM_MODE].Closed_Date__c
        );
    }

    @IsTest
    static void markReviewedSetsTodayAndTheNextReview() {
        Enrollment__c enrolled = sharedEnrollment();
        User staff = planner();
        Date today;
        Map<String, Object> plan;
        String refusal;
        Test.startTest();
        System.runAs(staff) {
            today = Date.today();
            Goal__c goal = new Goal__c(Enrollment__c = enrolled.Id, Name = 'Pass the test');
            insert goal;
            plan = ServicePlanController.markReviewed(goal.Id, today.addMonths(3));
            try {
                ServicePlanController.markReviewed(goal.Id, today.addDays(-1));
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
        }
        Test.stopTest();

        Map<String, Object> goal = (Map<String, Object>) goalsOf(plan)[0];
        Assert.areEqual(today, goal.get('lastReviewDate'), 'Reviewed today.');
        Assert.areEqual(today.addMonths(3), goal.get('nextReviewDate'));
        Assert.areEqual(
            Label.Programs_Plan_NextReviewPast,
            refusal,
            'A past next review is refused.'
        );
    }

    @IsTest
    static void aGoalNeedsAName() {
        Enrollment__c enrolled = sharedEnrollment();
        String refusal;
        Test.startTest();
        System.runAs(planner()) {
            try {
                ServicePlanController.saveGoal(JSON.serialize(goalJson(enrolled.Id, '  ')));
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
        }
        Test.stopTest();
        Assert.areEqual(Label.Programs_Plan_NameRequired, refusal);
    }

    @IsTest
    static void staffCannotDeleteAGoalAndReadOnlyCannotChangeOne() {
        Enrollment__c enrolled = sharedEnrollment();
        Goal__c goal = new Goal__c(Enrollment__c = enrolled.Id, Name = 'Keep a job');
        System.runAs(planner()) {
            insert goal;
        }
        Test.startTest();
        Boolean staffDeleted = true;
        System.runAs(planner()) {
            staffDeleted = Database.delete(
                    new List<Goal__c>{ goal },
                    false,
                    AccessLevel.USER_MODE
                )[0]
                .isSuccess();
        }
        Map<String, Object> readerPlan;
        String readerRefusal;
        System.runAs(reader()) {
            readerPlan = ServicePlanController.getPlan(enrolled.Id);
            try {
                ServicePlanController.saveGoal(JSON.serialize(goalJson(enrolled.Id, 'Sneak')));
            } catch (AuraHandledException refused) {
                readerRefusal = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.isFalse(staffDeleted, 'Staff never delete a goal (R-GL4).');
        Assert.isFalse((Boolean) readerPlan.get('canEdit'), 'Read Only sees but does not change.');
        Assert.areEqual(1, goalsOf(readerPlan).size(), 'Read Only sees the goal.');
        Assert.isNotNull(readerRefusal, 'Read Only cannot add a goal.');
        Assert.areEqual(1, [SELECT COUNT() FROM Goal__c WITH SYSTEM_MODE], 'Nothing added.');
    }

    @IsTest
    static void aGoalIsSeenOnlyByThoseWhoSeeItsEnrollment() {
        Enrollment__c enrolled = sharedEnrollment();
        System.runAs(planner()) {
            insert new Goal__c(Enrollment__c = enrolled.Id, Name = 'Private goal');
        }
        Test.startTest();
        Integer seen;
        String refusal;
        System.runAs(TestUsers.standardUserWith('Outsider', STAFF)) {
            seen = [SELECT COUNT() FROM Goal__c WITH USER_MODE];
            try {
                ServicePlanController.getPlan(enrolled.Id);
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
        }
        Test.stopTest();
        Assert.areEqual(0, seen, 'Staff the enrollment is not shared with see no goal (R-GL1).');
        Assert.areEqual(Label.Programs_Plan_NotFound, refusal);
    }

    @IsTest
    static void notesAboutAGoalAreListedUnderItAndMustBeOnItsEnrollment() {
        Enrollment__c enrolled = sharedEnrollment();
        Enrollment__c other;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            Program__c tutoring = new Program__c(Name = 'Tutoring');
            insert tutoring;
            other = new Enrollment__c(Program__c = tutoring.Id, Contact__c = enrolled.Contact__c);
            insert other;
        }
        Map<String, Object> plan;
        Database.SaveResult wrongEnrollment;
        Test.startTest();
        System.runAs(planner()) {
            Goal__c goal = new Goal__c(Enrollment__c = enrolled.Id, Name = 'Find housing');
            insert goal;
            List<Case_Note__c> notes = new List<Case_Note__c>();
            for (Integer i = 0; i < 4; i++) {
                notes.add(
                    new Case_Note__c(
                        Enrollment__c = enrolled.Id,
                        Goal__c = goal.Id,
                        Subject__c = 'Visit ' + i,
                        Note_Date__c = Date.today().addDays(-i)
                    )
                );
            }
            insert notes;
            wrongEnrollment = Database.insert(
                new Case_Note__c(Enrollment__c = other.Id, Goal__c = goal.Id, Subject__c = 'Wrong'),
                false
            );
            plan = ServicePlanController.getPlan(enrolled.Id);
        }
        Test.stopTest();

        Map<String, Object> goal = (Map<String, Object>) goalsOf(plan)[0];
        List<Object> listed = (List<Object>) goal.get('notes');
        Assert.areEqual(3, listed.size(), 'The latest three notes.');
        Assert.areEqual(4, goal.get('noteCount'), 'Counted in all.');
        Assert.areEqual(
            'Visit 0',
            ((Map<String, Object>) listed[0]).get('subject'),
            'Newest first.'
        );
        Assert.isTrue((Boolean) plan.get('canAddNote'), 'Staff may write notes.');
        Assert.isFalse(
            wrongEnrollment.isSuccess(),
            'A goal of another enrollment is refused (R-CN5).'
        );
    }

    @IsTest
    static void erasingThePersonDeletesTheirGoalsAndSteps() {
        Enrollment__c enrolled;
        List<PersonErasure.Change> changes;
        System.runAs(TestUsers.adminWith(ADMIN)) {
            enrolled = enrollment(new List<Id>());
            Goal__c goal = new Goal__c(Enrollment__c = enrolled.Id, Name = 'Erase me');
            insert goal;
            insert new Goal_Step__c(Goal__c = goal.Id, Name = 'And me');

            Test.startTest();
            changes = new ProgramsErasureExtension().erase(enrolled.Contact__c);
            Test.stopTest();
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Goal__c WITH SYSTEM_MODE], 'Goals gone.');
        Assert.areEqual(0, [SELECT COUNT() FROM Goal_Step__c WITH SYSTEM_MODE], 'Steps gone.');
        Assert.areEqual(1, [SELECT COUNT() FROM Enrollment__c WITH SYSTEM_MODE], 'Kept.');
        Assert.areEqual(PersonErasure.DELETED, changes[0].action, 'Goals deleted.');
        Assert.areEqual(PersonErasure.KEPT, changes[1].action, 'Enrollment kept.');
    }

    @IsTest
    static void staffCannotEraseSomeoneWithGoals() {
        Enrollment__c enrolled = sharedEnrollment();
        System.runAs(planner()) {
            insert new Goal__c(Enrollment__c = enrolled.Id, Name = 'Kept');
        }
        Test.startTest();
        String refusal;
        System.runAs(planner()) {
            try {
                new ProgramsErasureExtension().erase(enrolled.Contact__c);
            } catch (PersonErasure.ErasureException refused) {
                refusal = refused.getMessage();
            }
        }
        Test.stopTest();
        Assert.areEqual(Label.Programs_Erase_NeedProgramsAdmin, refusal);
    }

    @IsTest
    static void aGoalLinksOnlyToAnOutcomeOfThisProgramOrTheOrganization() {
        Schema.SObjectType elementType = NamespaceUtil.packagedObjectType('Logic_Model_Element__c');
        Schema.SObjectType modelType = NamespaceUtil.packagedObjectType('Logic_Model__c');
        User admin = TestUsers.adminWithInstalledModules();
        List<Map<String, String>> offered;
        Map<String, Object> plan;
        String refusal;
        System.runAs(admin) {
            Enrollment__c enrolled = enrollment(new List<Id>());
            if (elementType == null || modelType == null) {
                // Logic Models is not installed: nothing is offered and nothing breaks.
                Test.startTest();
                offered = ServicePlanController.getOutcomes(enrolled.Id);
                plan = ServicePlanController.getPlan(enrolled.Id);
                Test.stopTest();
                Assert.isTrue(offered.isEmpty(), 'No outcomes without Logic Models.');
                Assert.isFalse((Boolean) plan.get('outcomesAvailable'));
                return;
            }
            Program__c other = new Program__c(Name = 'Other');
            insert other;
            SObject programModel = modelType.newSObject();
            programModel.put('Name', 'Pantry model');
            programModel.put(NamespaceUtil.qualify('Program_Id__c'), (String) enrolled.Program__c);
            SObject orgModel = modelType.newSObject();
            orgModel.put('Name', 'Organization model');
            SObject otherModel = modelType.newSObject();
            otherModel.put('Name', 'Other model');
            otherModel.put(NamespaceUtil.qualify('Program_Id__c'), (String) other.Id);
            insert new List<SObject>{ programModel, orgModel, otherModel };
            List<SObject> elements = new List<SObject>();
            for (SObject model : new List<SObject>{ programModel, orgModel, otherModel }) {
                SObject outcome = elementType.newSObject();
                outcome.put('Name', 'Housed ' + model.get('Name'));
                outcome.put(NamespaceUtil.qualify('Logic_Model__c'), model.Id);
                outcome.put(NamespaceUtil.qualify('Type__c'), 'Outcome');
                outcome.put(NamespaceUtil.qualify('Outcome_Term__c'), 'Short Term');
                elements.add(outcome);
            }
            insert elements;

            Test.startTest();
            offered = ServicePlanController.getOutcomes(enrolled.Id);
            Map<String, Object> goal = goalJson(enrolled.Id, 'Housed');
            goal.put('outcomeId', (String) elements[0].Id);
            plan = ServicePlanController.saveGoal(JSON.serialize(goal));
            goal.put('outcomeId', (String) elements[2].Id);
            try {
                ServicePlanController.saveGoal(JSON.serialize(goal));
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(2, offered.size(), 'This program\'s outcome and the organization\'s.');
            Assert.areEqual(
                (String) elements[0].Id,
                offered[0].get('value'),
                'The program\'s model first.'
            );
            Map<String, Object> saved = (Map<String, Object>) goalsOf(plan)[0];
            Assert.areEqual('Housed Pantry model', saved.get('outcomeName'));
            Assert.isFalse((Boolean) saved.get('outcomeMissing'));
            Assert.areEqual(
                Label.Programs_Plan_BadOutcome,
                refusal,
                'Another program\'s outcome is refused.'
            );
        }
    }

    @IsTest
    static void unexpectedFailuresAreLoggedAndReportedPlainly() {
        Test.startTest();
        AuraHandledException handled;
        AuraHandledException bad;
        System.runAs(planner()) {
            handled = ServicePlanController.handled(new MathException('boom'), null);
            try {
                ServicePlanController.saveStep('[]');
            } catch (AuraHandledException refused) {
                bad = refused;
            }
        }
        Test.stopTest();
        Assert.areEqual(Label.Programs_Plan_ActionFailed, handled.getMessage());
        Assert.areEqual(Label.Programs_Plan_ActionFailed, bad.getMessage());
    }
}
