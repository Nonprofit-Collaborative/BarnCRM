/**
 * What the tribute panel on a gift calls (feature G-09).
 *
 * The panel shows the tribute in words rather than in fields, because what a person needs to
 * check before posting a letter is "in memory of Rosa Garcia, notify Ana Garcia, not yet sent",
 * not a list of lookups.
 */
public with sharing class TributeController {
    private static final String CONTEXT = 'Tribute panel';

    public class TributeView {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String tributeType;
        @AuraEnabled
        public String honoreeName;
        @AuraEnabled
        public String recipientName;
        @AuraEnabled
        public String message;
        @AuraEnabled
        public Boolean notificationSent;
        @AuraEnabled
        public Date notificationSentDate;
        @AuraEnabled
        public Boolean canMarkSent = false;
        /**
         * Why there is nothing to send, when there is nothing to send. A tribute with no
         * recipient recorded is a common and recoverable state, not an error, so the panel says
         * so rather than quietly hiding its button (R-TR3).
         */
        @AuraEnabled
        public String blockedReason;
    }

    @AuraEnabled(cacheable=true)
    public static TributeView getTribute(Id giftId) {
        if (giftId == null) {
            throw UserErrors.message(Label.Giving_TributeNotification_NotFound);
        }
        try {
            return viewFor(giftId);
        } catch (Exception failure) {
            throw report(failure, giftId);
        }
    }

    @AuraEnabled
    public static TributeView markNotificationSent(Id tributeId) {
        if (tributeId == null) {
            throw UserErrors.message(Label.Giving_TributeNotification_NotFound);
        }
        try {
            List<Tribute__c> found = TributeSelector.selectByIds(new Set<Id>{ tributeId });
            if (found.isEmpty()) {
                throw UserErrors.message(Label.Giving_TributeNotification_NotFound);
            }
            Id giftId = found[0].Gift__c;
            TributeService.markNotificationSent(new Set<Id>{ tributeId });
            return viewFor(giftId);
        } catch (AuraHandledException refused) {
            throw refused;
        } catch (Exception failure) {
            throw report(failure, tributeId);
        }
    }

    private static TributeView viewFor(Id giftId) {
        List<Tribute__c> tributes = TributeSelector.selectForGifts(new Set<Id>{ giftId });
        if (tributes.isEmpty()) {
            return null;
        }
        Tribute__c tribute = tributes[0];
        TributeView view = new TributeView();
        view.recordId = tribute.Id;
        view.name = tribute.Name;
        view.tributeType = tribute.Type__c;
        view.honoreeName = firstPresent(
            tribute.Honoree_Contact__r == null ? null : tribute.Honoree_Contact__r.Name,
            tribute.Honoree_Account__r == null ? null : tribute.Honoree_Account__r.Name,
            tribute.Honoree_Name__c
        );
        view.recipientName = firstPresent(
            tribute.Notification_Recipient_Contact__r == null
                ? null
                : tribute.Notification_Recipient_Contact__r.Name,
            tribute.Notification_Recipient_Account__r == null
                ? null
                : tribute.Notification_Recipient_Account__r.Name,
            tribute.Notification_Recipient_Name__c
        );
        view.message = tribute.Message__c;
        view.notificationSent = tribute.Notification_Sent__c == true;
        view.notificationSentDate = tribute.Notification_Sent_Date__c;
        Boolean hasRecipient = String.isNotBlank(view.recipientName);
        view.canMarkSent =
            Tribute__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).isUpdateable() &&
            view.notificationSent == false &&
            hasRecipient;
        if (!hasRecipient && view.notificationSent == false) {
            view.blockedReason = Label.Giving_TributeNotification_NoRecipient;
        }
        return view;
    }

    private static String firstPresent(String first, String second, String third) {
        if (String.isNotBlank(first)) {
            return first;
        }
        if (String.isNotBlank(second)) {
            return second;
        }
        return String.isBlank(third) ? null : third;
    }

    private static AuraHandledException report(Exception failure, Id recordId) {
        ErrorLogger.log(failure, CONTEXT, recordId);
        return UserErrors.message(Label.Giving_TributeNotification_ActionFailed);
    }
}
