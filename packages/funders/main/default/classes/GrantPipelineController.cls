/**
 * The Grant Pipeline tab (F-01, canonical model 29ZH, ADR-NEXT `NEXT-funders-module.md` decision
 * 11): the open grants by stage with their totals, the grants awarded this fiscal year, the
 * application deadlines coming up, and moving a grant to another stage.
 *
 * Thin by design (plan Section 9.9): it returns plain shapes, and arranging them into columns and
 * deadline rows happens in the browser module `grantPipelineModel`. Everything runs as the person:
 * reads in user mode, writes `AccessLevel.USER_MODE`.
 */
public with sharing class GrantPipelineController {
    private static final String CONTEXT = 'GrantPipelineController';
    /** The most cards the board draws; the totals are counted by the database and stay exact. */
    @TestVisible
    private static Integer maxCards = 1000;
    /** How far ahead Upcoming Deadlines looks (R-GN7). */
    public static final Integer DEADLINE_DAYS = 60;
    private static final Integer MAX_DEADLINES = 200;

    /** Everything the tab draws. */
    public class Board {
        @AuraEnabled
        public List<String> stages = new List<String>();
        @AuraEnabled
        public List<String> allStages = new List<String>();
        @AuraEnabled
        public List<Total> stageTotals = new List<Total>();
        @AuraEnabled
        public List<Card> cards = new List<Card>();
        @AuraEnabled
        public List<Card> deadlines = new List<Card>();
        @AuraEnabled
        public Boolean truncated = false;
        @AuraEnabled
        public Integer openCount = 0;
        @AuraEnabled
        public Decimal openAmount = 0;
        @AuraEnabled
        public Integer awardedCount = 0;
        @AuraEnabled
        public Decimal awardedAmount = 0;
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public Boolean canCreate = false;
        @AuraEnabled
        public Boolean canMarkSubmitted = false;
        @AuraEnabled
        public Date today;
    }

    /** One stage's open grants. */
    public class Total {
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public Decimal amount;
    }

    /** One open grant, as a card or a deadline row. */
    public class Card {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public String funderId;
        @AuraEnabled
        public String funderName;
        @AuraEnabled
        public Decimal amountRequested;
        @AuraEnabled
        public Date deadline;
        @AuraEnabled
        public String nextStep;
        @AuraEnabled
        public String ownerName;
        /** For a deadline row: `application` (a grant's deadline) or `requirement` (F-02). */
        @AuraEnabled
        public String kind;
        /** For a requirement row: its grant and its type. */
        @AuraEnabled
        public String grantId;
        @AuraEnabled
        public String grantName;
        @AuraEnabled
        public String requirementType;
    }

    public static final String KIND_APPLICATION = 'application';
    public static final String KIND_REQUIREMENT = 'requirement';

    /** The tab, for everyone's grants or only the person's own. */
    @AuraEnabled
    public static Board getBoard(Boolean mineOnly) {
        try {
            Map<String, Object> binds = new Map<String, Object>{
                'openStages' => GrantService.OPEN_STAGES,
                'beforeSubmitting' => GrantService.BEFORE_SUBMITTING,
                'awarded' => GrantService.STAGE_AWARDED,
                'horizon' => Date.today().addDays(DEADLINE_DAYS),
                'maxCards' => maxCards,
                'maxDeadlines' => MAX_DEADLINES,
                'ownerId' => UserInfo.getUserId()
            };
            String mine = mineOnly == true ? ' AND OwnerId = :ownerId' : '';
            Board board = new Board();
            board.today = Date.today();
            board.stages = GrantService.OPEN_STAGES;
            board.allStages = GrantService.STAGES;
            board.canEdit = Schema.SObjectType.Grant__c.isUpdateable();
            board.canCreate = Schema.SObjectType.Grant__c.isCreateable();

            List<AggregateResult> byStage = (List<AggregateResult>) Database.queryWithBinds(
                'SELECT Stage__c stage, COUNT(Id) total, SUM(Amount_Requested__c) amount' +
                    ' FROM Grant__c WHERE Stage__c IN :openStages' +
                    mine +
                    ' GROUP BY Stage__c',
                binds,
                AccessLevel.USER_MODE
            );
            for (AggregateResult row : byStage) {
                Total total = new Total();
                total.stage = (String) row.get('stage');
                total.count = (Integer) row.get('total');
                total.amount = row.get('amount') == null ? 0 : (Decimal) row.get('amount');
                board.stageTotals.add(total);
                board.openCount += total.count;
                board.openAmount += total.amount;
            }

            for (
                Grant__c grant : (List<Grant__c>) Database.queryWithBinds(
                    selectCards() +
                        ' WHERE Stage__c IN :openStages' +
                        mine +
                        ' ORDER BY Application_Deadline__c ASC NULLS LAST, Name LIMIT :maxCards',
                    binds,
                    AccessLevel.USER_MODE
                )
            ) {
                board.cards.add(toCard(grant));
            }
            board.truncated = board.openCount > board.cards.size();

            AggregateResult awarded = (AggregateResult) Database.queryWithBinds(
                'SELECT COUNT(Id) total, SUM(Amount_Awarded__c) amount FROM Grant__c' +
                    ' WHERE Stage__c = :awarded AND Decision_Date__c = THIS_FISCAL_YEAR' +
                    mine,
                binds,
                AccessLevel.USER_MODE
            )[0];
            board.awardedCount = (Integer) awarded.get('total');
            board.awardedAmount = awarded.get('amount') == null
                ? 0
                : (Decimal) awarded.get('amount');

            for (
                Grant__c grant : (List<Grant__c>) Database.queryWithBinds(
                    selectCards() +
                        ' WHERE Stage__c IN :beforeSubmitting' +
                        ' AND Application_Deadline__c != null' +
                        ' AND Application_Deadline__c <= :horizon' +
                        mine +
                        ' ORDER BY Application_Deadline__c ASC, Name LIMIT :maxDeadlines',
                    binds,
                    AccessLevel.USER_MODE
                )
            ) {
                Card row = toCard(grant);
                row.kind = KIND_APPLICATION;
                board.deadlines.add(row);
            }
            if (Schema.SObjectType.Grant_Requirement__c.isAccessible()) {
                addRequirementDeadlines(board, binds, mineOnly == true);
            }
            board.canMarkSubmitted = Schema.SObjectType.Grant_Requirement__c.fields.Status__c.isUpdateable();
            return board;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getBoard');
            throw UserErrors.message(Label.Funders_Pipeline_ErrorLoad);
        }
    }

    /**
     * Moves one grant to another stage. Moving to Awarded records the amount awarded when one is
     * given. The grant rules fill in the stage dates (R-GN3).
     */
    @AuraEnabled
    public static void moveStage(Id grantId, String stage, Decimal amountAwarded) {
        if (!Schema.SObjectType.Grant__c.isUpdateable()) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
        }
        if (grantId == null || !GrantService.STAGES.contains(stage)) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorStage);
        }
        try {
            Grant__c grant = new Grant__c(Id = grantId, Stage__c = stage);
            if (stage == GrantService.STAGE_AWARDED && amountAwarded != null) {
                grant.Amount_Awarded__c = amountAwarded;
            }
            Database.update(grant, true, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.moveStage', grantId);
            throw UserErrors.message(Label.Funders_Pipeline_ErrorUnexpected);
        }
    }

    /**
     * F-02: open requirements due within the window or overdue, as deadline rows. Mine means
     * assigned to the person, or on a grant the person owns.
     */
    private static void addRequirementDeadlines(
        Board board,
        Map<String, Object> binds,
        Boolean mineOnly
    ) {
        binds.put('openStatuses', GrantRequirementService.OPEN_STATUSES);
        String mine = mineOnly
            ? ' AND (Assigned_To__c = :ownerId OR Grant__r.OwnerId = :ownerId)'
            : '';
        for (
            Grant_Requirement__c requirement : (List<Grant_Requirement__c>) Database.queryWithBinds(
                'SELECT Id, Name, Type__c, Due_Date__c, Grant__c, Grant__r.Name,' +
                    ' Grant__r.Funder__c, Grant__r.Funder__r.Name, Assigned_To__r.Name' +
                    ' FROM Grant_Requirement__c WHERE Status__c IN :openStatuses' +
                    ' AND Due_Date__c <= :horizon' +
                    mine +
                    ' ORDER BY Due_Date__c ASC, Name LIMIT :maxDeadlines',
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            Card row = new Card();
            row.id = requirement.Id;
            row.name = requirement.Name;
            row.kind = KIND_REQUIREMENT;
            row.deadline = requirement.Due_Date__c;
            row.requirementType = requirement.Type__c;
            row.grantId = requirement.Grant__c;
            row.grantName = requirement.Grant__r?.Name;
            row.funderId = requirement.Grant__r?.Funder__c;
            row.funderName = requirement.Grant__r?.Funder__r?.Name;
            row.ownerName = requirement.Assigned_To__r?.Name;
            board.deadlines.add(row);
        }
    }

    /** F-02: marks one requirement Submitted; the dates automation fills its Submitted Date. */
    @AuraEnabled
    public static void markSubmitted(Id requirementId) {
        if (!Schema.SObjectType.Grant_Requirement__c.fields.Status__c.isUpdateable()) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
        }
        try {
            GrantRequirementService.markSubmitted(requirementId);
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.markSubmitted', requirementId);
            throw UserErrors.message(Label.Funders_Pipeline_ErrorUnexpected);
        }
    }

    private static String selectCards() {
        return 'SELECT Id, Name, Stage__c, Funder__c, Funder__r.Name, Amount_Requested__c,' +
            ' Application_Deadline__c, Next_Step__c, Owner.Name FROM Grant__c';
    }

    private static Card toCard(Grant__c grant) {
        Card card = new Card();
        card.id = grant.Id;
        card.name = grant.Name;
        card.stage = grant.Stage__c;
        card.funderId = grant.Funder__c;
        card.funderName = grant.Funder__r?.Name;
        card.amountRequested = grant.Amount_Requested__c;
        card.deadline = grant.Application_Deadline__c;
        card.nextStep = grant.Next_Step__c;
        card.ownerName = grant.Owner?.Name;
        return card;
    }
}
