/**
 * The relationship card's server side. Every method validates what it is given and returns a
 * typed result or a message the card can show a person (plan Section 7.2).
 *
 * The card sits on a person's record, and a person's record is a Contact in one org and an
 * Account in another. Nothing here asks which: the record id is passed straight to the
 * selector, which reads the relationships described from that person whichever lookup holds
 * them.
 */
public with sharing class RelationshipController {
    /** One relationship as the card draws it, always from this person's side. */
    public class RelationshipView {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String relationshipNumber;
        @AuraEnabled
        public Id relatedPersonId;
        @AuraEnabled
        public String relatedPersonName;
        @AuraEnabled
        public String relationshipType;
        @AuraEnabled
        public String reciprocalType;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean isFormer;
        @AuraEnabled
        public Date startDate;
        @AuraEnabled
        public Date endDate;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean isReciprocalManaged;
        @AuraEnabled
        public Boolean hasOtherSide;
    }

    /** Every relationship on file for one person, current ones first. */
    @AuraEnabled(cacheable=true)
    public static List<RelationshipView> getRelationships(Id personId) {
        if (personId == null) {
            throw ControllerErrors.messageFor(Label.Core_Relationship_PersonRequired);
        }
        try {
            return toViews(RelationshipSelector.selectByFromPersonIds(new Set<Id>{ personId }));
        } catch (Exception e) {
            ErrorLogger.log(e, 'RelationshipController.getRelationships');
            throw ControllerErrors.messageFor(Label.Core_Relationship_LoadFailed);
        }
    }

    /**
     * Removes one relationship and returns what this person has left. Deleting the other side
     * is the trigger's work, not this method's, which is why a person only ever has one thing
     * to remove.
     */
    @AuraEnabled
    public static List<RelationshipView> removeRelationship(Id relationshipId, Id personId) {
        if (relationshipId == null || personId == null) {
            throw ControllerErrors.messageFor(Label.Core_Relationship_RemoveFailed);
        }
        try {
            Database.delete(
                new List<Relationship__c>{ new Relationship__c(Id = relationshipId) },
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            ErrorLogger.log(e, 'RelationshipController.removeRelationship');
            throw ControllerErrors.messageFor(Label.Core_Relationship_RemoveFailed);
        }
        return getRelationships(personId);
    }

    private static List<RelationshipView> toViews(List<Relationship__c> records) {
        List<RelationshipView> views = new List<RelationshipView>();
        for (Relationship__c record : records) {
            RelationshipView view = new RelationshipView();
            view.id = record.Id;
            view.relationshipNumber = record.Name;
            view.relatedPersonId = PersonReference.idOf(
                record.Related_Contact__c,
                record.Related_Person_Account__c
            );
            view.relatedPersonName = relatedName(record);
            view.relationshipType = record.Type__c;
            view.reciprocalType = record.Reciprocal_Type__c;
            view.status = record.Status__c;
            view.isFormer = record.Status__c != ConnectionStatus.CURRENT;
            view.startDate = record.Start_Date__c;
            view.endDate = record.End_Date__c;
            view.description = record.Description__c;
            view.isReciprocalManaged = record.Is_Reciprocal_Managed__c == true;
            view.hasOtherSide = record.Reciprocal_Relationship__c != null;
            views.add(view);
        }
        return views;
    }

    private static String relatedName(Relationship__c record) {
        return PersonReference.nameOf(
            record.Related_Contact__r,
            record.Related_Person_Account__r,
            Label.Core_Relationship_UnnamedPerson
        );
    }
}
