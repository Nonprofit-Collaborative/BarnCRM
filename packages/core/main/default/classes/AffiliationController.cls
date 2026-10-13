/**
 * The affiliation card's server side. Every method validates what it is given and returns a
 * typed result or a message the card can show a person (plan Section 7.2).
 *
 * One card serves both ends of the connection. On a person's record it lists the organizations
 * they are connected to; on an organization's record it lists the people. The card does not
 * have to be told which: an account can be an organization in one org and a person in another,
 * so the controller reads both sides for the record it is given and each row says which end of
 * itself the reader is looking at.
 */
public with sharing class AffiliationController {
    /** One affiliation as the card draws it. */
    public class AffiliationView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String affiliationNumber;
        @AuraEnabled
        public Id personId;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public Id organizationId;
        @AuraEnabled
        public String organizationName;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean isFormer;
        @AuraEnabled
        public Boolean isPrimary;
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Date endDate;
        @AuraEnabled
        public String description;
        /** True when the record the card sits on is the organization, so the row names a person. */
        @AuraEnabled
        public Boolean readFromOrganization;
    }

    /**
     * Every affiliation on file for one record, whether that record is the person or the
     * organization. Current ones first, and the primary one first among those.
     */
    @AuraEnabled(cacheable=true)
    public static List<AffiliationView> getAffiliations(Id ownerId) {
        if (ownerId == null) {
            throw ControllerErrors.messageFor(Label.Core_Affiliation_PersonRequired);
        }
        try {
            List<AffiliationView> views = toViews(
                AffiliationSelector.selectByPersonIds(new Set<Id>{ ownerId }),
                false
            );
            views.addAll(
                toViews(AffiliationSelector.selectByOrganizationIds(new Set<Id>{ ownerId }), true)
            );
            return views;
        } catch (Exception e) {
            ErrorLogger.log(e, 'AffiliationController.getAffiliations');
            throw ControllerErrors.messageFor(Label.Core_Affiliation_LoadFailed);
        }
    }

    /**
     * Makes one affiliation the primary one for its person and returns that record's
     * affiliations as they now stand. Clearing the flag from the person's other affiliations
     * and copying the organization to their Primary Affiliation field is the trigger's work,
     * not this method's.
     */
    @AuraEnabled
    public static List<AffiliationView> makePrimary(Id affiliationId, Id ownerId) {
        if (affiliationId == null || ownerId == null) {
            throw ControllerErrors.messageFor(Label.Core_Affiliation_NotFound);
        }
        try {
            Database.update(
                new List<Affiliation__c>{
                    new Affiliation__c(Id = affiliationId, Is_Primary__c = true)
                },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            ErrorLogger.log(e, 'AffiliationController.makePrimary');
            throw ControllerErrors.messageFor(Label.Core_Affiliation_MakePrimaryFailed);
        }
        return getAffiliations(ownerId);
    }

    private static List<AffiliationView> toViews(
        List<Affiliation__c> records,
        Boolean readFromOrganization
    ) {
        List<AffiliationView> views = new List<AffiliationView>();
        for (Affiliation__c record : records) {
            AffiliationView view = new AffiliationView();
            view.id = record.Id;
            view.affiliationNumber = record.Name;
            view.personId = PersonReference.idOf(record.Contact__c, record.Person_Account__c);
            view.personName = personName(record);
            view.organizationId = record.Organization__c;
            view.organizationName = record.Organization__r == null
                ? null
                : record.Organization__r.Name;
            view.role = record.Role__c;
            view.status = record.Status__c;
            view.isFormer = record.Status__c != ConnectionStatus.CURRENT;
            view.isPrimary = record.Is_Primary__c == true;
            view.startDate = record.Start_Date__c;
            view.endDate = record.End_Date__c;
            view.description = record.Description__c;
            view.readFromOrganization = readFromOrganization;
            views.add(view);
        }
        return views;
    }

    private static String personName(Affiliation__c record) {
        return PersonReference.nameOf(
            record.Contact__r,
            record.Person_Account__r,
            Label.Core_Affiliation_UnnamedPerson
        );
    }
}
