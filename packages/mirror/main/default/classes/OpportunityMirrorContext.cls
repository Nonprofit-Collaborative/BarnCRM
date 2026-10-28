/**
 * What one copy of gifts to Opportunities reads, read once for all the gifts in it (feature
 * X-01, R-OM3): the Opportunities already linked, the appeals' Campaigns, the donors' names and
 * person contacts, and what the org's schema and the saver's access offer (the Donation record
 * type, the Donor role, the Campaign field). Used by `OpportunityMirrorService`.
 *
 * It also resolves Opportunity and its contact roles through describe, so Mirror installs and
 * compiles where they do not exist (plan Section 4.2, R-OM1).
 *
 * Campaign is written only when the saver may read Campaigns and the appeal's Campaign ID, and
 * edit the Opportunity's Campaign: otherwise it is left out of the copy entirely, so the
 * Opportunity's Campaign is never cleared for want of access, and a saver who cannot see either
 * still has gifts with an appeal copied, rather than every one refused.
 */
public with sharing class OpportunityMirrorContext {
    private static final String DONATION_RECORD_TYPE = 'Donation';
    // detection-only: Opportunity is resolved through describe so Mirror installs without it
    private static final String OPPORTUNITY_OBJECT = 'Opportunity';
    // detection-only: its contact roles are resolved the same way
    private static final String ROLE_OBJECT = 'OpportunityContactRole';
    public static final String CAMPAIGN_FIELD = 'CampaignId';
    public static final String DONOR_ROLE = 'Donor';
    /** The Opportunity field each copied gift attribute is compared on (R-OM3). */
    public static final List<String> COMPARED = new List<String>{
        'Amount',
        'CloseDate',
        'StageName',
        'AccountId'
    };

    private static Schema.SObjectType resolvedOpportunity;
    private static Schema.SObjectType resolvedRole;
    private static Boolean typesResolved = false;

    public final Map<Id, SObject> current;
    public final Boolean hasCampaign;
    public final Boolean donorRoleExists;
    private final Map<Id, String> campaignByAppeal = new Map<Id, String>();
    private final Map<Id, String> names;
    private final Map<Id, Id> personContactByAccount;
    private final Id donationRecordTypeId;
    private final Schema.SObjectType campaignType;

    public OpportunityMirrorContext(List<Gift__c> gifts) {
        Schema.DescribeSObjectResult describe = opportunityType().getDescribe();
        Schema.SObjectField campaignField = describe.fields.getMap()
            .get(CAMPAIGN_FIELD.toLowerCase());
        campaignType = CampaignSyncService.campaignType();
        hasCampaign =
            campaignField != null &&
            campaignType != null &&
            campaignType.getDescribe().isAccessible() &&
            campaignField.getDescribe().isAccessible() &&
            campaignField.getDescribe().isCreateable() &&
            campaignField.getDescribe().isUpdateable() &&
            Appeal__c.Campaign_Id__c.getDescribe().isAccessible();
        Schema.RecordTypeInfo donation = describe.getRecordTypeInfosByDeveloperName()
            .get(DONATION_RECORD_TYPE);
        donationRecordTypeId = donation != null &&
            donation.isActive() &&
            donation.isAvailable()
            ? donation.getRecordTypeId()
            : null;
        donorRoleExists = hasActiveValue(
            roleType().getDescribe().fields.getMap().get('role'),
            DONOR_ROLE
        );

        Set<Id> linkedIds = new Set<Id>();
        Set<Id> appealIds = new Set<Id>();
        // Names are needed only for a new Opportunity, person contacts for every role.
        Set<Id> namedContactIds = new Set<Id>();
        Set<Id> namedAccountIds = new Set<Id>();
        Set<Id> donorAccountIds = new Set<Id>();
        for (Gift__c gift : gifts) {
            if (gift.Opportunity_Id__c != null) {
                linkedIds.add(Id.valueOf(gift.Opportunity_Id__c));
            } else {
                addIfSet(namedContactIds, gift.Donor_Contact__c);
                addIfSet(namedAccountIds, gift.Donor_Account__c);
            }
            addIfSet(appealIds, gift.Appeal__c);
            if (gift.Donor_Contact__c == null) {
                addIfSet(donorAccountIds, gift.Donor_Account__c);
            }
        }
        List<String> read = new List<String>{ 'Id' };
        read.addAll(COMPARED);
        if (hasCampaign) {
            read.add(CAMPAIGN_FIELD);
        }
        current = OpportunityMirrorSelector.opportunitiesById(describe.getName(), read, linkedIds);
        if (hasCampaign && !appealIds.isEmpty()) {
            campaignByAppeal.putAll(CampaignSyncSelector.campaignIdsByAppealId(appealIds));
        }
        names = OpportunityMirrorSelector.namesById(namedContactIds, namedAccountIds);
        personContactByAccount = OpportunityMirrorSelector.personContactIds(donorAccountIds);
    }

    /** The Opportunity object, or null in an org without it (a Platform-only org). */
    public static Schema.SObjectType opportunityType() {
        resolveTypes();
        return resolvedOpportunity;
    }

    /** OpportunityContactRole, or null in an org without it. */
    public static Schema.SObjectType roleType() {
        resolveTypes();
        return resolvedRole;
    }

    private static void resolveTypes() {
        if (!typesResolved) {
            Map<String, Schema.SObjectType> globals = NamespaceUtil.globalDescribe();
            resolvedOpportunity = globals.get(OPPORTUNITY_OBJECT);
            resolvedRole = globals.get(ROLE_OBJECT);
            typesResolved = true;
        }
    }

    /** The person on the primary contact role: the donor contact, or a person account's. */
    public Id personOf(Gift__c gift) {
        if (gift.Donor_Contact__c != null) {
            return gift.Donor_Contact__c;
        }
        return gift.Donor_Account__c == null
            ? null
            : personContactByAccount.get(gift.Donor_Account__c);
    }

    /**
     * The Opportunity as the gift says it should be (R-OM3). The stage is left out when null,
     * for the caller to fill from the Opportunity as it is.
     */
    public SObject desiredOpportunity(Gift__c gift, String stageName) {
        SObject opportunity = opportunityType().newSObject();
        opportunity.put('Amount', gift.Amount__c);
        opportunity.put('CloseDate', gift.Gift_Date__c);
        if (stageName != null) {
            opportunity.put('StageName', stageName);
        }
        opportunity.put(
            'AccountId',
            gift.Donor_Account__c != null ? gift.Donor_Account__c : gift.Household__c
        );
        if (hasCampaign) {
            Id campaignId = gift.Appeal__c == null
                ? null
                : MirrorSync.idOf(campaignByAppeal.get(gift.Appeal__c), campaignType);
            opportunity.put(CAMPAIGN_FIELD, campaignId);
        }
        return opportunity;
    }

    /** What only a new Opportunity gets: its name and the Donation record type. */
    public void prepareNew(SObject opportunity, Gift__c gift) {
        Id donor = gift.Donor_Contact__c != null ? gift.Donor_Contact__c : gift.Donor_Account__c;
        String donorName = names.containsKey(donor)
            ? names.get(donor)
            : Label.Mirror_OpportunityMirror_UnknownDonor;
        opportunity.put(
            'Name',
            String.format(
                    Label.Mirror_OpportunityMirror_OpportunityName,
                    new List<Object>{ donorName, String.valueOf(gift.Gift_Date__c) }
                )
                .left(120)
        );
        if (donationRecordTypeId != null) {
            opportunity.put('RecordTypeId', donationRecordTypeId);
        }
    }

    /** Whether the Opportunity as it is differs from what the gift says in a copied field. */
    public Boolean differs(SObject desired, SObject existing) {
        List<String> fields = new List<String>(COMPARED);
        if (hasCampaign) {
            fields.add(CAMPAIGN_FIELD);
        }
        for (String field : fields) {
            if (!MirrorSync.same(desired.get(field), existing.get(field))) {
                return true;
            }
        }
        return false;
    }

    private static void addIfSet(Set<Id> ids, Id value) {
        if (value != null) {
            ids.add(value);
        }
    }

    private static Boolean hasActiveValue(Schema.SObjectField field, String value) {
        if (field == null) {
            return false;
        }
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() == value) {
                return true;
            }
        }
        return false;
    }
}
