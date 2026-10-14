/**
 * The affiliation card's one server call. The card reads affiliations through GraphQL and
 * saves through Lightning Data Service (ADR-0093); only which lookups a new affiliation fills
 * in needs the server, because it depends on the record's type and the org's shape.
 */
public with sharing class AffiliationController {
    /**
     * Which lookups a new affiliation added from this record's card fills in: the record's
     * own (`ownerField`) and the other end's (`otherEndField`).
     */
    public class CardContext {
        @AuraEnabled
        public String ownerField;
        @AuraEnabled
        public String otherEndField;
    }

    /**
     * Decided from the record itself, never from the affiliations already on file, so an
     * organization with no affiliations yet is still read as an organization. A contact and
     * a person account are people; any other account is the organization end, and the
     * person at the other end is a contact, or a person account in an org that stores
     * people as accounts.
     */
    @AuraEnabled(cacheable=true)
    public static CardContext getCardContext(Id recordId) {
        CardContext context = new CardContext();
        context.ownerField = 'Contact__c';
        context.otherEndField = 'Organization__c';
        if (recordId == null || recordId.getSObjectType() != Account.SObjectType) {
            return context;
        }
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        if (personTypes != null && !personTypes.isEmpty()) {
            for (
                Account record : HouseholdSelector.getAccountRecordTypes(new Set<Id>{ recordId })
            ) {
                if (personTypes.contains(record.RecordTypeId)) {
                    context.ownerField = 'Person_Account__c';
                    return context;
                }
            }
        }
        context.ownerField = 'Organization__c';
        context.otherEndField = HouseholdService.isPersonAccountOrg()
            ? 'Person_Account__c'
            : 'Contact__c';
        return context;
    }
}
