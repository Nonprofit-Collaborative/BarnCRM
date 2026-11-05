/**
 * The rules a tribute is saved by, and the gift reference it keeps in step (feature G-09).
 *
 * Before the save: one tribute per gift, an honoree who is named one way or another, and the
 * memorial rule that a gift in memory of someone who has died never notifies that same person
 * (R-TR6). Ticking the sent box stamps the date here, so the date is right however the box was
 * ticked.
 *
 * After the save: the gift's tribute reference is written, because it is a mirror the package
 * maintains rather than something a person fills in (R-G8).
 */
@NamespaceAccessible
public with sharing class TributeTriggerHandler extends TriggerHandler {
	@NamespaceAccessible
	public TributeTriggerHandler() {
		return;
	}

	public override void beforeInsert() {
		List<Tribute__c> tributes = asTributes(newRecords());
		TributeService.rejectSecondTribute(tributes);
		TributeService.validate(tributes);
		TributeService.stampSentDates(tributes, null);
	}

	public override void beforeUpdate() {
		List<Tribute__c> tributes = asTributes(newRecords());
		TributeService.validate(tributes);
		TributeService.stampSentDates(tributes, priorById(oldRecordsById()));
	}

	public override void afterInsert() {
		TributeService.mirrorOnGifts(asTributes(newRecords()), true);
	}

	public override void afterDelete() {
		TributeService.mirrorOnGifts(asTributes(oldRecords()), false);
	}

	private static Map<Id, Tribute__c> priorById(Map<Id, SObject> oldRecordsById) {
		Map<Id, Tribute__c> prior = new Map<Id, Tribute__c>();
		if (oldRecordsById == null) {
			return prior;
		}
		for (Id recordId : oldRecordsById.keySet()) {
			prior.put(recordId, (Tribute__c) oldRecordsById.get(recordId));
		}
		return prior;
	}

	private static List<Tribute__c> asTributes(List<SObject> records) {
		List<Tribute__c> tributes = new List<Tribute__c>();
		if (records == null) {
			return tributes;
		}
		for (SObject record : records) {
			tributes.add((Tribute__c) record);
		}
		return tributes;
	}
}
