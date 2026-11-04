/**
 * The Grant Pipeline tab (F-01, canonical model 29ZH, ADR-0161 `0161-funders-module.md` decision
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
        /** For a payment row on the Grant Calendar (F-08): the amount expected. */
        @AuraEnabled
        public Decimal amount;
        /** For a board card: what Record the Award starts from (modules-16). */
        @AuraEnabled
        public Date awardStartDate;
        @AuraEnabled
        public Date awardEndDate;
        @AuraEnabled
        public Boolean restricted;
    }

    public static final String KIND_APPLICATION = 'application';
    public static final String KIND_REQUIREMENT = 'requirement';

    /** The tab, for everyone's grants or only the person's own. */
    @AuraEnabled
    public static Board getBoard(Boolean mineOnly) {
        try {
            Map<String, Object> binds = new Map<String, Object>{
                'openStages' => GrantService.OPEN_STAGES,
                'awarded' => GrantService.STAGE_AWARDED,
                'maxCards' => maxCards,
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
                Card card = toCard(grant);
                card.awardStartDate = grant.Award_Start_Date__c;
                card.awardEndDate = grant.Award_End_Date__c;
                card.restricted = grant.Restricted__c;
                board.cards.add(card);
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

            // The same reader as the Grant Calendar (GrantDeadlineSelector), overdue included.
            Date horizon = Date.today().addDays(DEADLINE_DAYS);
            for (
                Grant__c grant : GrantDeadlineSelector.applications(
                    null,
                    horizon,
                    mineOnly,
                    MAX_DEADLINES
                )
            ) {
                Card row = toCard(grant);
                row.kind = KIND_APPLICATION;
                board.deadlines.add(row);
            }
            for (
                Grant_Requirement__c requirement : GrantDeadlineSelector.requirements(
                    null,
                    horizon,
                    mineOnly,
                    MAX_DEADLINES
                )
            ) {
                board.deadlines.add(toRequirementRow(requirement));
            }
            board.canMarkSubmitted = Schema.SObjectType.Grant_Requirement__c.fields.Status__c.isUpdateable();
            return board;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getBoard');
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Pipeline_LoadFailed'));
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
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
        }
    }

    /**
     * Record the Award (modules-16): moves one grant to Awarded with what the award letter says,
     * each optional: the amount awarded, the award period and whether the money is restricted. A
     * blank value leaves the grant's own value as it is. The grant rules check the dates and fill
     * in the decision date (R-GN3).
     */
    @AuraEnabled
    public static void recordAward(
        Id grantId,
        Decimal amountAwarded,
        Date startDate,
        Date endDate,
        Boolean restricted
    ) {
        if (!Schema.SObjectType.Grant__c.isUpdateable()) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
        }
        if (grantId == null) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorStage);
        }
        try {
            Grant__c grant = new Grant__c(Id = grantId, Stage__c = GrantService.STAGE_AWARDED);
            if (amountAwarded != null) {
                grant.Amount_Awarded__c = amountAwarded;
            }
            if (startDate != null) {
                grant.Award_Start_Date__c = startDate;
            }
            if (endDate != null) {
                grant.Award_End_Date__c = endDate;
            }
            if (restricted != null) {
                grant.Restricted__c = restricted;
            }
            Database.update(grant, true, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.recordAward', grantId);
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
        }
    }

    /** F-02: an open requirement as a deadline row; the Grant Calendar draws the same shape. */
    public static Card toRequirementRow(Grant_Requirement__c requirement) {
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
        return row;
    }

    /**
     * F-02: marks one requirement Submitted; the dates automation fills its Submitted Date. Returns
     * what it replaced, for Undo (modules-17).
     */
    @AuraEnabled
    public static FundersUndoState markSubmitted(Id requirementId) {
        if (!Schema.SObjectType.Grant_Requirement__c.fields.Status__c.isUpdateable()) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
        }
        try {
            return GrantRequirementService.markSubmitted(requirementId);
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.markSubmitted', requirementId);
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
        }
    }

    /** modules-17: Undo for Mark Submitted, from what markSubmitted returned. */
    @AuraEnabled
    public static void undoSubmitted(Id requirementId, String status, Date submittedDate) {
        if (!Schema.SObjectType.Grant_Requirement__c.fields.Status__c.isUpdateable()) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
        }
        Boolean undone;
        try {
            undone = GrantRequirementService.undoSubmitted(requirementId, status, submittedDate);
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.undoSubmitted', requirementId);
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Shared_NotSaved'));
        }
        if (!undone) {
            throw UserErrors.message(BarnHelp.text('Funders', 'Funders_Undo_Changed'));
        }
    }

    private static String selectCards() {
        return 'SELECT Id, Name, Stage__c, Funder__c, Funder__r.Name, Amount_Requested__c,' +
            ' Application_Deadline__c, Next_Step__c, Owner.Name, Award_Start_Date__c,' +
            ' Award_End_Date__c, Restricted__c FROM Grant__c';
    }

    /** A grant as a card or deadline row; the Grant Calendar draws the same shape. */
    public static Card toCard(Grant__c grant) {
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
