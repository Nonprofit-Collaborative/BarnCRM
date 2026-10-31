/**
 * What the soft credits panel on a gift calls (feature G-08).
 *
 * Every method validates what it was given and answers with a typed result or with a message the
 * component can show a person (plan Section 7.2). Anything unexpected is recorded in the Error
 * Log before it is reported, so that a failure nobody read is still findable.
 */
public with sharing class SoftCreditController {
    private static final String CONTEXT = 'Soft credits panel';

    /**
     * One line of the panel.
     */
    public class SoftCreditView {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Id personId;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String customRole;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Decimal percent;
        @AuraEnabled
        public Boolean isAutomatic;
    }

    /**
     * The panel's whole state: the credits, and whether this person may change them.
     */
    public class SoftCreditPanel {
        @AuraEnabled
        public List<SoftCreditView> credits = new List<SoftCreditView>();
        @AuraEnabled
        public Boolean canAdd = false;
        @AuraEnabled
        public Boolean canRemove = false;
    }

    @AuraEnabled(cacheable=true)
    public static SoftCreditPanel getCredits(Id giftId) {
        if (giftId == null) {
            throw UserErrors.message(Label.Giving_SoftCredit_GiftRequired);
        }
        try {
            return panelFor(giftId);
        } catch (Exception failure) {
            throw report(failure, giftId);
        }
    }

    /**
     * Adds a credit a person entered. Never marked automatic, so package maintenance leaves it
     * alone for ever after (R-SC6).
     */
    @AuraEnabled
    public static SoftCreditPanel addCredit(
        Id giftId,
        Id personId,
        String role,
        String customRole,
        Decimal amount
    ) {
        if (giftId == null) {
            throw UserErrors.message(Label.Giving_SoftCredit_GiftRequired);
        }
        if (personId == null) {
            throw UserErrors.message(Label.Giving_SoftCredit_OneCreditedParty);
        }
        try {
            Soft_Credit__c credit = new Soft_Credit__c(
                Gift__c = giftId,
                Role__c = String.isBlank(role) ? 'Influencer' : role,
                Custom_Role__c = customRole,
                Amount__c = amount,
                Is_Automatic__c = false
            );
            if (personId.getSObjectType() == Contact.SObjectType) {
                credit.Contact__c = personId;
            } else {
                credit.Account__c = personId;
            }
            Database.insert(new List<Soft_Credit__c>{ credit }, true, AccessLevel.USER_MODE);
            return panelFor(giftId);
        } catch (Exception failure) {
            throw report(failure, giftId);
        }
    }

    /**
     * Removes a credit a person entered. An automatic credit is not removable here, because it
     * would come straight back the next time the gift was saved; the panel hides its button and
     * this is the second line of that defence.
     */
    @AuraEnabled
    public static SoftCreditPanel removeCredit(Id softCreditId) {
        if (softCreditId == null) {
            throw UserErrors.message(Label.Giving_SoftCredits_ActionFailed);
        }
        try {
            List<Soft_Credit__c> found = SoftCreditSelector.selectByIds(
                new Set<Id>{ softCreditId }
            );
            if (found.isEmpty()) {
                throw UserErrors.message(Label.Giving_SoftCredits_ActionFailed);
            }
            Soft_Credit__c credit = found[0];
            if (credit.Is_Automatic__c == true) {
                throw UserErrors.message(Label.Giving_SoftCredits_AutomaticHelp);
            }
            Id giftId = credit.Gift__c;
            Database.delete(new List<Soft_Credit__c>{ credit }, true, AccessLevel.USER_MODE);
            return panelFor(giftId);
        } catch (AuraHandledException refused) {
            throw refused;
        } catch (Exception failure) {
            throw report(failure, softCreditId);
        }
    }

    private static SoftCreditPanel panelFor(Id giftId) {
        SoftCreditPanel panel = new SoftCreditPanel();
        Schema.DescribeSObjectResult describe = Soft_Credit__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        panel.canAdd = describe.isCreateable();
        panel.canRemove = describe.isDeletable();
        for (Soft_Credit__c credit : SoftCreditSelector.selectForGifts(new Set<Id>{ giftId })) {
            SoftCreditView view = new SoftCreditView();
            view.recordId = credit.Id;
            view.name = credit.Name;
            view.role = credit.Role__c;
            view.customRole = credit.Custom_Role__c;
            view.amount = credit.Amount__c;
            view.percent = credit.Percent__c;
            view.isAutomatic = credit.Is_Automatic__c == true;
            if (credit.Contact__c != null) {
                view.personId = credit.Contact__c;
                view.personName = credit.Contact__r == null ? null : credit.Contact__r.Name;
            } else {
                view.personId = credit.Account__c;
                view.personName = credit.Account__r == null ? null : credit.Account__r.Name;
            }
            panel.credits.add(view);
        }
        return panel;
    }

    private static AuraHandledException report(Exception failure, Id recordId) {
        ErrorLogger.log(failure, CONTEXT, recordId);
        return UserErrors.message(Label.Giving_SoftCredits_ActionFailed);
    }
}
