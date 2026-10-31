/**
 * The queries behind the Ask Pipeline board (canonical model Section 25O). Every query runs as the
 * person, so the board shows only the asks, donors and totals they may see.
 */
public with sharing class AskSelector {
    /** One stage's open asks: how many, and the sum of their ask amounts (R-SO6). */
    public class StageTotal {
        public String stage;
        public Integer count;
        public Decimal amount;
    }

    /** Open asks by stage, counted by the database so a long column is still totalled right. */
    public static List<StageTotal> openTotalsByStage(Id ownerId) {
        List<StageTotal> totals = new List<StageTotal>();
        List<AggregateResult> rows = ownerId == null
            ? [
                  SELECT Stage__c stage, COUNT(Id) asks, SUM(Amount__c) amount
                  FROM Ask__c
                  WHERE Outcome__c = :AskRules.OUTCOME_OPEN
                  WITH USER_MODE
                  GROUP BY Stage__c
              ]
            : [
                  SELECT Stage__c stage, COUNT(Id) asks, SUM(Amount__c) amount
                  FROM Ask__c
                  WHERE Outcome__c = :AskRules.OUTCOME_OPEN AND OwnerId = :ownerId
                  WITH USER_MODE
                  GROUP BY Stage__c
              ];
        for (AggregateResult row : rows) {
            StageTotal total = new StageTotal();
            total.stage = (String) row.get('stage');
            total.count = (Integer) row.get('asks');
            total.amount = (Decimal) row.get('amount');
            totals.add(total);
        }
        return totals;
    }

    /** Asks closed this fiscal year (by Closed Date), by outcome: count and ask amount (R-SO6). */
    public static Map<String, StageTotal> closedThisFiscalYear(Id ownerId) {
        Map<String, StageTotal> byOutcome = new Map<String, StageTotal>();
        List<AggregateResult> rows = ownerId == null
            ? [
                  SELECT Outcome__c outcome, COUNT(Id) asks, SUM(Amount__c) amount
                  FROM Ask__c
                  WHERE
                      Outcome__c IN :AskRules.CLOSED_OUTCOMES
                      AND Closed_Date__c = THIS_FISCAL_YEAR
                  WITH USER_MODE
                  GROUP BY Outcome__c
              ]
            : [
                  SELECT Outcome__c outcome, COUNT(Id) asks, SUM(Amount__c) amount
                  FROM Ask__c
                  WHERE
                      Outcome__c IN :AskRules.CLOSED_OUTCOMES
                      AND Closed_Date__c = THIS_FISCAL_YEAR
                      AND OwnerId = :ownerId
                  WITH USER_MODE
                  GROUP BY Outcome__c
              ];
        for (AggregateResult row : rows) {
            StageTotal total = new StageTotal();
            total.stage = (String) row.get('outcome');
            total.count = (Integer) row.get('asks');
            total.amount = (Decimal) row.get('amount');
            byOutcome.put(total.stage, total);
        }
        return byOutcome;
    }

    /** The open asks the board shows as cards, soonest target date first. */
    public static List<Ask__c> openAsks(Id ownerId, Integer maxRows) {
        return ownerId == null
            ? [
                  SELECT
                      Id,
                      Name,
                      Stage__c,
                      Amount__c,
                      Target_Date__c,
                      Next_Step__c,
                      Stage_Changed_Date__c,
                      Donor_Contact__c,
                      Donor_Contact__r.Name,
                      Donor_Account__c,
                      Donor_Account__r.Name,
                      Owner.Name
                  FROM Ask__c
                  WHERE Outcome__c = :AskRules.OUTCOME_OPEN
                  WITH USER_MODE
                  ORDER BY Target_Date__c ASC NULLS LAST, Amount__c DESC NULLS LAST, Name
                  LIMIT :maxRows
              ]
            : [
                  SELECT
                      Id,
                      Name,
                      Stage__c,
                      Amount__c,
                      Target_Date__c,
                      Next_Step__c,
                      Stage_Changed_Date__c,
                      Donor_Contact__c,
                      Donor_Contact__r.Name,
                      Donor_Account__c,
                      Donor_Account__r.Name,
                      Owner.Name
                  FROM Ask__c
                  WHERE Outcome__c = :AskRules.OUTCOME_OPEN AND OwnerId = :ownerId
                  WITH USER_MODE
                  ORDER BY Target_Date__c ASC NULLS LAST, Amount__c DESC NULLS LAST, Name
                  LIMIT :maxRows
              ];
    }

    /** One ask, with what closing it needs; null when the person cannot see it. */
    public static Ask__c forClose(Id askId) {
        List<Ask__c> asks = [
            SELECT Id, Outcome__c, Amount__c, Donor_Contact__c, Donor_Account__c, Fund__c, Appeal__c
            FROM Ask__c
            WHERE Id = :askId
            WITH USER_MODE
            LIMIT 1
        ];
        return asks.isEmpty() ? null : asks[0];
    }

    /** Whether a gift the person can see belongs to the ask's donor. */
    public static Boolean isDonorsGift(Id giftId, Ask__c ask) {
        return [
                SELECT COUNT()
                FROM Gift__c
                WHERE
                    Id = :giftId
                    AND ((Donor_Contact__c != NULL
                    AND Donor_Contact__c = :ask.Donor_Contact__c)
                    OR (Donor_Account__c != NULL
                    AND Donor_Account__c = :ask.Donor_Account__c))
                WITH USER_MODE
            ] == 1;
    }

    /** Whether a commitment the person can see belongs to the ask's donor. */
    public static Boolean isDonorsCommitment(Id commitmentId, Ask__c ask) {
        return [
                SELECT COUNT()
                FROM Commitment__c
                WHERE
                    Id = :commitmentId
                    AND ((Donor_Contact__c != NULL
                    AND Donor_Contact__c = :ask.Donor_Contact__c)
                    OR (Donor_Account__c != NULL
                    AND Donor_Account__c = :ask.Donor_Account__c))
                WITH USER_MODE
            ] == 1;
    }
}
