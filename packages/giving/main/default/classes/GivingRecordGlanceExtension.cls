/**
 * Giving at a Glance (people-14): the card Giving adds to Core's Contact and Account record
 * pages, so staff working in the BarnCRM app see what a donor gave and can enter a gift without
 * switching to BarnCRM Fundraising. Core finds this class by name (`RecordGlanceExtensions`,
 * ADR-0167) and draws what it returns.
 *
 * Everything is read with the viewer's own access. Someone who cannot read gifts, or the
 * giving fields, gets no card; the Enter a Gift button shows only to someone who can create a
 * gift. The figures are the rollups already on the record, so nothing is counted here.
 */
@NamespaceAccessible
public with sharing class GivingRecordGlanceExtension implements RecordGlanceExtension {
	@TestVisible
	private static final String QUICK_GIFT_ENTRY = 'Quick_Gift_Entry';
	@TestVisible
	private static final String ENTER_GIFT_ACTION = 'Enter_Gift';

	@NamespaceAccessible
	public GivingRecordGlanceExtension() {
		// Built by name from Core (RecordGlanceExtensions), so it needs a public constructor.
	}

	public RecordGlance.Card glance(Id recordId) {
		if (recordId == null || !Schema.SObjectType.Gift__c.isAccessible()) {
			return null;
		}
		Schema.SObjectType objectType = recordId.getSObjectType();
		SObject donor;
		try {
			if (objectType == Contact.SObjectType) {
				donor = firstOrNull(
					[
						SELECT Id, Total_Giving__c, Last_Gift_Date__c, Donor_Level__r.Name
						FROM Contact
						WHERE Id = :recordId
						WITH USER_MODE
					]
				);
			} else if (objectType == Account.SObjectType) {
				donor = firstOrNull(
					[
						SELECT Id, Total_Giving__c, Last_Gift_Date__c, Donor_Level__r.Name
						FROM Account
						WHERE Id = :recordId
						WITH USER_MODE
					]
				);
			}
		} catch (QueryException noAccess) {
			// The viewer cannot read the giving fields: no card, rather than an error on the page.
			return null;
		}
		if (donor == null) {
			return null;
		}
		return card(donor, objectType);
	}

	@TestVisible
	private static RecordGlance.Card card(SObject donor, Schema.SObjectType objectType) {
		Map<String, Schema.SObjectField> fields = objectType.getDescribe().fields.getMap();
		Decimal totalGiving = (Decimal) donor.get('Total_Giving__c');
		SObject levelRecord = donor.getSObject('Donor_Level__r');
		RecordGlance.Card card = new RecordGlance.Card(
				'giving',
				Label.Giving_Glance_Title,
				'custom:custom41'
			)
			.addCurrency(
				fields.get('Total_Giving__c').getDescribe().getLabel(),
				totalGiving == null ? 0 : totalGiving
			)
			.addDate(
				fields.get('Last_Gift_Date__c').getDescribe().getLabel(),
				(Date) donor.get('Last_Gift_Date__c')
			)
			.addText(
				fields.get('Donor_Level__c').getDescribe().getLabel(),
				levelRecord == null ? null : (String) levelRecord.get('Name')
			);
		if (Schema.SObjectType.Gift__c.isCreateable()) {
			card.addAction(enterGiftLabel(objectType), enterGiftReference((Id) donor.get('Id')));
		}
		return card;
	}

	/**
	 * The page reference Quick Gift Entry reads its donor from (the contract with the Quick Gift
	 * Entry page: `c__donorId` on the `Quick_Gift_Entry` tab).
	 */
	@TestVisible
	private static Map<String, Object> enterGiftReference(Id donorId) {
		return new Map<String, Object>{
			'type' => 'standard__navItemPage',
			'attributes' => new Map<String, Object>{
				'apiName' => NamespaceUtil.prefix() + QUICK_GIFT_ENTRY
			},
			'state' => new Map<String, Object>{ NamespaceUtil.stateKey('donorId') => donorId }
		};
	}

	/**
	 * The button reads like the donor page's own Enter_Gift action ("Enter a Gift"), so the two
	 * never disagree and no second label is kept; the Quick Gift Entry title when it cannot be read.
	 */
	@TestVisible
	private static String enterGiftLabel(Schema.SObjectType objectType) {
		String actionName =
			objectType.getDescribe().getName() +
			'.' +
			NamespaceUtil.prefix() +
			ENTER_GIFT_ACTION;
		try {
			List<QuickAction.DescribeQuickActionResult> described = QuickAction.describeQuickActions(
				new List<String>{ actionName }
			);
			if (!described.isEmpty() && String.isNotBlank(described[0].getLabel())) {
				return described[0].getLabel();
			}
		} catch (Exception notReadable) {
			// Falls through to the page title below.
		}
		return Label.Giving_QuickGiftEntry_Heading;
	}

	private static SObject firstOrNull(List<SObject> rows) {
		return rows.isEmpty() ? null : rows[0];
	}
}
