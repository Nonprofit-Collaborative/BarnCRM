/**
 * The Tickets tab of the event page (EV-03, canonical model 29EV2 and 29EV3): the event's ticket
 * types and promo codes. Thin by design (plan Section 9.9): it returns plain shapes; code states,
 * prices with a code and the quantity total are worked out in the browser module
 * `eventTicketsModel`. Records are added, edited and deleted through the platform's record forms,
 * so this class only reads, in user mode.
 */
public with sharing class EventTicketsController {
	private static final String CONTEXT = 'EventTicketsController';

	/** Everything the tab draws. */
	public class Tickets {
		@AuraEnabled
		public Decimal capacity;
		@AuraEnabled
		public String currencyCode;
		/** The promo code object's plural label, the codes section's heading. */
		@AuraEnabled
		public String codesTitle;
		@AuraEnabled
		public Boolean canAddTicket = false;
		@AuraEnabled
		public Boolean canAddCode = false;
		@AuraEnabled
		public List<TicketRow> tickets = new List<TicketRow>();
		@AuraEnabled
		public List<CodeRow> codes = new List<CodeRow>();
		/** Field labels by `Object.Field`, so the tab needs no labels of its own for columns. */
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One ticket type. */
	public class TicketRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public Decimal price;
		@AuraEnabled
		public Decimal quantity;
		@AuraEnabled
		public Datetime salesStart;
		@AuraEnabled
		public Datetime salesEnd;
		@AuraEnabled
		public Boolean active;
	}

	/** One promo code. */
	public class CodeRow {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String code;
		@AuraEnabled
		public String discountType;
		@AuraEnabled
		public Decimal discountValue;
		@AuraEnabled
		public String ticketTypeId;
		@AuraEnabled
		public Decimal maxUses;
		@AuraEnabled
		public Datetime validFrom;
		@AuraEnabled
		public Datetime validUntil;
		@AuraEnabled
		public Boolean active;
	}

	/**
	 * The event's ticket types (by sort order, then name) and promo codes (by code).
	 *
	 * @param eventId the event
	 * @return the tab's tickets, codes and what the person may add
	 */
	@AuraEnabled
	public static Tickets getTickets(Id eventId) {
		try {
			Tickets result = new Tickets();
			result.canAddTicket = Schema.SObjectType.Ticket_Type__c.isCreateable();
			result.canAddCode = Schema.SObjectType.Promo_Code__c.isCreateable();
			result.currencyCode = UserInfo.getDefaultCurrency();
			result.codesTitle = Schema.SObjectType.Promo_Code__c.getLabelPlural();
			labels(result, Schema.SObjectType.Ticket_Type__c.fields.getMap(), 'Ticket_Type__c');
			labels(result, Schema.SObjectType.Promo_Code__c.fields.getMap(), 'Promo_Code__c');
			for (Event__c record : [
				SELECT Capacity__c
				FROM Event__c
				WHERE Id = :eventId
				WITH USER_MODE
			]) {
				result.capacity = record.Capacity__c;
			}
			for (Ticket_Type__c ticket : [
				SELECT Id, Name, Price__c, Quantity__c, Sales_Start__c, Sales_End__c, Active__c
				FROM Ticket_Type__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Sort_Order__c ASC NULLS LAST, Name
				LIMIT 200
			]) {
				result.tickets.add(toRow(ticket));
			}
			for (Promo_Code__c code : [
				SELECT
					Id,
					Name,
					Discount_Type__c,
					Discount_Value__c,
					Ticket_Type__c,
					Max_Uses__c,
					Valid_From__c,
					Valid_Until__c,
					Active__c
				FROM Promo_Code__c
				WHERE Event__c = :eventId
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				result.codes.add(toRow(code));
			}
			return result;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getTickets', eventId);
			throw UserErrors.message(BarnHelp.text('Events', 'Events_Tickets_LoadFailed'));
		}
	}

	private static void labels(
		Tickets result,
		Map<String, Schema.SObjectField> fields,
		String objectName
	) {
		for (String name : fields.keySet()) {
			Schema.DescribeFieldResult field = fields.get(name).getDescribe();
			if (field.isCustom() || field.getName() == 'Name') {
				result.fieldLabels.put(objectName + '.' + field.getName(), field.getLabel());
			}
		}
	}

	private static TicketRow toRow(Ticket_Type__c record) {
		TicketRow row = new TicketRow();
		row.id = record.Id;
		row.name = record.Name;
		row.price = record.Price__c;
		row.quantity = record.Quantity__c;
		row.salesStart = record.Sales_Start__c;
		row.salesEnd = record.Sales_End__c;
		row.active = record.Active__c;
		return row;
	}

	private static CodeRow toRow(Promo_Code__c record) {
		CodeRow row = new CodeRow();
		row.id = record.Id;
		row.code = record.Name;
		row.discountType = record.Discount_Type__c;
		row.discountValue = record.Discount_Value__c;
		row.ticketTypeId = record.Ticket_Type__c;
		row.maxUses = record.Max_Uses__c;
		row.validFrom = record.Valid_From__c;
		row.validUntil = record.Valid_Until__c;
		row.active = record.Active__c;
		return row;
	}
}
