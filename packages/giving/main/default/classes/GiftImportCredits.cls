/**
 * The soft credit and the tribute an imported row can carry with its gift (canonical model
 * R-GI5, R-GI6): read and checked for the dry run, and saved after the gift in a commit.
 * A credit or tribute the platform refuses fails the row, and the processor then deletes the
 * gift, so a row is saved whole or not at all (R-GI7).
 */
public with sharing class GiftImportCredits {
	public static final String PARTY_CONTACT_2 = 'Contact2';
	private static final String ROLE_OTHER = 'Other';

	/** Reads each row's soft credit and tribute, refusing a value that cannot be one. */
	public static void read(List<GiftImportRow> gifts) {
		for (GiftImportRow item : gifts) {
			if (item.error != null) {
				continue;
			}
			try {
				readCredit(item);
				readTribute(item);
			} catch (GiftImportRow.GiftImportException refused) {
				item.error = refused.getMessage();
			}
		}
	}

	private static void readCredit(GiftImportRow item) {
		String entity = GiftImportRow.ENTITY_SOFT_CREDIT;
		if (!item.names(entity)) {
			return;
		}
		String role = picklistValue(
			Soft_Credit__c.Role__c.getDescribe(),
			item.value(entity, 'Role__c'),
			BarnHelp.text('Giving', 'Giving_Import_ErrorSoftCreditRoleUnknown')
		);
		String customRole = item.value(entity, 'Custom_Role__c');
		if (role == ROLE_OTHER && customRole == null) {
			throw new GiftImportRow.GiftImportException(
				BarnHelp.text('Giving', 'Giving_Import_ErrorCustomRoleMissing')
			);
		}
		String amountText = item.value(entity, 'Amount__c');
		Decimal amount = amountText == null ? item.amount : GiftImportRow.parseAmount(amountText);
		if (amount == null) {
			throw new GiftImportRow.GiftImportException(
				String.format(
					BarnHelp.text('Giving', 'Giving_Import_ErrorValueUnreadable'),
					new List<String>{ amountText, Label.Giving_Import_TargetSoftCreditAmount }
				)
			);
		}
		item.creditParty = partyChoice(item.value(entity, 'Party'));
		item.credit = new Soft_Credit__c(
			Role__c = role,
			Custom_Role__c = customRole,
			Amount__c = amount
		);
	}

	private static void readTribute(GiftImportRow item) {
		String entity = GiftImportRow.ENTITY_TRIBUTE;
		if (!item.names(entity)) {
			return;
		}
		String type = picklistValue(
			Tribute__c.Type__c.getDescribe(),
			item.value(entity, 'Type__c'),
			BarnHelp.text('Giving', 'Giving_Import_ErrorTributeTypeUnknown')
		);
		String honoree = item.value(entity, 'Honoree_Name__c');
		if (honoree == null) {
			throw new GiftImportRow.GiftImportException(
				BarnHelp.text('Giving', 'Giving_Import_ErrorTributeHonoreeMissing')
			);
		}
		item.tribute = new Tribute__c(
			Type__c = type,
			Honoree_Name__c = honoree,
			Notification_Recipient_Name__c = item.value(entity, 'Notification_Recipient_Name__c'),
			Message__c = item.value(entity, 'Message__c')
		);
	}

	/** A picklist value matched ignoring case; a missing or unknown one names the choices. */
	private static String picklistValue(
		Schema.DescribeFieldResult field,
		String text,
		String refusal
	) {
		List<String> accepted = new List<String>();
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (!entry.isActive()) {
				continue;
			}
			accepted.add(entry.getValue());
			if (
				text != null &&
				(entry.getValue().equalsIgnoreCase(text) || entry.getLabel().equalsIgnoreCase(text))
			) {
				return entry.getValue();
			}
		}
		throw new GiftImportRow.GiftImportException(
			String.format(
				refusal,
				new List<String>{ text == null ? '' : text, String.join(accepted, ', ') }
			)
		);
	}

	private static String partyChoice(String text) {
		if (text == null) {
			return PARTY_CONTACT_2;
		}
		for (
			String choice : new List<String>{
				GiftImportRow.DONOR_CONTACT_1,
				PARTY_CONTACT_2,
				GiftImportRow.DONOR_ORGANIZATION,
				GiftImportRow.DONOR_HOUSEHOLD
			}
		) {
			if (choice.equalsIgnoreCase(text.deleteWhitespace())) {
				return choice;
			}
		}
		throw new GiftImportRow.GiftImportException(
			String.format(
				BarnHelp.text('Giving', 'Giving_Import_ErrorSoftCreditPartyChoice'),
				new List<String>{ text }
			)
		);
	}

	/**
	 * Finds whom each soft credit credits. In a dry run a person Core would create has no
	 * identifier yet, and the credit still counts as one that would be made.
	 */
	public static void resolveParties(List<GiftImportRow> gifts, Boolean dryRun) {
		for (GiftImportRow item : gifts) {
			if (item.error != null || item.credit == null) {
				continue;
			}
			Import_Row__c row = item.row;
			Id party;
			String comingFrom;
			if (item.creditParty == PARTY_CONTACT_2) {
				party = row.Contact_2__c != null ? row.Contact_2__c : row.Person_2_Account__c;
				comingFrom = ImportMapping.ENTITY_CONTACT_2;
			} else if (item.creditParty == GiftImportRow.DONOR_CONTACT_1) {
				party = row.Contact_1__c != null ? row.Contact_1__c : row.Person_1_Account__c;
				comingFrom = ImportMapping.ENTITY_CONTACT_1;
			} else if (item.creditParty == GiftImportRow.DONOR_ORGANIZATION) {
				party = row.Organization__c;
				comingFrom = ImportMapping.ENTITY_ORGANIZATION;
			} else {
				party = row.Household__c;
				comingFrom = ImportMapping.ENTITY_CONTACT_1;
			}
			if (party == null) {
				if (!(dryRun && item.names(comingFrom))) {
					item.error = BarnHelp.text(
						'Giving',
						'Giving_Import_ErrorSoftCreditPartyMissing'
					);
				}
			} else if (party.getSObjectType() == Contact.SObjectType) {
				item.credit.Contact__c = party;
			} else {
				item.credit.Account__c = party;
			}
		}
	}

	/**
	 * Saves the tributes and the soft credits of the rows whose gifts were saved. A credit the
	 * package already made for the same party and role, such as the automatic household
	 * member credit, is not made twice: the row records that one (R-GI5).
	 */
	public static void save(List<GiftImportRow> gifts) {
		List<GiftImportRow> withTribute = new List<GiftImportRow>();
		List<Tribute__c> tributes = new List<Tribute__c>();
		Set<Id> creditedGiftIds = new Set<Id>();
		for (GiftImportRow item : gifts) {
			if (item.error != null || item.giftId == null) {
				continue;
			}
			if (item.tribute != null) {
				item.tribute.Gift__c = item.giftId;
				tributes.add(item.tribute);
				withTribute.add(item);
			}
			if (item.credit != null) {
				creditedGiftIds.add(item.giftId);
			}
		}
		insertAll(tributes, withTribute);

		Map<String, Id> existing = new Map<String, Id>();
		for (Soft_Credit__c credit : GiftImportSelector.selectCreditsOnGifts(creditedGiftIds)) {
			existing.put(
				creditKey(credit.Gift__c, credit.Contact__c, credit.Account__c, credit.Role__c),
				credit.Id
			);
		}
		List<GiftImportRow> withCredit = new List<GiftImportRow>();
		List<Soft_Credit__c> credits = new List<Soft_Credit__c>();
		for (GiftImportRow item : gifts) {
			if (item.error != null || item.giftId == null || item.credit == null) {
				continue;
			}
			Soft_Credit__c credit = item.credit;
			Id already = existing.get(
				creditKey(item.giftId, credit.Contact__c, credit.Account__c, credit.Role__c)
			);
			if (already != null) {
				item.row.Soft_Credit_Id__c = already;
				continue;
			}
			credit.Gift__c = item.giftId;
			credits.add(credit);
			withCredit.add(item);
		}
		insertAll(credits, withCredit);
		for (Integer index = 0; index < credits.size(); index++) {
			if (credits[index].Id != null) {
				withCredit[index].row.Soft_Credit_Id__c = credits[index].Id;
			}
		}
	}

	private static String creditKey(Id giftId, Id contactId, Id accountId, String role) {
		return giftId + ':' + (contactId != null ? contactId : accountId) + ':' + role;
	}

	/** Inserts in the user's own mode; a refused record fails its row with the reason. */
	private static void insertAll(List<SObject> records, List<GiftImportRow> owners) {
		if (records.isEmpty()) {
			return;
		}
		List<Database.SaveResult> results = Database.insert(records, false, AccessLevel.USER_MODE);
		for (Integer index = 0; index < results.size(); index++) {
			if (!results[index].isSuccess()) {
				List<String> messages = new List<String>();
				for (Database.Error error : results[index].getErrors()) {
					messages.add(error.getMessage());
				}
				owners[index].error = String.format(
					BarnHelp.text('Giving', 'Giving_Import_ErrorFailed'),
					new List<String>{ String.join(messages, ' ') }
				);
			}
		}
	}
}
