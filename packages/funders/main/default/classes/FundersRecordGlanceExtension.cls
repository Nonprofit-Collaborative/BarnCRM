/**
 * Grants at a Glance on Core's record pages (modules-21, ADR-0167): a funder organization's
 * grants, or those a person is funder contact on. Read with the viewer's access; null when
 * there is no grant or no access.
 */
@NamespaceAccessible
public with sharing class FundersRecordGlanceExtension implements RecordGlanceExtension {
	@TestVisible
	private static final String KEY = 'funders';

	/** Built by name from Core. */
	@NamespaceAccessible
	public FundersRecordGlanceExtension() {
		return;
	}

	public RecordGlance.Card glance(Id recordId) {
		Schema.SObjectType parent = recordId?.getSObjectType();
		if (
			(parent != Account.SObjectType && parent != Contact.SObjectType) ||
			!Schema.SObjectType.Grant__c.isAccessible()
		) {
			return null;
		}
		Integer total = 0;
		Integer open = 0;
		for (AggregateResult row : [
			SELECT Stage__c stage, COUNT(Id) total
			FROM Grant__c
			WHERE Funder__c = :recordId OR Funder_Contact__c = :recordId
			WITH USER_MODE
			GROUP BY Stage__c
		]) {
			Integer count = (Integer) row.get('total');
			total += count;
			open += GrantService.OPEN_STAGES.contains((String) row.get('stage')) ? count : 0;
		}
		if (total == 0) {
			return null;
		}
		RecordGlance.Card card = new RecordGlance.Card(
				KEY,
				Label.Funders_Glance_Title,
				'custom:custom8'
			)
			.addNumber(Schema.SObjectType.Grant__c.getLabelPlural(), total)
			.addNumber(Label.Funders_Glance_OpenGrants, open);
		Schema.DescribeFieldResult amount = Schema.SObjectType.Grant__c.fields.Amount_Awarded__c;
		if (amount.isAccessible()) {
			Decimal awarded = (Decimal) [
					SELECT SUM(Amount_Awarded__c) awarded
					FROM Grant__c
					WHERE
						(Funder__c = :recordId
						OR Funder_Contact__c = :recordId)
						AND Stage__c = :GrantService.STAGE_AWARDED
					WITH USER_MODE
				][0]
				.get('awarded');
			card.addCurrency(amount.getLabel(), awarded == null ? 0 : awarded);
		}
		return card.addRelatedListAction(
			Label.Funders_Glance_ViewGrants,
			recordId,
			parent == Account.SObjectType ? Grant__c.Funder__c : Grant__c.Funder_Contact__c
		);
	}
}
