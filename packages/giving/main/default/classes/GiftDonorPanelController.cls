/**
 * The donor panel in Quick Gift Entry (G-33): who the chosen donor is to the organization, read
 * while the gift is typed, so nobody leaves the form to look. The household, the giving totals
 * the rollups keep, the last few gifts and the open pledges and recurring gifts.
 *
 * Read only, in user mode: a person sees only the gifts and commitments their sharing lets them
 * see, and someone without the Giving field access gets the panel's plain error instead of the
 * figures. Plain JSON out, so the panel ports with the rest of gift entry (plan 9.9).
 */
public with sharing class GiftDonorPanelController {
	/** How many recent gifts and open commitments the panel lists. */
	@TestVisible
	private static final Integer ROWS = 3;

	private static final Set<String> OPEN_COMMITMENT = new Set<String>{ 'Active', 'Paused' };
	private static final Set<String> OWED = new Set<String>{
		'Scheduled',
		'Overdue',
		'Partially paid'
	};

	/** What the panel shows about one donor. */
	public class Panel {
		@AuraEnabled
		public Id householdId;
		@AuraEnabled
		public String householdName;
		@AuraEnabled
		public Decimal totalGiving;
		@AuraEnabled
		public Date lastGiftDate;
		@AuraEnabled
		public List<GiftRow> gifts = new List<GiftRow>();
		@AuraEnabled
		public List<CommitmentRow> commitments = new List<CommitmentRow>();
	}

	/** One recent gift. */
	public class GiftRow {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Date giftDate;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String paymentMethod;
		@AuraEnabled
		public String status;
	}

	/** One open pledge or recurring gift, with the next payment it is owed. */
	public class CommitmentRow {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String frequency;
		@AuraEnabled
		public Decimal balance;
		@AuraEnabled
		public Date nextDueDate;
		@AuraEnabled
		public Decimal nextDueAmount;
	}

	/**
	 * The panel for a person (a contact, or a person held as an account) or an organization.
	 * Null for an id that names neither, so the form simply shows no panel.
	 */
	@AuraEnabled
	public static Panel getPanel(String donorId) {
		Id donor = asDonorId(donorId);
		if (donor == null) {
			return null;
		}
		try {
			Panel panel = new Panel();
			Boolean isContact = donor.getSObjectType() == Contact.SObjectType;
			readTotals(panel, donor, isContact);
			readHousehold(panel, donor);
			readGifts(panel, donor, isContact);
			readCommitments(panel, donor, isContact);
			return panel;
		} catch (Exception e) {
			ErrorLogger.log(e, 'GiftDonorPanelController.getPanel');
			throw UserErrors.message(BarnHelp.text('Giving', 'Giving_DonorPanel_LoadError'));
		}
	}

	private static Id asDonorId(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			Id candidate = Id.valueOf(value.trim());
			Schema.SObjectType type = candidate.getSobjectType();
			return type == Contact.SObjectType || type == Account.SObjectType ? candidate : null;
		} catch (System.StringException e) {
			return null;
		}
	}

	private static void readTotals(Panel panel, Id donor, Boolean isContact) {
		if (isContact) {
			for (Contact person : [
				SELECT Total_Giving__c, Last_Gift_Date__c
				FROM Contact
				WHERE Id = :donor
				WITH USER_MODE
				LIMIT 1
			]) {
				panel.totalGiving = person.Total_Giving__c;
				panel.lastGiftDate = person.Last_Gift_Date__c;
			}
			return;
		}
		for (Account organization : [
			SELECT Total_Giving__c, Last_Gift_Date__c
			FROM Account
			WHERE Id = :donor
			WITH USER_MODE
			LIMIT 1
		]) {
			panel.totalGiving = organization.Total_Giving__c;
			panel.lastGiftDate = organization.Last_Gift_Date__c;
		}
	}

	/** The household the gift would be credited to (R-G2); none for an organization. */
	private static void readHousehold(Panel panel, Id donor) {
		Id householdId = HouseholdService.getHouseholdIdsFor(new Set<Id>{ donor }).get(donor);
		if (householdId == null || householdId == donor) {
			return;
		}
		for (Account household : [
			SELECT Id, Name
			FROM Account
			WHERE Id = :householdId
			WITH USER_MODE
			LIMIT 1
		]) {
			panel.householdId = household.Id;
			panel.householdName = household.Name;
		}
	}

	private static void readGifts(Panel panel, Id donor, Boolean isContact) {
		Id contactId = isContact ? donor : null;
		Id accountId = isContact ? null : donor;
		for (Gift__c gift : [
			SELECT Id, Name, Gift_Date__c, Amount__c, Type__c, Status__c
			FROM Gift__c
			WHERE
				(Donor_Contact__c = :contactId
				AND Donor_Contact__c != NULL)
				OR (Donor_Account__c = :accountId
				AND Donor_Account__c != NULL)
			WITH USER_MODE
			ORDER BY Gift_Date__c DESC, Name DESC
			LIMIT :ROWS
		]) {
			GiftRow row = new GiftRow();
			row.id = gift.Id;
			row.name = gift.Name;
			row.giftDate = gift.Gift_Date__c;
			row.amount = gift.Amount__c;
			row.paymentMethod = gift.Type__c;
			row.status = gift.Status__c;
			panel.gifts.add(row);
		}
	}

	private static void readCommitments(Panel panel, Id donor, Boolean isContact) {
		Id contactId = isContact ? donor : null;
		Id accountId = isContact ? null : donor;
		for (Commitment__c commitment : [
			SELECT
				Id,
				Name,
				Type__c,
				Status__c,
				Amount__c,
				Frequency__c,
				Balance__c,
				(
					SELECT Due_Date__c, Expected_Amount__c, Paid_Amount__c
					FROM Installments__r
					WHERE Status__c IN :OWED
					ORDER BY Due_Date__c ASC
					LIMIT 1
				)
			FROM Commitment__c
			WHERE
				Status__c IN :OPEN_COMMITMENT
				AND ((Donor_Contact__c = :contactId
				AND Donor_Contact__c != NULL)
				OR (Donor_Account__c = :accountId
				AND Donor_Account__c != NULL))
			WITH USER_MODE
			ORDER BY Start_Date__c DESC, Name DESC
			LIMIT :ROWS
		]) {
			CommitmentRow row = new CommitmentRow();
			row.id = commitment.Id;
			row.name = commitment.Name;
			row.type = commitment.Type__c;
			row.status = commitment.Status__c;
			row.amount = commitment.Amount__c;
			row.frequency = commitment.Frequency__c;
			row.balance = commitment.Balance__c;
			for (Installment__c next : commitment.Installments__r) {
				row.nextDueDate = next.Due_Date__c;
				row.nextDueAmount =
					(next.Expected_Amount__c == null ? 0 : next.Expected_Amount__c) -
					(next.Paid_Amount__c == null ? 0 : next.Paid_Amount__c);
			}
			panel.commitments.add(row);
		}
	}
}
