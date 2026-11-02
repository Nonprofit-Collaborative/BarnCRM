/**
 * Participant service plans (P-10; canonical model Sections 29ZA2 and 29ZA3; ADR-NEXT
 * `NEXT-programs-service-plans-cohorts-sessions.md`): the goals on an enrollment, their steps,
 * reviews and the case notes about them, as plain JSON shapes so the same panel could call a
 * WordPress endpoint (plan 9.9). Every read and write runs in user mode: Goal and Goal Step are
 * details of the enrollment, so the platform shows and changes only what the enrollment's sharing
 * allows (R-GL1).
 *
 * A goal names a Logic Models outcome by record identifier only (R-GL5): the outcome object is
 * found by describe, read with dynamic SOQL, and never named in a static reference, so Programs
 * installs without Logic Models.
 */
public with sharing class ServicePlanService {
    /** The goal statuses that close a goal (R-GL2). */
    public static final Set<String> CLOSED_GOAL = new Set<String>{ 'Achieved', 'Not Achieved' };
    /** The step status that completes a step (R-GS1). */
    public static final String DONE = 'Done';
    /** The most goals read for one enrollment, and case notes listed under one goal. */
    public static final Integer MAX_GOALS = 100;
    public static final Integer NOTES_PER_GOAL = 3;

    private static final String OUTCOME_OBJECT = 'Logic_Model_Element__c';
    private static final String OUTCOME_TYPE = 'Outcome';
    private static final Integer OUTCOME_LIMIT = 500;

    /** Raised with a message the panel shows as it is. */
    public class PlanException extends Exception {
    }

    // ------------------------------------------------------------------------- the date rules

    /** R-GL2: closing fills an empty Closed Date with today; reopening empties it. */
    public static void fillClosedDates(List<Goal__c> goals, Map<Id, SObject> oldById) {
        for (Goal__c goal : goals) {
            Boolean closed = CLOSED_GOAL.contains(goal.Status__c);
            Goal__c old = oldById == null ? null : (Goal__c) oldById.get(goal.Id);
            Boolean wasClosed = old != null && CLOSED_GOAL.contains(old.Status__c);
            if (closed && goal.Closed_Date__c == null && (old == null || !wasClosed)) {
                goal.Closed_Date__c = Date.today();
            } else if (!closed && wasClosed) {
                goal.Closed_Date__c = null;
            }
        }
    }

    /** R-GS1: Done fills an empty Completed Date with today; reopening empties it. */
    public static void fillCompletedDates(List<Goal_Step__c> steps, Map<Id, SObject> oldById) {
        for (Goal_Step__c step : steps) {
            Boolean nowDone = step.Status__c == DONE;
            Goal_Step__c old = oldById == null ? null : (Goal_Step__c) oldById.get(step.Id);
            Boolean wasDone = old != null && old.Status__c == DONE;
            if (nowDone && step.Completed_Date__c == null && !wasDone) {
                step.Completed_Date__c = Date.today();
            } else if (!nowDone && wasDone) {
                step.Completed_Date__c = null;
            }
        }
    }

    // -------------------------------------------------------------------------------- reading

    /**
     * The enrollment's plan as the panel draws it.
     *
     * @param enrollmentId the enrollment
     * @return the person and program, what the user may do, the status choices, and the goals,
     *         each with its steps and the latest case notes about it the user may see
     */
    public static Map<String, Object> read(Id enrollmentId) {
        List<Enrollment__c> found = [
            SELECT Id, Program__c, Program__r.Name, Contact__r.Name, Account__r.Name
            FROM Enrollment__c
            WHERE Id = :enrollmentId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            throw new PlanException(Label.Programs_Plan_NotFound);
        }
        Enrollment__c enrollment = found[0];
        Map<String, Object> plan = new Map<String, Object>{
            'enrollmentId' => enrollment.Id,
            'programName' => enrollment.Program__r?.Name,
            'personName' => enrollment.Contact__r != null
                ? enrollment.Contact__r.Name
                : enrollment.Account__r?.Name,
            'canEdit' => canEdit(enrollmentId),
            'canAddNote' => Schema.SObjectType.Case_Note__c.isCreateable(),
            'outcomesAvailable' => outcomeType() != null,
            'goalStatuses' => options(Goal__c.Status__c.getDescribe()),
            'stepStatuses' => options(Goal_Step__c.Status__c.getDescribe())
        };

        List<Goal__c> goals = [
            SELECT
                Id,
                Name,
                Description__c,
                Status__c,
                Target_Date__c,
                Assigned_To__c,
                Assigned_To__r.Name,
                Last_Review_Date__c,
                Next_Review_Date__c,
                Closed_Date__c,
                Outcome_Id__c,
                (
                    SELECT
                        Id,
                        Name,
                        Status__c,
                        Assigned_To__c,
                        Assigned_To__r.Name,
                        Target_Date__c,
                        Completed_Date__c
                    FROM Steps__r
                    ORDER BY Target_Date__c NULLS LAST, CreatedDate
                )
            FROM Goal__c
            WHERE Enrollment__c = :enrollmentId
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT :MAX_GOALS
        ];
        Map<Id, List<Map<String, Object>>> notesByGoal = notesAbout(goals);
        Map<String, String> outcomeNames = outcomeNames(goals);
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Goal__c goal : goals) {
            rows.add(goalRow(goal, notesByGoal.get(goal.Id), outcomeNames));
        }
        plan.put('goals', rows);
        return plan;
    }

    private static Map<String, Object> goalRow(
        Goal__c goal,
        List<Map<String, Object>> notes,
        Map<String, String> outcomeNames
    ) {
        List<Map<String, Object>> steps = new List<Map<String, Object>>();
        for (Goal_Step__c step : goal.Steps__r) {
            steps.add(
                new Map<String, Object>{
                    'id' => step.Id,
                    'name' => step.Name,
                    'status' => step.Status__c,
                    'assignedToId' => step.Assigned_To__c,
                    'assignedToName' => step.Assigned_To__r?.Name,
                    'targetDate' => step.Target_Date__c,
                    'completedDate' => step.Completed_Date__c
                }
            );
        }
        List<Map<String, Object>> noteRows = notes == null
            ? new List<Map<String, Object>>()
            : notes;
        List<Map<String, Object>> latest = new List<Map<String, Object>>();
        for (Integer i = 0; i < noteRows.size() && i < NOTES_PER_GOAL; i++) {
            latest.add(noteRows[i]);
        }
        String outcomeId = goal.Outcome_Id__c;
        return new Map<String, Object>{
            'id' => goal.Id,
            'name' => goal.Name,
            'description' => goal.Description__c,
            'status' => goal.Status__c,
            'closed' => CLOSED_GOAL.contains(goal.Status__c),
            'targetDate' => goal.Target_Date__c,
            'assignedToId' => goal.Assigned_To__c,
            'assignedToName' => goal.Assigned_To__r?.Name,
            'lastReviewDate' => goal.Last_Review_Date__c,
            'nextReviewDate' => goal.Next_Review_Date__c,
            'closedDate' => goal.Closed_Date__c,
            'outcomeId' => outcomeId,
            'outcomeName' => outcomeId == null ? null : outcomeNames.get(outcomeId),
            'outcomeMissing' => outcomeId != null && !outcomeNames.containsKey(outcomeId),
            'steps' => steps,
            'notes' => latest,
            'noteCount' => noteRows.size()
        };
    }

    /** The case notes about these goals that the user may read, newest first, by goal. */
    private static Map<Id, List<Map<String, Object>>> notesAbout(List<Goal__c> goals) {
        Map<Id, List<Map<String, Object>>> byGoal = new Map<Id, List<Map<String, Object>>>();
        if (goals.isEmpty() || !Schema.SObjectType.Case_Note__c.isAccessible()) {
            return byGoal;
        }
        Set<Id> goalIds = new Map<Id, Goal__c>(goals).keySet();
        for (Case_Note__c note : [
            SELECT Id, Goal__c, Note_Date__c, Type__c, Subject__c
            FROM Case_Note__c
            WHERE Goal__c IN :goalIds
            WITH USER_MODE
            ORDER BY Note_Date__c DESC, CreatedDate DESC
            LIMIT 1000
        ]) {
            if (!byGoal.containsKey(note.Goal__c)) {
                byGoal.put(note.Goal__c, new List<Map<String, Object>>());
            }
            byGoal.get(note.Goal__c)
                .add(
                    new Map<String, Object>{
                        'id' => note.Id,
                        'noteDate' => note.Note_Date__c,
                        'type' => note.Type__c,
                        'subject' => note.Subject__c
                    }
                );
        }
        return byGoal;
    }

    /** Whether the user may add and change goals here: object access and edit on the enrollment. */
    private static Boolean canEdit(Id enrollmentId) {
        if (
            !Schema.SObjectType.Goal__c.isCreateable() || !Schema.SObjectType.Goal__c.isUpdateable()
        ) {
            return false;
        }
        List<UserRecordAccess> access = [
            SELECT RecordId, HasEditAccess
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId = :enrollmentId
            WITH SYSTEM_MODE
        ];
        return !access.isEmpty() && access[0].HasEditAccess;
    }

    private static List<Map<String, String>> options(Schema.DescribeFieldResult field) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                result.add(
                    new Map<String, String>{
                        'value' => entry.getValue(),
                        'label' => entry.getLabel()
                    }
                );
            }
        }
        return result;
    }

    // ------------------------------------------------------------------------------ outcomes

    /**
     * Logic Models' element object, found by describe only (R-GL5), or null where Logic Models is
     * not installed or the user cannot read it.
     */
    @TestVisible
    private static Schema.SObjectType outcomeType() {
        Schema.SObjectType type = NamespaceUtil.packagedObjectType(OUTCOME_OBJECT);
        if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
            return null;
        }
        return type;
    }

    /**
     * The outcomes a goal on this enrollment can work toward: those of the logic model for the
     * enrollment's program first, then the organization's. Empty without Logic Models.
     *
     * @param enrollmentId the enrollment
     * @return value and label pairs, the label naming the model
     */
    public static List<Map<String, String>> outcomes(Id enrollmentId) {
        List<Map<String, String>> result = new List<Map<String, String>>();
        Schema.SObjectType type = outcomeType();
        if (type == null || enrollmentId == null) {
            return result;
        }
        List<Enrollment__c> found = [
            SELECT Program__c
            FROM Enrollment__c
            WHERE Id = :enrollmentId
            WITH USER_MODE
        ];
        if (found.isEmpty()) {
            return result;
        }
        String programId = found[0].Program__c;
        String model = NamespaceUtil.qualify('Logic_Model__r');
        String programField = model + '.' + NamespaceUtil.qualify('Program_Id__c');
        // Every name here comes from describe or this class's constants, never from the user.
        String soql =
            'SELECT Id, Name, ' +
            model +
            '.Name, ' +
            programField +
            ' FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE ' +
            NamespaceUtil.qualify('Type__c') +
            ' = :outcomeType AND (' +
            programField +
            ' = :programId OR ' +
            programField +
            ' = NULL) ORDER BY ' +
            model +
            '.Name, Name LIMIT :maxRows';
        List<Map<String, String>> organization = new List<Map<String, String>>();
        for (
            SObject row : Database.queryWithBinds(
                soql,
                new Map<String, Object>{
                    'outcomeType' => OUTCOME_TYPE,
                    'programId' => programId,
                    'maxRows' => OUTCOME_LIMIT
                },
                AccessLevel.USER_MODE
            )
        ) {
            SObject parent = row.getSObject(model);
            String modelName = parent == null ? '' : (String) parent.get('Name');
            Map<String, String> option = new Map<String, String>{
                'value' => (String) row.Id,
                'label' => String.format(
                    Label.Programs_Plan_OutcomeOption,
                    new List<Object>{ (String) row.get('Name'), modelName }
                )
            };
            Object scope = parent == null
                ? null
                : parent.get(NamespaceUtil.qualify('Program_Id__c'));
            if (scope == null) {
                organization.add(option);
            } else {
                result.add(option);
            }
        }
        result.addAll(organization);
        return result;
    }

    /** The names of the outcomes these goals name, by Id, read in user mode. */
    private static Map<String, String> outcomeNames(List<Goal__c> goals) {
        Map<String, String> names = new Map<String, String>();
        Schema.SObjectType type = outcomeType();
        Set<Id> ids = new Set<Id>();
        for (Goal__c goal : goals) {
            Id outcomeId = asId(goal.Outcome_Id__c);
            if (outcomeId != null && type != null && outcomeId.getSObjectType() == type) {
                ids.add(outcomeId);
            }
        }
        if (ids.isEmpty()) {
            return names;
        }
        String soql =
            'SELECT Id, Name FROM ' +
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() +
            ' WHERE Id IN :ids';
        for (
            SObject row : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.USER_MODE
            )
        ) {
            names.put((String) row.Id, (String) row.get('Name'));
            names.put(String.valueOf(row.Id).left(15), (String) row.get('Name'));
        }
        return names;
    }

    private static Id asId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception notAnId) {
            return null;
        }
    }

    // -------------------------------------------------------------------------------- writing

    /**
     * Adds or changes a goal. On insert `enrollmentId` places it.
     *
     * @param fields id (blank to add), enrollmentId, name, description, status, targetDate,
     *        assignedToId, nextReviewDate, outcomeId (blank for none)
     * @return the goal's enrollment
     */
    public static Id saveGoal(Map<String, Object> fields) {
        Id goalId = idOf(fields, 'id');
        Id enrollmentId = goalId == null ? idOf(fields, 'enrollmentId') : enrollmentOf(goalId);
        if (enrollmentId == null) {
            throw new PlanException(Label.Programs_Plan_NotFound);
        }
        String name = text(fields, 'name');
        if (name == null) {
            throw new PlanException(Label.Programs_Plan_NameRequired);
        }
        Goal__c goal = new Goal__c(
            Id = goalId,
            Name = name.left(80),
            Description__c = text(fields, 'description'),
            Target_Date__c = day(fields, 'targetDate'),
            Assigned_To__c = idOf(fields, 'assignedToId'),
            Next_Review_Date__c = day(fields, 'nextReviewDate')
        );
        String status = text(fields, 'status');
        if (status != null) {
            goal.Status__c = status;
        }
        if (fields.containsKey('outcomeId')) {
            goal.Outcome_Id__c = checkedOutcome(enrollmentId, text(fields, 'outcomeId'));
        }
        if (goalId == null) {
            goal.Enrollment__c = enrollmentId;
            insert as user goal;
        } else {
            update as user goal;
        }
        return enrollmentId;
    }

    /**
     * Adds or changes a step. On insert `goalId` places it.
     *
     * @param fields id (blank to add), goalId, name, status, targetDate, assignedToId
     * @return the step's enrollment
     */
    public static Id saveStep(Map<String, Object> fields) {
        Id stepId = idOf(fields, 'id');
        Id goalId = stepId == null ? idOf(fields, 'goalId') : goalOf(stepId);
        Id enrollmentId = goalId == null ? null : enrollmentOf(goalId);
        if (enrollmentId == null) {
            throw new PlanException(Label.Programs_Plan_NotFound);
        }
        Goal_Step__c step = new Goal_Step__c(Id = stepId);
        if (fields.containsKey('name')) {
            String name = text(fields, 'name');
            if (name == null) {
                throw new PlanException(Label.Programs_Plan_NameRequired);
            }
            step.Name = name.left(80);
        } else if (stepId == null) {
            throw new PlanException(Label.Programs_Plan_NameRequired);
        }
        String status = text(fields, 'status');
        if (status != null) {
            step.Status__c = status;
        }
        if (fields.containsKey('targetDate')) {
            step.Target_Date__c = day(fields, 'targetDate');
        }
        if (fields.containsKey('assignedToId')) {
            step.Assigned_To__c = idOf(fields, 'assignedToId');
        }
        if (stepId == null) {
            step.Goal__c = goalId;
            insert as user step;
        } else {
            update as user step;
        }
        return enrollmentId;
    }

    /**
     * R-GL3: the goal was reviewed today; the next review is on the date given (or none).
     *
     * @param goalId the goal
     * @param nextReview the next review date, or null
     * @return the goal's enrollment
     */
    public static Id markReviewed(Id goalId, Date nextReview) {
        Id enrollmentId = goalId == null ? null : enrollmentOf(goalId);
        if (enrollmentId == null) {
            throw new PlanException(Label.Programs_Plan_NotFound);
        }
        if (nextReview != null && nextReview < Date.today()) {
            throw new PlanException(Label.Programs_Plan_NextReviewPast);
        }
        update as user new Goal__c(
            Id = goalId,
            Last_Review_Date__c = Date.today(),
            Next_Review_Date__c = nextReview
        );
        return enrollmentId;
    }

    /** An outcome the picker offers for this enrollment, or null for none; anything else refused. */
    private static String checkedOutcome(Id enrollmentId, String outcomeId) {
        if (outcomeId == null) {
            return null;
        }
        for (Map<String, String> option : outcomes(enrollmentId)) {
            if (option.get('value') == outcomeId) {
                return outcomeId;
            }
        }
        throw new PlanException(Label.Programs_Plan_BadOutcome);
    }

    private static Id enrollmentOf(Id goalId) {
        List<Goal__c> goals = [
            SELECT Enrollment__c
            FROM Goal__c
            WHERE Id = :goalId
            WITH USER_MODE
        ];
        return goals.isEmpty() ? null : goals[0].Enrollment__c;
    }

    private static Id goalOf(Id stepId) {
        List<Goal_Step__c> steps = [
            SELECT Goal__c
            FROM Goal_Step__c
            WHERE Id = :stepId
            WITH USER_MODE
        ];
        return steps.isEmpty() ? null : steps[0].Goal__c;
    }

    private static String text(Map<String, Object> fields, String key) {
        Object value = fields.get(key);
        if (value == null) {
            return null;
        }
        String result = String.valueOf(value).trim();
        return String.isEmpty(result) ? null : result;
    }

    private static Id idOf(Map<String, Object> fields, String key) {
        String value = text(fields, key);
        if (value == null) {
            return null;
        }
        Id result = asId(value);
        if (result == null) {
            throw new PlanException(Label.Programs_Plan_NotFound);
        }
        return result;
    }

    private static Date day(Map<String, Object> fields, String key) {
        String value = text(fields, key);
        return value == null ? null : Date.valueOf(value);
    }
}
