/**
 * The Giving Fund card on a grant's page (F-03, canonical model 29ZH R-GN8, ADR-0162
 * `0162-funders-restricted-funds-schedules-calendar.md` decision 4): the Giving fund the grant's
 * money is booked to, the active funds to choose from where Giving is installed, and saving the
 * choice. The card's restricted totals are the grant's own fields, read by the page.
 *
 * Thin by design (plan Section 9.9): plain shapes out, the rules in `GrantFundService`.
 * Everything runs as the person.
 */
public with sharing class GrantFundController {
    private static final String CONTEXT = 'GrantFundController';

    /** What the card draws. */
    public class FundCard {
        /** Whether Giving is installed and the person can read funds. */
        @AuraEnabled
        public Boolean available = false;
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public String fundId;
        @AuraEnabled
        public String fundName;
        /** A fund is named but cannot be found: deleted, or not visible to the person. */
        @AuraEnabled
        public Boolean missing = false;
        /** The card's title: the Giving Fund field's label, read by describe. */
        @AuraEnabled
        public String title;
        @AuraEnabled
        public List<GrantProgramController.Option> options = new List<GrantProgramController.Option>();
    }

    /** The card for one grant. */
    @AuraEnabled
    public static FundCard getFund(Id grantId) {
        try {
            FundCard card = new FundCard();
            card.title = Schema.SObjectType.Grant__c.fields.Fund_Id__c.getLabel();
            List<Grant__c> grants = [
                SELECT Id, Fund_Id__c
                FROM Grant__c
                WHERE Id = :grantId
                WITH USER_MODE
                LIMIT 1
            ];
            if (grants.isEmpty()) {
                return card;
            }
            card.fundId = grants[0].Fund_Id__c;
            card.available = GrantFundService.fundsAvailable();
            card.canEdit =
                card.available && Schema.SObjectType.Grant__c.fields.Fund_Id__c.isUpdateable();
            if (!card.available) {
                return card;
            }
            for (Map<String, String> fund : GrantFundService.funds()) {
                card.options.add(
                    new GrantProgramController.Option(fund.get('label'), fund.get('value'))
                );
            }
            if (String.isNotBlank(card.fundId)) {
                card.fundName = GrantFundService.fundName(card.fundId);
                card.missing = card.fundName == null;
            }
            return card;
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getFund', grantId);
            throw UserErrors.message(Label.Funders_Pipeline_ErrorUnexpected);
        }
    }

    /** Names the fund the grant's money is booked to, or clears it when `fundId` is blank. */
    @AuraEnabled
    public static void setFund(Id grantId, String fundId) {
        if (!Schema.SObjectType.Grant__c.fields.Fund_Id__c.isUpdateable()) {
            throw UserErrors.message(Label.Funders_Pipeline_ErrorNoPermission);
        }
        try {
            GrantFundService.setFund(grantId, fundId);
        } catch (GrantService.GrantException e) {
            throw UserErrors.message(e.getMessage());
        } catch (DmlException e) {
            throw UserErrors.message(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.setFund', grantId);
            throw UserErrors.message(Label.Funders_Pipeline_ErrorUnexpected);
        }
    }
}
