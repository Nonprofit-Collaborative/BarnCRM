/**
 * Reads service counts (P-12, canonical model 29ZB1). Counts carry no person, so they follow the
 * user's own access: user mode, with sharing.
 */
public with sharing class ServiceCountSelector {
	/** How many people were counted for this service on this day, all rows added up. */
	public static Integer totalOn(Id serviceId, Date countDate) {
		List<AggregateResult> rows = [
			SELECT SUM(People_Served__c) total
			FROM Service_Count__c
			WHERE Service__c = :serviceId AND Count_Date__c = :countDate
			WITH USER_MODE
		];
		Decimal total = rows.isEmpty() ? null : (Decimal) rows[0].get('total');
		return total == null ? 0 : total.intValue();
	}
}
