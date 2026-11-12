/**
 * Membership terms (canonical model 29MEM3; ADR-NEXT `NEXT-memberships-module.md`, decisions 3
 * and 4): what a new term fills on save (R-MEM1) and how a term is renewed (R-MEM3). Every
 * renewal path, staff, gifts, recurring gifts and online payments, comes through `renew`, so a
 * new term is always made the same way.
 */
public with sharing class MembershipService {
	public static final String PENDING = 'Pending';
	public static final String CURRENT = 'Current';
	public static final String GRACE = 'Grace';
	public static final String LAPSED = 'Lapsed';
	public static final String RENEWED = 'Renewed';
	public static final String CANCELLED = 'Cancelled';
	public static final String MODULE = 'Memberships';

	/** A renewal or payment that cannot be made, with a message fit to show. */
	public class MembershipException extends Exception {
	}

	/** One renewal: the term renewed and, optionally, what pays for the next one. */
	public class Renewal {
		public Id termId;
		public Id levelId;
		public Date onDate;
		public String source = 'Staff';
		public Decimal amountPaid;
		public String giftId;
		public String commitmentId;
		public String paymentId;

		public Renewal(Id termId) {
			this.termId = termId;
		}
	}

	/** A test sets the date. */
	@TestVisible
	private static Date todayOverride;

	public static Date today() {
		return todayOverride != null ? todayOverride : Date.today();
	}

	/** Whether the module is on in the Module Manager. */
	public static Boolean moduleOn() {
		return !ModuleManagerService.turnedOff().contains(MODULE.toLowerCase());
	}

	/** R-MEM1: dues, start, end and member since, for what is blank on new terms. */
	public static void fill(List<Membership_Term__c> terms) {
		Set<Id> levelIds = new Set<Id>();
		Set<Id> previousIds = new Set<Id>();
		for (Membership_Term__c term : terms) {
			levelIds.add(term.Level__c);
			previousIds.add(term.Previous_Term__c);
		}
		Map<Id, Membership_Level__c> levels = levels(levelIds);
		Map<Id, Membership_Term__c> previous = new Map<Id, Membership_Term__c>(
			[
				SELECT Id, Member_Since__c, Start_Date__c
				FROM Membership_Term__c
				WHERE Id IN :previousIds
				WITH SYSTEM_MODE
			]
		);
		for (Membership_Term__c term : terms) {
			Membership_Level__c level = levels.get(term.Level__c);
			if (term.Dues__c == null && level != null) {
				term.Dues__c = level.Dues__c;
			}
			if (term.Start_Date__c == null && term.Status__c == CURRENT) {
				term.Start_Date__c = today();
			}
			if (term.End_Date__c == null && term.Start_Date__c != null && level != null) {
				term.End_Date__c = endOf(term.Start_Date__c, level);
			}
			Membership_Term__c before = previous.get(term.Previous_Term__c);
			if (term.Member_Since__c == null) {
				term.Member_Since__c = before == null
					? term.Start_Date__c
					: (before.Member_Since__c != null
							? before.Member_Since__c
							: before.Start_Date__c);
			}
		}
	}

	/** The last day of a term starting on `starts`, or null when the level does not expire. */
	public static Date endOf(Date starts, Membership_Level__c level) {
		Integer months = level == null ||
			level.Term_Months__c == null
			? 12
			: level.Term_Months__c.intValue();
		return starts == null || months <= 0 ? null : starts.addMonths(months).addDays(-1);
	}

	/**
	 * R-MEM3: a new term for each renewal, the renewed term marked Renewed. `asSystem` is true
	 * for the nightly run and the payment listener, which act for the organization; staff renew
	 * in user mode. Returns the new terms in the order asked.
	 */
	public static List<Membership_Term__c> renew(List<Renewal> requests, Boolean asSystem) {
		Set<Id> termIds = new Set<Id>();
		Set<Id> levelIds = new Set<Id>();
		for (Renewal request : requests) {
			termIds.add(request.termId);
			levelIds.add(request.levelId);
		}
		Map<Id, Membership_Term__c> olds = new Map<Id, Membership_Term__c>(
			Database.queryWithBinds(
				'SELECT Id, Status__c, Level__c, Contact__c, Account__c, End_Date__c, Start_Date__c,' +
					' Member_Since__c, Commitment_Id__c, Directory_Opt_In__c, Directory_Location__c,' +
					' Directory_Bio__c FROM Membership_Term__c WHERE Id IN :termIds',
				new Map<String, Object>{ 'termIds' => termIds },
				asSystem ? AccessLevel.SYSTEM_MODE : AccessLevel.USER_MODE
			)
		);
		for (Membership_Term__c old : olds.values()) {
			levelIds.add(old.Level__c);
		}
		Map<Id, Membership_Level__c> levels = levels(levelIds);
		List<Membership_Term__c> made = new List<Membership_Term__c>();
		List<Membership_Term__c> closed = new List<Membership_Term__c>();
		for (Renewal request : requests) {
			Membership_Term__c old = olds.get(request.termId);
			if (old == null) {
				throw new MembershipException(
					BarnHelp.text('Memberships', 'Memberships_Error_NotFound')
				);
			}
			if (old.Status__c != CURRENT && old.Status__c != GRACE && old.Status__c != LAPSED) {
				throw new MembershipException(
					BarnHelp.text('Memberships', 'Memberships_Error_CannotRenew')
				);
			}
			Membership_Level__c level = levels.get(
				request.levelId != null ? request.levelId : old.Level__c
			);
			if (level == null) {
				throw new MembershipException(
					BarnHelp.text('Memberships', 'Memberships_Error_NoLevel')
				);
			}
			Boolean continues = old.Status__c != LAPSED && old.End_Date__c != null;
			Date starts = continues
				? old.End_Date__c.addDays(1)
				: (request.onDate != null ? request.onDate : today());
			made.add(
				new Membership_Term__c(
					Level__c = level.Id,
					Contact__c = old.Contact__c,
					Account__c = old.Account__c,
					Status__c = CURRENT,
					Start_Date__c = starts,
					End_Date__c = endOf(starts, level),
					Member_Since__c = old.Member_Since__c != null
						? old.Member_Since__c
						: old.Start_Date__c,
					Previous_Term__c = old.Id,
					Origin__c = continues ? 'Renewal' : 'Rejoin',
					Source__c = request.source,
					Dues__c = level.Dues__c,
					Amount_Paid__c = request.amountPaid,
					Gift_Id__c = request.giftId,
					Commitment_Id__c = request.commitmentId != null
						? request.commitmentId
						: old.Commitment_Id__c,
					Payment_Id__c = request.paymentId,
					Directory_Opt_In__c = old.Directory_Opt_In__c,
					Directory_Location__c = old.Directory_Location__c,
					Directory_Bio__c = old.Directory_Bio__c
				)
			);
			closed.add(new Membership_Term__c(Id = old.Id, Status__c = RENEWED));
		}
		if (asSystem) {
			insert as system made;
			update as system closed;
		} else {
			insert as user made;
			update as user closed;
		}
		return made;
	}

	/** Levels by id, read in system mode: levels are reference data every member's term names. */
	public static Map<Id, Membership_Level__c> levels(Set<Id> levelIds) {
		return new Map<Id, Membership_Level__c>(
			[
				SELECT Id, Name, Dues__c, Term_Months__c, Grace_Days__c, Active__c, Fund_Id__c
				FROM Membership_Level__c
				WHERE Id IN :levelIds
				WITH SYSTEM_MODE
			]
		);
	}
}
