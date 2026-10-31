/**
 * The Ask Pipeline board (G-26, canonical model Section 25R): the stages, the open asks as cards,
 * the totals, moving an ask to another stage, and closing one.
 *
 * Thin by design (plan Section 9.9): it returns plain shapes the board renders, and arranging the
 * cards into columns happens in the browser module `askPipelineModel`. Everything runs as the
 * person: reads `WITH USER_MODE`, writes `AccessLevel.USER_MODE`.
 *
 * Closing an ask as Won can record its result (R-SO5): a gift through Quick Gift Entry's own save,
 * so every gift rule applies; a pledge as a Commitment of type Pledge; or a link to a gift or pledge
 * already entered for the same donor. The result, the link and the outcome are saved together or
 * not at all.
 */
public with sharing class AskPipelineController {
    private static final String CONTEXT = 'AskPipelineController';
    /** The most cards the board draws; the totals are counted by the database and stay exact. */
    @TestVisible
    private static Integer maxCards = 1000;

    public static final String RESULT_GIFT = 'gift';
    public static final String RESULT_PLEDGE = 'pledge';
    public static final String RESULT_LINK = 'link';
    public static final String RESULT_LATER = 'later';

    private static final String TYPE_PLEDGE = 'Pledge';
    private static final String STATUS_ACTIVE = 'Active';
    private static final String TYPE_IN_KIND = 'In-kind';

    /** Everything the board draws. */
    public class Board {
        @AuraEnabled
        public List<String> stages = new List<String>();
        @AuraEnabled
        public List<Total> stageTotals = new List<Total>();
        @AuraEnabled
        public List<Card> cards = new List<Card>();
        @AuraEnabled
        public Boolean truncated = false;
        @AuraEnabled
        public Integer openCount = 0;
        @AuraEnabled
        public Decimal openAmount = 0;
        @AuraEnabled
        public Integer wonCount = 0;
        @AuraEnabled
        public Decimal wonAmount = 0;
        @AuraEnabled
        public Integer declinedCount = 0;
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public Boolean canCreate = false;
        @AuraEnabled
        public List<Option> giftTypes = new List<Option>();
        @AuraEnabled
        public List<Option> frequencies = new List<Option>();
        @AuraEnabled
        public Date today;
    }

    /** One stage's open asks. */
    public class Total {
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public Decimal amount;
    }

    /** One open ask, as a card. */
    public class Card {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public String donorId;
        @AuraEnabled
        public String donorName;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date targetDate;
        @AuraEnabled
        public String nextStep;
        @AuraEnabled
        public String ownerName;
        @AuraEnabled
        public Date stageChangedDate;
    }

    /** One choice in a list. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** How the person closed an ask, as entered in the board's Close dialog. */
    public class CloseInput {
        @AuraEnabled
        public String askId { get; set; }
        /** Won, Declined or Withdrawn. */
        @AuraEnabled
        public String outcome { get; set; }
        /** For Won: gift, pledge, link or later. */
        @AuraEnabled
        public String result { get; set; }
        @AuraEnabled
        public Decimal amount { get; set; }
        @AuraEnabled
        public Date giftDate { get; set; }
        @AuraEnabled
        public String giftType { get; set; }
        @AuraEnabled
        public String frequency { get; set; }
        @AuraEnabled
        public Integer payments { get; set; }
        @AuraEnabled
        public String linkedId { get; set; }
        @AuraEnabled
        public Date nextAskDate { get; set; }
    }

    /** What came of closing an ask. */
    public class CloseResult {
        @AuraEnabled
        public Boolean success = false;
        @AuraEnabled
        public String error;
        @AuraEnabled
        public String giftId;
        @AuraEnabled
        public String commitmentId;
    }

    /** The board, for everyone's asks or only the person's own. */
    @AuraEnabled
    public static Board getBoard(Boolean mineOnly) {
        try {
            Id ownerId = mineOnly == true ? UserInfo.getUserId() : null;
            Board board = new Board();
            board.today = System.today();
            board.stages = AskRules.stages();
            board.canEdit = Schema.SObjectType.Ask__c.isUpdateable();
            board.canCreate = Schema.SObjectType.Ask__c.isCreateable();
            for (AskSelector.StageTotal row : AskSelector.openTotalsByStage(ownerId)) {
                Total total = new Total();
                total.stage = row.stage;
                total.count = row.count;
                total.amount = row.amount == null ? 0 : row.amount;
                board.stageTotals.add(total);
                board.openCount += total.count;
                board.openAmount += total.amount;
            }
            List<Ask__c> asks = AskSelector.openAsks(ownerId, maxCards);
            for (Ask__c ask : asks) {
                board.cards.add(toCard(ask));
            }
            board.truncated = board.openCount > board.cards.size();
            Map<String, AskSelector.StageTotal> closed = AskSelector.closedThisFiscalYear(ownerId);
            AskSelector.StageTotal won = closed.get(AskRules.OUTCOME_WON);
            if (won != null) {
                board.wonCount = won.count;
                board.wonAmount = won.amount == null ? 0 : won.amount;
            }
            AskSelector.StageTotal declined = closed.get(AskRules.OUTCOME_DECLINED);
            board.declinedCount = declined == null ? 0 : declined.count;
            board.giftTypes = giftTypes();
            board.frequencies = frequencies();
            return board;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getBoard');
            throw UserErrors.message(Label.Giving_Ask_ErrorLoad);
        }
    }

    /** Moves one ask to another stage. The ask rules check the stage (R-SO2). */
    @AuraEnabled
    public static void moveStage(Id askId, String stage) {
        if (!Schema.SObjectType.Ask__c.isUpdateable()) {
            throw UserErrors.message(Label.Giving_Ask_ErrorNoPermission);
        }
        try {
            Database.update(new Ask__c(Id = askId, Stage__c = stage), true, AccessLevel.USER_MODE);
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.moveStage', askId);
            throw UserErrors.message(Label.Giving_Ask_ErrorUnexpected);
        }
    }

    /** Closes one ask, recording what a win produced (R-SO5). */
    @AuraEnabled
    public static CloseResult closeAsk(CloseInput input) {
        CloseResult result = new CloseResult();
        if (!Schema.SObjectType.Ask__c.isUpdateable()) {
            result.error = Label.Giving_Ask_ErrorNoPermission;
            return result;
        }
        Ask__c ask = input == null ? null : AskSelector.forClose(asId(input.askId));
        if (ask == null) {
            result.error = Label.Giving_Ask_ErrorNotFound;
            return result;
        }
        if (!AskRules.CLOSED_OUTCOMES.contains(input.outcome)) {
            result.error = Label.Giving_Ask_ErrorOutcome;
            return result;
        }
        Savepoint beforeClose = Database.setSavepoint();
        try {
            Ask__c closing = new Ask__c(
                Id = ask.Id,
                Outcome__c = input.outcome,
                Next_Ask_Date__c = input.nextAskDate
            );
            if (input.outcome == AskRules.OUTCOME_WON) {
                result.error = recordResult(ask, input, closing, result);
            }
            if (result.error != null) {
                Database.rollback(beforeClose);
                return result;
            }
            Database.update(closing, true, AccessLevel.USER_MODE);
            result.success = true;
            return result;
        } catch (DmlException e) {
            Database.rollback(beforeClose);
            result.giftId = null;
            result.commitmentId = null;
            result.error = e.getDmlMessage(0);
            return result;
        } catch (Exception e) {
            Database.rollback(beforeClose);
            ErrorLogger.log(e, CONTEXT + '.closeAsk', ask.Id);
            result.giftId = null;
            result.commitmentId = null;
            result.error = Label.Giving_Ask_ErrorUnexpected;
            return result;
        }
    }

    /**
     * Records or links what a won ask produced, setting the link on `closing`. Returns the sentence
     * to show when it cannot, or null.
     */
    private static String recordResult(
        Ask__c ask,
        CloseInput input,
        Ask__c closing,
        CloseResult result
    ) {
        String kind = String.isBlank(input.result) ? RESULT_LATER : input.result;
        if (kind == RESULT_LATER) {
            return null;
        }
        if (ask.Donor_Contact__c == null && ask.Donor_Account__c == null) {
            return Label.Giving_Ask_ErrorNoDonor;
        }
        if (kind == RESULT_GIFT) {
            return recordGift(ask, input, closing, result);
        }
        if (kind == RESULT_PLEDGE) {
            return recordPledge(ask, input, closing, result);
        }
        if (kind == RESULT_LINK) {
            return linkExisting(ask, input, closing);
        }
        return Label.Giving_Ask_ErrorOutcome;
    }

    /** The gift now, through Quick Gift Entry's save, so every gift rule applies. */
    private static String recordGift(
        Ask__c ask,
        CloseInput input,
        Ask__c closing,
        CloseResult result
    ) {
        QuickGiftEntryController.GiftInput gift = new QuickGiftEntryController.GiftInput();
        gift.donorContactId = ask.Donor_Contact__c;
        gift.donorAccountId = ask.Donor_Account__c;
        gift.amount = input.amount;
        gift.giftDate = input.giftDate;
        gift.giftType = input.giftType;
        gift.appealId = ask.Appeal__c;
        gift.fundId = ask.Fund__c;
        QuickGiftEntryController.SaveResult saved = QuickGiftEntryController.saveGift(gift);
        if (saved.success != true) {
            if (!saved.fieldErrors.isEmpty()) {
                return saved.fieldErrors[0].message;
            }
            return String.isBlank(saved.formError)
                ? Label.Giving_Ask_ErrorUnexpected
                : saved.formError;
        }
        closing.Gift__c = saved.giftId;
        result.giftId = saved.giftId;
        return null;
    }

    /**
     * A pledge for the total, in equal payments; the last payment takes up any rounding, as for any
     * pledge (R-CM5). Its schedule is generated by the commitment triggers.
     */
    private static String recordPledge(
        Ask__c ask,
        CloseInput input,
        Ask__c closing,
        CloseResult result
    ) {
        if (input.amount == null || input.amount <= 0) {
            return Label.Giving_Ask_ErrorAmount;
        }
        if (
            input.payments == null ||
            input.payments < 1 ||
            String.isBlank(input.frequency) ||
            input.giftDate == null
        ) {
            return Label.Giving_Ask_ErrorPledgeSchedule;
        }
        Commitment__c pledge = new Commitment__c(
            Type__c = TYPE_PLEDGE,
            Status__c = STATUS_ACTIVE,
            Donor_Contact__c = ask.Donor_Contact__c,
            Donor_Account__c = ask.Donor_Account__c,
            Expected_Total__c = input.amount.setScale(2),
            Installments_Planned__c = input.payments,
            Amount__c = (input.amount / input.payments).setScale(2, System.RoundingMode.DOWN),
            Frequency__c = input.frequency,
            Start_Date__c = input.giftDate,
            Appeal__c = ask.Appeal__c,
            Fund__c = ask.Fund__c
        );
        Database.insert(pledge, true, AccessLevel.USER_MODE);
        closing.Commitment__c = pledge.Id;
        result.commitmentId = pledge.Id;
        return null;
    }

    /** A gift or pledge already entered, which must be the same donor's. */
    private static String linkExisting(Ask__c ask, CloseInput input, Ask__c closing) {
        Id linked = asId(input.linkedId);
        if (linked == null) {
            return Label.Giving_Ask_ErrorChooseLink;
        }
        if (linked.getSObjectType() == Gift__c.SObjectType) {
            if (!AskSelector.isDonorsGift(linked, ask)) {
                return Label.Giving_Ask_ErrorWrongDonor;
            }
            closing.Gift__c = linked;
            return null;
        }
        if (linked.getSObjectType() == Commitment__c.SObjectType) {
            if (!AskSelector.isDonorsCommitment(linked, ask)) {
                return Label.Giving_Ask_ErrorWrongDonor;
            }
            closing.Commitment__c = linked;
            return null;
        }
        return Label.Giving_Ask_ErrorChooseLink;
    }

    private static Card toCard(Ask__c ask) {
        Card card = new Card();
        card.id = ask.Id;
        card.name = ask.Name;
        card.stage = ask.Stage__c;
        card.amount = ask.Amount__c;
        card.targetDate = ask.Target_Date__c;
        card.nextStep = ask.Next_Step__c;
        card.stageChangedDate = ask.Stage_Changed_Date__c;
        card.ownerName = ask.Owner?.Name;
        if (ask.Donor_Contact__c != null) {
            card.donorId = ask.Donor_Contact__c;
            card.donorName = ask.Donor_Contact__r?.Name;
        } else if (ask.Donor_Account__c != null) {
            card.donorId = ask.Donor_Account__c;
            card.donorName = ask.Donor_Account__r?.Name;
        }
        return card;
    }

    /** The ways a gift can arrive, without In-kind: a won ask is money. */
    private static List<Option> giftTypes() {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() != TYPE_IN_KIND) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static List<Option> frequencies() {
        List<Option> options = new List<Option>();
        for (
            Schema.PicklistEntry entry : Commitment__c.Frequency__c.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static Id asId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (StringException e) {
            return null;
        }
    }
}
