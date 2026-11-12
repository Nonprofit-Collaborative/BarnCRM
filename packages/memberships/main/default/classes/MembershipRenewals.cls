/**
 * The Memberships step of the nightly run (ADR-0166; ADR-NEXT `NEXT-memberships-module.md`,
 * decision 5), in order: renewals from Giving gifts (R-MEM6), renewals from active recurring
 * gifts and lapse handling (R-MEM4), reminders (R-MEM5), then certification expiry (R-MEM12). Each phase takes up to `ROWS`
 * terms a night; the rest wait for the next. It acts for the organization, in system mode.
 *
 * Giving is read by name (dynamic SOQL, names qualified by the namespace), so this package never
 * depends on it; with Giving absent the gift phases do nothing.
 */
public with sharing class MembershipRenewals implements Schedulable {
	public static final String JOB_NAME = 'BarnCRM Memberships Renewals';
	private static final Integer ROWS = 2000;
	private static final Integer GIFT_WINDOW_DAYS = 45;
	private static final String CONTEXT = 'MembershipRenewals';
	private static final Map<String, Integer> PER_YEAR = new Map<String, Integer>{
		'Weekly' => 52,
		'Every two weeks' => 26,
		'Monthly' => 12,
		'Quarterly' => 4,
		'Twice a year' => 2,
		'Yearly' => 1
	};

	/** One received gift allocated to a level's fund, as the gift phase reads it. */
	public class GiftRow {
		public Id giftId;
		public Id contactId;
		public Id accountId;
		public Date giftDate;
		public Decimal amount;
		public String fundId;
		public Id commitmentId;
	}

	/** Set by tests: the gifts to read, since Giving is not in this package's org. */
	@TestVisible
	private static List<GiftRow> giftsOverride;
	/** Set by tests: the commitment ids still Active. */
	@TestVisible
	private static Set<String> activeCommitmentsOverride;
	@TestVisible
	private static EmailSender emailSender = new MessagingEmailSender();

	public static NightlyStep step() {
		return new NightlyStep(
				JOB_NAME,
				BarnHelp.text('Memberships', 'Memberships_Nightly_Step'),
				6,
				50,
				new MembershipRenewals()
			)
			.activeWhen(MembershipService.moduleOn());
	}

	public void execute(SchedulableContext context) {
		run();
	}

	/** Every phase, each in its own try so one failing does not stop the others. */
	public static void run() {
		try {
			if (MembershipsSettings.renewFromGifts()) {
				renewFromGifts();
			}
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.gifts');
		}
		try {
			lapse();
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.lapse');
		}
		try {
			if (MembershipsSettings.remindersEnabled()) {
				remind();
			}
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.remind');
		}
		try {
			CertificationService.expire();
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.certifications');
		}
	}

	// ---- R-MEM6 gift renewals --------------------------------------------------------------

	/** Each recent gift to a level's fund pays a term at the highest level it meets. */
	@TestVisible
	private static Integer renewFromGifts() {
		Map<String, List<Membership_Level__c>> byFund = new Map<String, List<Membership_Level__c>>();
		for (Membership_Level__c level : [
			SELECT Id, Dues__c, Term_Months__c, Fund_Id__c
			FROM Membership_Level__c
			WHERE Active__c = TRUE AND Fund_Id__c != NULL
			WITH SYSTEM_MODE
			ORDER BY Dues__c DESC
		]) {
			String fund = level.Fund_Id__c.left(15);
			if (!byFund.containsKey(fund)) {
				byFund.put(fund, new List<Membership_Level__c>());
			}
			byFund.get(fund).add(level);
		}
		if (byFund.isEmpty()) {
			return 0;
		}
		List<GiftRow> gifts = recentGifts(byFund.keySet());
		Set<String> used = new Set<String>();
		Set<Id> contacts = new Set<Id>();
		Set<Id> accounts = new Set<Id>();
		Map<Id, Decimal> yearly = commitmentYearly(gifts);
		for (GiftRow gift : gifts) {
			used.add(gift.giftId);
			contacts.add(gift.contactId);
			accounts.add(gift.accountId);
		}
		for (Membership_Term__c term : [
			SELECT Gift_Id__c
			FROM Membership_Term__c
			WHERE Gift_Id__c IN :used
			WITH SYSTEM_MODE
		]) {
			used.remove(term.Gift_Id__c);
		}
		Map<Id, Membership_Term__c> latest = latestTerms(contacts, accounts);
		List<MembershipService.Renewal> renewals = new List<MembershipService.Renewal>();
		List<Membership_Term__c> joins = new List<Membership_Term__c>();
		List<Membership_Term__c> activations = new List<Membership_Term__c>();
		Set<Id> taken = new Set<Id>();
		for (GiftRow gift : gifts) {
			Id member = gift.accountId != null ? gift.accountId : gift.contactId;
			Decimal counts = gift.commitmentId != null && yearly.containsKey(gift.commitmentId)
				? yearly.get(gift.commitmentId)
				: gift.amount;
			Membership_Level__c level = levelMet(byFund.get(gift.fundId.left(15)), counts);
			if (
				!used.contains(gift.giftId) ||
				member == null ||
				level == null ||
				taken.contains(member)
			) {
				continue;
			}
			taken.add(member);
			String source = gift.commitmentId == null ? 'Gift' : 'Recurring Gift';
			Membership_Term__c last = latest.get(member);
			if (last != null && last.Status__c == MembershipService.PENDING) {
				activations.add(
					new Membership_Term__c(
						Id = last.Id,
						Level__c = level.Id,
						Status__c = MembershipService.CURRENT,
						Start_Date__c = gift.giftDate,
						End_Date__c = MembershipService.endOf(gift.giftDate, level),
						Member_Since__c = last.Member_Since__c != null
							? last.Member_Since__c
							: gift.giftDate,
						Source__c = source,
						Amount_Paid__c = gift.amount,
						Gift_Id__c = gift.giftId,
						Commitment_Id__c = gift.commitmentId
					)
				);
			} else if (last != null) {
				MembershipService.Renewal renewal = new MembershipService.Renewal(last.Id);
				renewal.levelId = level.Id;
				renewal.onDate = gift.giftDate;
				renewal.source = source;
				renewal.amountPaid = gift.amount;
				renewal.giftId = gift.giftId;
				renewal.commitmentId = gift.commitmentId;
				renewals.add(renewal);
			} else {
				joins.add(
					new Membership_Term__c(
						Level__c = level.Id,
						Contact__c = gift.contactId,
						Account__c = gift.accountId,
						Status__c = MembershipService.CURRENT,
						Start_Date__c = gift.giftDate,
						Source__c = source,
						Amount_Paid__c = gift.amount,
						Gift_Id__c = gift.giftId,
						Commitment_Id__c = gift.commitmentId
					)
				);
			}
		}
		insert as system joins;
		update as system activations;
		MembershipService.renew(renewals, true);
		return joins.size() + activations.size() + renewals.size();
	}

	/** The highest active level on the fund whose dues the amount meets (levels by dues, high first). */
	@TestVisible
	private static Membership_Level__c levelMet(List<Membership_Level__c> levels, Decimal amount) {
		for (
			Membership_Level__c level : levels == null ? new List<Membership_Level__c>() : levels
		) {
			if (amount != null && amount >= (level.Dues__c == null ? 0 : level.Dues__c)) {
				return level;
			}
		}
		return null;
	}

	/** Each member's newest term not Renewed or Cancelled, keyed by account, else contact. */
	private static Map<Id, Membership_Term__c> latestTerms(Set<Id> contacts, Set<Id> accounts) {
		Map<Id, Membership_Term__c> latest = new Map<Id, Membership_Term__c>();
		for (Membership_Term__c term : [
			SELECT Id, Status__c, Contact__c, Account__c, Member_Since__c
			FROM Membership_Term__c
			WHERE
				(Account__c IN :accounts
				OR (Account__c = NULL
				AND Contact__c IN :contacts))
				AND Status__c NOT IN ('Renewed', 'Cancelled')
			WITH SYSTEM_MODE
			ORDER BY Start_Date__c ASC NULLS FIRST
		]) {
			latest.put(term.Account__c != null ? term.Account__c : term.Contact__c, term);
		}
		return latest;
	}

	/** Received gifts of the last 45 days allocated to the funds, read from Giving by name. */
	private static List<GiftRow> recentGifts(Set<String> fundIds) {
		if (giftsOverride != null) {
			return giftsOverride;
		}
		String ns = NamespaceUtil.prefix();
		if (NamespaceUtil.objectType('Gift_Allocation__c') == null) {
			return new List<GiftRow>();
		}
		List<GiftRow> rows = new List<GiftRow>();
		String query =
			'SELECT {ns}Amount__c, {ns}Fund__c, {ns}Gift__c, {ns}Gift__r.{ns}Donor_Contact__c,' +
			' {ns}Gift__r.{ns}Donor_Account__c, {ns}Gift__r.{ns}Gift_Date__c, {ns}Gift__r.{ns}Commitment__c' +
			' FROM {ns}Gift_Allocation__c WHERE {ns}Fund__c IN :funds AND {ns}Gift__r.{ns}Status__c = \'Received\'' +
			' AND {ns}Gift__r.{ns}Gift_Date__c >= :since ORDER BY {ns}Gift__r.{ns}Gift_Date__c LIMIT ' +
			ROWS;
		for (
			SObject allocation : Database.queryWithBinds(
				query.replace('{ns}', ns),
				new Map<String, Object>{
					'funds' => fundIds,
					'since' => MembershipService.today().addDays(-GIFT_WINDOW_DAYS)
				},
				AccessLevel.SYSTEM_MODE
			)
		) {
			SObject gift = allocation.getSObject(ns + 'Gift__r');
			GiftRow row = new GiftRow();
			row.giftId = (Id) allocation.get(ns + 'Gift__c');
			row.amount = (Decimal) allocation.get(ns + 'Amount__c');
			row.fundId = String.valueOf(allocation.get(ns + 'Fund__c'));
			row.contactId = (Id) gift.get(ns + 'Donor_Contact__c');
			row.accountId = (Id) gift.get(ns + 'Donor_Account__c');
			row.giftDate = (Date) gift.get(ns + 'Gift_Date__c');
			row.commitmentId = (Id) gift.get(ns + 'Commitment__c');
			rows.add(row);
		}
		return rows;
	}

	/** The yearly amount of each Recurring commitment the gifts belong to. */
	private static Map<Id, Decimal> commitmentYearly(List<GiftRow> gifts) {
		Set<Id> ids = new Set<Id>();
		for (GiftRow gift : gifts) {
			ids.add(gift.commitmentId);
		}
		ids.remove(null);
		Map<Id, Decimal> yearly = new Map<Id, Decimal>();
		if (
			ids.isEmpty() ||
			giftsOverride != null ||
			NamespaceUtil.objectType('Commitment__c') == null
		) {
			return yearly;
		}
		String ns = NamespaceUtil.prefix();
		for (
			SObject commitment : Database.queryWithBinds(
				('SELECT Id, {ns}Amount__c, {ns}Frequency__c FROM {ns}Commitment__c' +
					' WHERE Id IN :ids AND {ns}Type__c = \'Recurring\'')
					.replace('{ns}', ns),
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.SYSTEM_MODE
			)
		) {
			Integer times = PER_YEAR.get((String) commitment.get(ns + 'Frequency__c'));
			Decimal amount = (Decimal) commitment.get(ns + 'Amount__c');
			if (times != null && amount != null) {
				yearly.put(commitment.Id, amount * times);
			}
		}
		return yearly;
	}

	// ---- R-MEM4 recurring renewals and lapse ----------------------------------------------

	/** Ended terms renew from an active recurring gift, or move to Grace or Lapsed. */
	@TestVisible
	private static Integer lapse() {
		Date today = MembershipService.today();
		List<Membership_Term__c> ended = [
			SELECT Id, Status__c, End_Date__c, Commitment_Id__c, Level__r.Grace_Days__c
			FROM Membership_Term__c
			WHERE Status__c IN ('Current', 'Grace') AND End_Date__c < :today
			WITH SYSTEM_MODE
			ORDER BY End_Date__c
			LIMIT :ROWS
		];
		Set<String> active = activeCommitments(ended);
		List<MembershipService.Renewal> renewals = new List<MembershipService.Renewal>();
		List<Membership_Term__c> moved = new List<Membership_Term__c>();
		for (Membership_Term__c term : ended) {
			if (term.Commitment_Id__c != null && active.contains(term.Commitment_Id__c.left(15))) {
				MembershipService.Renewal renewal = new MembershipService.Renewal(term.Id);
				renewal.source = 'Recurring Gift';
				renewals.add(renewal);
				continue;
			}
			Decimal grace = term.Level__r.Grace_Days__c == null ? 0 : term.Level__r.Grace_Days__c;
			String status = term.End_Date__c.addDays(grace.intValue()) >= today
				? MembershipService.GRACE
				: MembershipService.LAPSED;
			if (status != term.Status__c) {
				moved.add(new Membership_Term__c(Id = term.Id, Status__c = status));
			}
		}
		update as system moved;
		MembershipService.renew(renewals, true);
		return moved.size() + renewals.size();
	}

	private static Set<String> activeCommitments(List<Membership_Term__c> terms) {
		if (activeCommitmentsOverride != null) {
			return activeCommitmentsOverride;
		}
		Set<Id> ids = new Set<Id>();
		for (Membership_Term__c term : terms) {
			if (term.Commitment_Id__c instanceof Id) {
				ids.add(Id.valueOf(term.Commitment_Id__c));
			}
		}
		Set<String> active = new Set<String>();
		if (ids.isEmpty() || NamespaceUtil.objectType('Commitment__c') == null) {
			return active;
		}
		String ns = NamespaceUtil.prefix();
		for (
			SObject row : Database.queryWithBinds(
				('SELECT Id FROM {ns}Commitment__c WHERE Id IN :ids AND {ns}Status__c = \'Active\'')
					.replace('{ns}', ns),
				new Map<String, Object>{ 'ids' => ids },
				AccessLevel.SYSTEM_MODE
			)
		) {
			active.add(String.valueOf(row.Id).left(15));
		}
		return active;
	}

	// ---- R-MEM5 reminders ------------------------------------------------------------------

	/** One reminder per term, stamped before sending and unstamped when the send fails. */
	@TestVisible
	private static Integer remind() {
		Date today = MembershipService.today();
		Date until = today.addDays(MembershipsSettings.reminderDays());
		Id templateId = MembershipEmails.templateId(MembershipsSettings.reminderTemplate());
		if (templateId == null) {
			ErrorLogger.logMessage(
				BarnHelp.text('Memberships', 'Memberships_Error_NoTemplate'),
				CONTEXT,
				ErrorLogger.SEVERITY_WARNING
			);
			return 0;
		}
		List<Membership_Term__c> due = new List<Membership_Term__c>();
		for (Membership_Term__c term : [
			SELECT Id, Contact__c, End_Date__c, Reminded_For__c
			FROM Membership_Term__c
			WHERE
				Status__c = 'Current'
				AND End_Date__c >= :today
				AND End_Date__c <= :until
				AND Contact__r.Email != NULL
				AND Contact__r.HasOptedOutOfEmail = FALSE
			WITH SYSTEM_MODE
			LIMIT :ROWS
		]) {
			if (term.Reminded_For__c != term.End_Date__c) {
				due.add(term);
			}
		}
		return MembershipEmails.send(due, templateId, 'Reminded_For__c', emailSender);
	}
}
