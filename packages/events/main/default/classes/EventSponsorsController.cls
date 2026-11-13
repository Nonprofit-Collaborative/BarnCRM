/**
 * The Sponsors tab of the event page (EV-09, canonical model 29EV22 to 29EV24): the event's
 * sponsorship levels, its sponsors (Core accounts) with status and amount, and each sponsor's
 * deliverables checklist (logo, booth, passes). Thin by design (plan Section 9.9): progress and
 * status words live in `eventSponsorsModel`. Reads in user mode; writes
 * `AccessLevel.USER_MODE`. Levels and sponsor details are edited through the platform's record
 * form. A sponsor's Giving gift or commitment, or Funders award, is held as a record identifier
 * and labelled through Core's `LinkedRecords`, so nothing here names another module.
 */
public with sharing class EventSponsorsController {
	private static final String CONTEXT = 'EventSponsorsController';

	/** Everything the tab draws. */
	public class Sponsors {
		@AuraEnabled
		public List<LevelRow> levels = new List<LevelRow>();
		@AuraEnabled
		public List<SponsorRow> sponsors = new List<SponsorRow>();
		@AuraEnabled
		public List<Option> deliverableStatuses = new List<Option>();
		@AuraEnabled
		public List<Option> deliverableTypes = new List<Option>();
		@AuraEnabled
		public Boolean canAddSponsor = false;
		@AuraEnabled
		public Boolean canAddLevel = false;
		@AuraEnabled
		public Boolean canEdit = false;
		/** Field labels by API name, so the tab needs no labels of its own for columns. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One sponsorship level. */
	public class LevelRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String benefits;
		@AuraEnabled
		public Integer sponsorCount = 0;
	}

	/** One sponsor with its checklist. */
	public class SponsorRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String accountId;
		@AuraEnabled
		public String levelId;
		@AuraEnabled
		public String levelName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public String contactId;
		@AuraEnabled
		public String contactName;
		@AuraEnabled
		public String linkedRecordId;
		/** The linked record's name and kind, when it can be read; otherwise null. */
		@AuraEnabled
		public String linkedLabel;
		@AuraEnabled
		public String linkedKind;
		@AuraEnabled
		public List<DeliverableRow> deliverables = new List<DeliverableRow>();
	}

	/** One checklist item. */
	public class DeliverableRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public Decimal quantity;
	}

	/** A choice in a list. */
	public class Option {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		Option(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	/**
	 * The event's levels and sponsors, with each sponsor's deliverables.
	 *
	 * @param eventId the event
	 * @return the tab's contents and what the person may do
	 */
	@AuraEnabled
	public static Sponsors getSponsors(Id eventId) {
		try {
			Sponsors result = new Sponsors();
			result.canAddSponsor = Schema.SObjectType.Event_Sponsor__c.isCreateable();
			result.canAddLevel = Schema.SObjectType.Sponsorship_Level__c.isCreateable();
			result.canEdit = Schema.SObjectType.Event_Sponsor__c.isUpdateable();
			fillLabels(result);
			Map<Id, LevelRow> levelsById = new Map<Id, LevelRow>();
			for (Sponsorship_Level__c level : [
				SELECT Id, Name, Amount__c, Benefits__c
				FROM Sponsorship_Level__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Sort_Order__c ASC NULLS LAST, Name
				LIMIT 200
			]) {
				LevelRow row = new LevelRow();
				row.id = level.Id;
				row.name = level.Name;
				row.amount = level.Amount__c;
				row.benefits = level.Benefits__c;
				levelsById.put(level.Id, row);
				result.levels.add(row);
			}
			Map<Id, SponsorRow> sponsorsById = new Map<Id, SponsorRow>();
			for (Event_Sponsor__c sponsor : [
				SELECT
					Id,
					Name,
					Account__c,
					Level__c,
					Level__r.Name,
					Status__c,
					Amount__c,
					Contact__c,
					Contact__r.Name,
					Linked_Record_Id__c
				FROM Event_Sponsor__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Level__r.Sort_Order__c ASC NULLS LAST, Name
				LIMIT 500
			]) {
				SponsorRow row = new SponsorRow();
				row.id = sponsor.Id;
				row.name = sponsor.Name;
				row.accountId = sponsor.Account__c;
				row.levelId = sponsor.Level__c;
				row.levelName = sponsor.Level__r?.Name;
				row.status = sponsor.Status__c;
				row.amount = sponsor.Amount__c;
				row.contactId = sponsor.Contact__c;
				row.contactName = sponsor.Contact__r?.Name;
				row.linkedRecordId = sponsor.Linked_Record_Id__c;
				sponsorsById.put(sponsor.Id, row);
				result.sponsors.add(row);
				if (row.levelId != null && levelsById.containsKey(row.levelId)) {
					levelsById.get(row.levelId).sponsorCount++;
				}
			}
			addLinkedLabels(result.sponsors);
			for (Sponsor_Deliverable__c item : [
				SELECT Id, Name, Event_Sponsor__c, Type__c, Status__c, Due_Date__c, Quantity__c
				FROM Sponsor_Deliverable__c
				WHERE Event_Sponsor__c IN :sponsorsById.keySet()
				WITH USER_MODE
				ORDER BY CreatedDate, Name
				LIMIT 5000
			]) {
				DeliverableRow row = new DeliverableRow();
				row.id = item.Id;
				row.name = item.Name;
				row.type = item.Type__c;
				row.status = item.Status__c;
				row.dueDate = item.Due_Date__c;
				row.quantity = item.Quantity__c;
				sponsorsById.get(item.Event_Sponsor__c).deliverables.add(row);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getSponsors', eventId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Sponsors_LoadFailed')
			);
		}
	}

	/**
	 * Adds an organization as a sponsor of the event at a level, named after the organization,
	 * with the level's amount and a checklist from the level's deliverables (R-SP2, R-SP3).
	 *
	 * @param eventId the event
	 * @param accountId the sponsoring organization, a Core account
	 * @param levelId the level, or null for none
	 * @return the new sponsor's identifier
	 */
	@AuraEnabled
	public static Id addSponsor(Id eventId, Id accountId, Id levelId) {
		Savepoint savepoint = Database.setSavepoint();
		try {
			List<Account> accounts = [
				SELECT Id, Name
				FROM Account
				WHERE Id = :accountId
				WITH USER_MODE
				LIMIT 1
			];
			if (accounts.isEmpty()) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Shared_NotSaved'));
			}
			if (
				![
						SELECT Id
						FROM Event_Sponsor__c
						WHERE Event__c = :eventId AND Account__c = :accountId
						WITH USER_MODE
						LIMIT 1
					]
					.isEmpty()
			) {
				throw UserErrors.message(
					BarnHelp.text(
						'Events',
						'Events_Sponsor_Duplicate',
						new List<Object>{ accounts[0].Name }
					)
				);
			}
			Event_Sponsor__c sponsor = new Event_Sponsor__c(
				Event__c = eventId,
				Account__c = accountId,
				Name = accounts[0].Name.left(80),
				Level__c = levelId
			);
			List<Sponsorship_Level__c> levels = levelId == null
				? new List<Sponsorship_Level__c>()
				: [
						SELECT Id, Amount__c, Deliverables__c
						FROM Sponsorship_Level__c
						WHERE Id = :levelId AND Event__c = :eventId
						WITH USER_MODE
						LIMIT 1
				  ];
			if (levelId != null && levels.isEmpty()) {
				throw UserErrors.message(BarnHelp.text('Events', 'Events_Sponsor_LevelOtherEvent'));
			}
			if (!levels.isEmpty()) {
				sponsor.Amount__c = levels[0].Amount__c;
			}
			Database.insert(sponsor, true, AccessLevel.USER_MODE);
			if (!levels.isEmpty()) {
				List<Sponsor_Deliverable__c> checklist = new List<Sponsor_Deliverable__c>();
				for (
					SponsorDeliverableTemplate.Item item : SponsorDeliverableTemplate.parse(
						levels[0].Deliverables__c
					)
				) {
					checklist.add(
						new Sponsor_Deliverable__c(
							Event_Sponsor__c = sponsor.Id,
							Name = item.name,
							Type__c = item.type
						)
					);
				}
				if (!checklist.isEmpty()) {
					Database.insert(checklist, true, AccessLevel.USER_MODE);
				}
			}
			return sponsor.Id;
		} catch (AuraHandledException refused) {
			Database.rollback(savepoint);
			throw refused;
		} catch (DmlException e) {
			Database.rollback(savepoint);
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			Database.rollback(savepoint);
			ErrorLogger.log(e, CONTEXT + '.addSponsor', eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Adds one item to a sponsor's checklist.
	 *
	 * @param sponsorId the sponsor
	 * @param name what is owed, for example "Logo for the program"
	 * @param type Logo, Booth, Passes or Other
	 */
	@AuraEnabled
	public static void addDeliverable(Id sponsorId, String name, String type) {
		if (String.isBlank(name)) {
			throw UserErrors.message(
				BarnHelp.text('Events', 'Events_Sponsor_DeliverableNeedsName')
			);
		}
		save(
			new Sponsor_Deliverable__c(
				Event_Sponsor__c = sponsorId,
				Name = name.trim().left(80),
				Type__c = String.isBlank(type) ? 'Other' : type
			),
			'addDeliverable'
		);
	}

	/**
	 * Sets a checklist item's status (Pending, Requested, Received or Done).
	 *
	 * @param deliverableId the item
	 * @param status the new status
	 */
	@AuraEnabled
	public static void setDeliverableStatus(Id deliverableId, String status) {
		try {
			Database.update(
				new Sponsor_Deliverable__c(Id = deliverableId, Status__c = status),
				true,
				AccessLevel.USER_MODE
			);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.setDeliverableStatus', deliverableId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * Removes a sponsor and, with it, its checklist.
	 *
	 * @param sponsorId the sponsor
	 */
	@AuraEnabled
	public static void removeSponsor(Id sponsorId) {
		try {
			Database.delete(new Event_Sponsor__c(Id = sponsorId), true, AccessLevel.USER_MODE);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.removeSponsor', sponsorId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** One column of the leads download: its label and the row key it reads. */
	public class LeadColumn {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String path;

		LeadColumn(String label, String path) {
			this.label = label;
			this.path = path;
		}
	}

	/** A sponsor's leads for Download Leads (EV-28): Shared status only (R-SLD2). */
	public class Leads {
		@AuraEnabled
		public List<LeadColumn> columns = new List<LeadColumn>();
		@AuraEnabled
		public List<Map<String, Object>> rows = new List<Map<String, Object>>();
	}

	/** The fields a leads download holds, in order. */
	private static final List<Schema.SObjectField> LEAD_FIELDS = new List<Schema.SObjectField>{
		Sponsor_Lead__c.Lead_Name__c,
		Sponsor_Lead__c.Lead_Email__c,
		Sponsor_Lead__c.Lead_Title__c,
		Sponsor_Lead__c.Lead_Company__c,
		Sponsor_Lead__c.Interest__c,
		Sponsor_Lead__c.Notes__c,
		Sponsor_Lead__c.CreatedDate
	};

	/**
	 * A sponsor's leads, for the Sponsors tab's Download Leads: only attendees who shared their
	 * details (status Shared), read in user mode.
	 *
	 * @param sponsorId the sponsor
	 * @return the columns and rows; no rows when the sponsor has no leads
	 */
	@AuraEnabled
	public static Leads getLeads(Id sponsorId) {
		try {
			Leads result = new Leads();
			for (Schema.SObjectField field : LEAD_FIELDS) {
				Schema.DescribeFieldResult describe = field.getDescribe();
				result.columns.add(new LeadColumn(describe.getLabel(), describe.getName()));
			}
			for (Sponsor_Lead__c lead : [
				SELECT
					Lead_Name__c,
					Lead_Email__c,
					Lead_Title__c,
					Lead_Company__c,
					toLabel(Interest__c),
					Notes__c,
					CreatedDate
				FROM Sponsor_Lead__c
				WHERE Event_Sponsor__c = :sponsorId AND Status__c = 'Shared'
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 10000
			]) {
				Map<String, Object> row = new Map<String, Object>();
				for (Schema.SObjectField field : LEAD_FIELDS) {
					row.put(field.getDescribe().getName(), lead.get(field));
				}
				result.rows.add(row);
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getLeads', sponsorId);
			throw UserErrors.wrapShowingDml(
				e,
				BarnHelp.text('Events', 'Events_Sponsors_LoadFailed')
			);
		}
	}

	/** Names the linked Giving or Funders record, where it exists and can be read. */
	private static void addLinkedLabels(List<SponsorRow> rows) {
		List<String> ids = new List<String>();
		for (SponsorRow row : rows) {
			if (String.isNotBlank(row.linkedRecordId)) {
				ids.add(row.linkedRecordId);
			}
		}
		if (ids.isEmpty()) {
			return;
		}
		Map<String, LinkedRecords.Link> links = LinkedRecords.resolve(ids);
		for (SponsorRow row : rows) {
			LinkedRecords.Link link = links.get(row.linkedRecordId);
			if (link != null) {
				row.linkedLabel = link.label;
				row.linkedKind = link.objectLabel;
			}
		}
	}

	private static void fillLabels(Sponsors result) {
		Map<String, Schema.SObjectField> sponsorFields = Schema.SObjectType.Event_Sponsor__c.fields.getMap();
		for (
			String name : new List<String>{
				'Name',
				'Level__c',
				'Status__c',
				'Amount__c',
				'Contact__c',
				'Linked_Record_Id__c',
				'Deliverables_Total__c'
			}
		) {
			result.fieldLabels.put(
				name,
				NamespaceUtil.field(sponsorFields, name).getDescribe().getLabel()
			);
		}
		Map<String, Schema.SObjectField> itemFields = Schema.SObjectType.Sponsor_Deliverable__c.fields.getMap();
		for (String name : new List<String>{ 'Name', 'Type__c', 'Status__c', 'Due_Date__c' }) {
			result.fieldLabels.put(
				'Deliverable_' + name,
				NamespaceUtil.field(itemFields, name).getDescribe().getLabel()
			);
		}
		result.fieldLabels.put('Levels', Schema.SObjectType.Sponsorship_Level__c.getLabelPlural());
		Map<String, Schema.SObjectField> levelFields = Schema.SObjectType.Sponsorship_Level__c.fields.getMap();
		result.fieldLabels.put(
			'LevelName',
			NamespaceUtil.field(levelFields, 'Name').getDescribe().getLabel()
		);
		result.fieldLabels.put(
			'LevelAmount',
			NamespaceUtil.field(levelFields, 'Amount__c').getDescribe().getLabel()
		);
		result.fieldLabels.put(
			'LevelBenefits',
			NamespaceUtil.field(levelFields, 'Benefits__c').getDescribe().getLabel()
		);
		for (
			Schema.PicklistEntry entry : Schema.SObjectType.Sponsor_Deliverable__c.fields.Status__c.getPicklistValues()
		) {
			if (entry.isActive()) {
				result.deliverableStatuses.add(new Option(entry.getLabel(), entry.getValue()));
			}
		}
		for (
			Schema.PicklistEntry entry : Schema.SObjectType.Sponsor_Deliverable__c.fields.Type__c.getPicklistValues()
		) {
			if (entry.isActive()) {
				result.deliverableTypes.add(new Option(entry.getLabel(), entry.getValue()));
			}
		}
	}

	private static void save(SObject record, String method) {
		try {
			Database.insert(record, true, AccessLevel.USER_MODE);
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.' + method);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}
}
