/**
 * How a new commitment is put together from what a person enters, shared by every screen that
 * creates one: the Ask Pipeline's Record a Pledge and the New Commitment screen. Both therefore
 * check the same things and save the same record (people-giving-11).
 *
 * A pledge is entered as a total and a number of payments; the amount each time is the total
 * divided evenly, rounded down, and the last payment takes up the rounding (R-CM5). A
 * recurring gift is entered as the amount each time and has no total.
 *
 * Nothing here saves; the caller inserts in user mode.
 */
public with sharing class CommitmentEntry {
	public static final String TYPE_PLEDGE = 'Pledge';
	public static final String TYPE_RECURRING = 'Recurring';
	private static final String STATUS_ACTIVE = 'Active';
	/** The same ceiling the schedule builder keeps. */
	private static final Integer MAX_PAYMENTS = 520;

	/**
	 * The sentence to show when a pledge cannot be built from these entries, or null when it
	 * can.
	 */
	public static String pledgeProblem(
		Decimal total,
		Integer payments,
		String frequency,
		Date firstPaymentDate
	) {
		if (total == null || total <= 0) {
			return Label.Giving_Ask_ErrorAmount;
		}
		if (
			payments == null ||
			payments < 1 ||
			String.isBlank(frequency) ||
			firstPaymentDate == null
		) {
			return Label.Giving_Ask_ErrorPledgeSchedule;
		}
		return null;
	}

	/** A pledge for the total in equal payments, ready to insert. */
	public static Commitment__c pledge(
		Id donorContactId,
		Id donorAccountId,
		Decimal total,
		Integer payments,
		String frequency,
		Date firstPaymentDate,
		Id appealId,
		Id fundId
	) {
		return new Commitment__c(
			Type__c = TYPE_PLEDGE,
			Status__c = STATUS_ACTIVE,
			Donor_Contact__c = donorContactId,
			Donor_Account__c = donorAccountId,
			Expected_Total__c = total.setScale(2),
			Installments_Planned__c = payments,
			Amount__c = (total / payments).setScale(2, System.RoundingMode.DOWN),
			Frequency__c = frequency,
			Start_Date__c = firstPaymentDate,
			Appeal__c = appealId,
			Fund__c = fundId
		);
	}

	/**
	 * The sentence to show when a recurring gift cannot be built from these entries, or null
	 * when it can.
	 */
	public static String recurringProblem(
		Decimal amountEachTime,
		String frequency,
		Date startDate
	) {
		if (amountEachTime == null || amountEachTime <= 0) {
			return BarnHelp.text('Giving', 'Giving_CommitmentNew_ErrorAmountEachTime');
		}
		if (String.isBlank(frequency) || startDate == null) {
			return BarnHelp.text('Giving', 'Giving_CommitmentNew_ErrorRecurringSchedule');
		}
		return null;
	}

	/** An open-ended recurring gift, ready to insert. */
	public static Commitment__c recurring(
		Id donorContactId,
		Id donorAccountId,
		Decimal amountEachTime,
		String frequency,
		Date startDate,
		Id appealId,
		Id fundId
	) {
		return new Commitment__c(
			Type__c = TYPE_RECURRING,
			Status__c = STATUS_ACTIVE,
			Donor_Contact__c = donorContactId,
			Donor_Account__c = donorAccountId,
			Amount__c = amountEachTime.setScale(2),
			Frequency__c = frequency,
			Start_Date__c = startDate,
			Appeal__c = appealId,
			Fund__c = fundId
		);
	}

	/**
	 * How many payments fall from the first payment date up to and including the last one,
	 * on the dates the schedule itself uses. Null when either date is missing or the last is
	 * before the first.
	 */
	public static Integer paymentsThrough(
		String frequency,
		Date firstPaymentDate,
		Date lastPaymentDate
	) {
		if (
			String.isBlank(frequency) ||
			firstPaymentDate == null ||
			lastPaymentDate == null ||
			lastPaymentDate < firstPaymentDate
		) {
			return null;
		}
		Commitment__c draft = new Commitment__c(
			Frequency__c = frequency,
			Start_Date__c = firstPaymentDate
		);
		Integer count = 0;
		while (
			count < MAX_PAYMENTS &&
			CommitmentService.dueDateFor(draft, count) <= lastPaymentDate
		) {
			count++;
		}
		return count;
	}
}
