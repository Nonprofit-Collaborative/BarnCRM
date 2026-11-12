/**
 * Tributes: the honor or memorial a gift was given under, and who to tell (feature G-09,
 * canonical model Section 25).
 *
 * Two rules live here rather than in a validation rule, because both need to read another
 * record. The first is R-TR6: a gift in memory of someone who has died may not name that same
 * person as the person to notify. The second is R-TR1: a gift has at most one tribute.
 *
 * Marking a notification sent stamps the date. Neither the flag nor the date is ever cleared by
 * automation, because together they are the record of what the organization did (R-TR4).
 */
public with sharing class TributeService {
	public static final String TYPE_IN_MEMORY_OF = 'In memory of';
	public static final String TYPE_IN_HONOR_OF = 'In honor of';

	/**
	 * Records that the notification for these tributes has gone out, and when. A tribute already
	 * marked sent keeps the date it already had.
	 */
	public static List<Tribute__c> markNotificationSent(Set<Id> tributeIds) {
		List<Tribute__c> changed = new List<Tribute__c>();
		if (tributeIds == null || tributeIds.isEmpty()) {
			return changed;
		}
		Date today = Date.today();
		for (Tribute__c tribute : TributeSelector.selectByIds(tributeIds)) {
			if (tribute.Notification_Sent__c == true && tribute.Notification_Sent_Date__c != null) {
				continue;
			}
			tribute.Notification_Sent__c = true;
			if (tribute.Notification_Sent_Date__c == null) {
				tribute.Notification_Sent_Date__c = today;
			}
			changed.add(tribute);
		}
		if (!changed.isEmpty()) {
			// Only the fields being changed: a user mode update of the rows as read would also
			// carry the master detail to the gift, which nobody may edit.
			List<Tribute__c> updates = new List<Tribute__c>();
			for (Tribute__c tribute : changed) {
				updates.add(
					new Tribute__c(
						Id = tribute.Id,
						Notification_Sent__c = tribute.Notification_Sent__c,
						Notification_Sent_Date__c = tribute.Notification_Sent_Date__c
					)
				);
			}
			Database.update(updates, true, AccessLevel.USER_MODE);
		}
		return changed;
	}

	/**
	 * Stamps the sent date on any tribute whose sent flag has just been ticked, so that the date
	 * is right whether it was ticked on the record page, by the component, or by an import.
	 */
	public static void stampSentDates(List<Tribute__c> tributes, Map<Id, Tribute__c> priorById) {
		if (tributes == null) {
			return;
		}
		Date today = Date.today();
		for (Tribute__c tribute : tributes) {
			Boolean wasSent = false;
			if (priorById != null && tribute.Id != null && priorById.containsKey(tribute.Id)) {
				wasSent = priorById.get(tribute.Id).Notification_Sent__c == true;
			}
			if (tribute.Notification_Sent__c == true && !wasSent) {
				if (tribute.Notification_Sent_Date__c == null) {
					tribute.Notification_Sent_Date__c = today;
				}
			}
		}
	}

	/**
	 * Refuses a memorial that would send its notification to the person it remembers, and a
	 * tribute with nobody named as the honoree.
	 */
	public static void validate(List<Tribute__c> tributes) {
		if (tributes == null || tributes.isEmpty()) {
			return;
		}
		Set<Id> honoreeContactIds = new Set<Id>();
		Set<Id> honoreeAccountIds = new Set<Id>();
		for (Tribute__c tribute : tributes) {
			if (!TYPE_IN_MEMORY_OF.equals(tribute.Type__c)) {
				continue;
			}
			if (tribute.Honoree_Contact__c != null) {
				honoreeContactIds.add(tribute.Honoree_Contact__c);
			}
			if (tribute.Honoree_Account__c != null) {
				honoreeAccountIds.add(tribute.Honoree_Account__c);
			}
		}
		Set<Id> deceased = TributeSelector.selectDeceasedContactIds(honoreeContactIds);
		// A person stored as an account carries Deceased the same way a contact does (Section 5),
		// so the memorial rule has to ask both. Without this it would either miss the case
		// entirely in a Person Account org, or refuse the legitimate memorial that notifies the
		// foundation it honours.
		deceased.addAll(TributeSelector.selectDeceasedAccountIds(honoreeAccountIds));

		for (Tribute__c tribute : tributes) {
			if (
				String.isBlank(tribute.Honoree_Name__c) &&
				tribute.Honoree_Contact__c == null &&
				tribute.Honoree_Account__c == null
			) {
				tribute.addError(BarnHelp.text('Giving', 'Giving_Tribute_HonoreeRequired'));
				continue;
			}
			if (!TYPE_IN_MEMORY_OF.equals(tribute.Type__c)) {
				continue;
			}
			Boolean notifiesHonoreeContact =
				tribute.Honoree_Contact__c != null &&
				tribute.Honoree_Contact__c == tribute.Notification_Recipient_Contact__c &&
				deceased.contains(tribute.Honoree_Contact__c);
			Boolean notifiesHonoreeAccount =
				tribute.Honoree_Account__c != null &&
				tribute.Honoree_Account__c == tribute.Notification_Recipient_Account__c &&
				deceased.contains(tribute.Honoree_Account__c);
			if (notifiesHonoreeContact || notifiesHonoreeAccount) {
				tribute.addError(BarnHelp.text('Giving', 'Giving_Tribute_DeceasedHonoreeNotified'));
			}
		}
	}

	/**
	 * Refuses a second tribute on a gift that already has one (R-TR1), counting both the tributes
	 * already saved and the ones in this batch.
	 */
	public static void rejectSecondTribute(List<Tribute__c> tributes) {
		if (tributes == null || tributes.isEmpty()) {
			return;
		}
		Set<Id> giftIds = new Set<Id>();
		for (Tribute__c tribute : tributes) {
			if (tribute.Gift__c != null) {
				giftIds.add(tribute.Gift__c);
			}
		}
		Set<Id> takenGiftIds = new Set<Id>();
		for (Tribute__c existing : TributeSelector.selectExistingForGifts(giftIds)) {
			takenGiftIds.add(existing.Gift__c);
		}
		for (Tribute__c tribute : tributes) {
			if (tribute.Gift__c == null) {
				continue;
			}
			if (takenGiftIds.contains(tribute.Gift__c)) {
				tribute.addError(BarnHelp.text('Giving', 'Giving_Tribute_OnePerGift'));
				continue;
			}
			takenGiftIds.add(tribute.Gift__c);
		}
	}

	/**
	 * Keeps the gift's tribute reference in step with the tribute itself. The tribute's own gift
	 * reference is the authoritative link; the one on the gift is the mirror that gift list
	 * views, reports, and the receipt merge read without a subquery (R-G8).
	 */
	public static void mirrorOnGifts(List<Tribute__c> tributes, Boolean linking) {
		if (tributes == null || tributes.isEmpty()) {
			return;
		}
		Map<Id, Gift__c> giftsToUpdate = new Map<Id, Gift__c>();
		for (Tribute__c tribute : tributes) {
			if (tribute.Gift__c == null) {
				continue;
			}
			giftsToUpdate.put(
				tribute.Gift__c,
				new Gift__c(Id = tribute.Gift__c, Tribute__c = linking == true ? tribute.Id : null)
			);
		}
		if (giftsToUpdate.isEmpty()) {
			return;
		}
		// Clearing the mirror is best effort on purpose: the usual reason a tribute is deleted is
		// that its gift is being deleted with it, and there is then no gift left to update.
		Database.update(giftsToUpdate.values(), linking == true, AccessLevel.USER_MODE);
	}
}
