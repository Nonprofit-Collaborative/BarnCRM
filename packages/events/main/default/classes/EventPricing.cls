/**
 * The promo code rule (canonical model R-PC5, R-ERG2) on the server, where a Forms submission is
 * processed. It repeats `eventTicketsModel.js` exactly, and both are tested against the same
 * cases (ADR-0182 `0182-event-registrations.md`, decision 3).
 */
public with sharing class EventPricing {
	public static final String ACTIVE = 'active';
	public static final String INACTIVE = 'inactive';
	public static final String SCHEDULED = 'scheduled';
	public static final String EXPIRED = 'expired';
	private static final String DISCOUNT_AMOUNT = 'Amount';
	private static final Decimal ZERO = 0;
	private static final Decimal HUNDRED = 100;

	/** A code's state at a moment: active, inactive, scheduled (not yet valid) or expired. */
	public static String codeState(Promo_Code__c code, Datetime now) {
		if (code == null || code.Active__c != true) {
			return INACTIVE;
		}
		if (code.Valid_From__c != null && code.Valid_From__c > now) {
			return SCHEDULED;
		}
		if (code.Valid_Until__c != null && code.Valid_Until__c <= now) {
			return EXPIRED;
		}
		return ACTIVE;
	}

	/** Whether the code takes money off this ticket type at this moment. */
	public static Boolean codeApplies(Promo_Code__c code, Id ticketTypeId, Datetime now) {
		if (codeState(code, now) != ACTIVE) {
			return false;
		}
		return code.Ticket_Type__c == null || code.Ticket_Type__c == ticketTypeId;
	}

	/**
	 * The price with the code applied: a percent off rounded to the cent, an amount off capped
	 * at the price, never below zero. A code that does not apply leaves the price as it is.
	 */
	public static Decimal priceWithCode(
		Decimal price,
		Promo_Code__c code,
		Id ticketTypeId,
		Datetime now
	) {
		Decimal base = toCents(price);
		if (!codeApplies(code, ticketTypeId, now)) {
			return base / HUNDRED;
		}
		Decimal value = code.Discount_Value__c == null ? ZERO : code.Discount_Value__c;
		Decimal off = code.Discount_Type__c == DISCOUNT_AMOUNT
			? toCents(value)
			: (base *
					Math.min(Math.max(value, ZERO), HUNDRED) /
					HUNDRED)
					.round(System.RoundingMode.HALF_UP);
		return Math.max(base - Math.max(off, ZERO), ZERO) / HUNDRED;
	}

	private static Decimal toCents(Decimal value) {
		return value == null ? ZERO : (value * HUNDRED).round(System.RoundingMode.HALF_UP);
	}
}
