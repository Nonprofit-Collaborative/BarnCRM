/**
 * Which thank you a gift gets (feature G-12, canonical model R-AK1 and R-AK2, ADR-0032).
 *
 * Matching is a pure function of a gift, the rules, and the set of donors who already had a gift.
 * It holds no state, does no DML, and queries only when it is asked for that donor set, which is
 * what lets the same code run in a before-insert trigger and inside a batch chunk without either
 * of them knowing about the other.
 *
 * Rules are evaluated twice on purpose (R-AK3): once on the save of a gift, to decide whether it
 * joins the queue, and again when the queue is sent, to decide which template each queued gift
 * gets. Nothing is stored on the gift in between, so a rule corrected on Tuesday morning is the
 * rule that applies to Monday's gifts that have not gone out yet.
 */
public with sharing class AcknowledgmentRuleService {
	public static final String CHANNEL_EMAIL = 'Email';
	public static final String CHANNEL_LETTER = 'Letter';
	public static final String CHANNEL_NONE = 'None';

	public static final String STATUS_TO_ACKNOWLEDGE = 'To acknowledge';
	public static final String STATUS_ACKNOWLEDGED = 'Acknowledged';
	public static final String STATUS_NOT_REQUIRED = 'Not required';
	public static final String STATUS_DO_NOT_ACKNOWLEDGE = 'Do not acknowledge';

	private static final String GIFT_STATUS_RECEIVED = 'Received';

	/** The rule that won, flattened, so a caller never has to re-read the rule record. */
	public class RuleMatch {
		public Id ruleId;
		public String ruleName;
		public String channel;
		public String template;

		public RuleMatch(Acknowledgment_Rule__c rule) {
			this.ruleId = rule.Id;
			this.ruleName = rule.Name;
			this.channel = rule.Channel__c;
			this.template = rule.Email_Template__c;
		}
	}

	/**
	 * Whether this gift is the kind of thing that is ever thanked for (R-AK8).
	 *
	 * Only a received gift of a positive amount. That single test is what keeps refunds, write
	 * offs, pending gifts and the negative gifts that record a reversal out of the feature
	 * entirely, rather than each of them being remembered separately in five places.
	 */
	public static Boolean isAcknowledgeable(Gift__c gift) {
		return gift != null &&
			GIFT_STATUS_RECEIVED.equals(gift.Status__c) &&
			gift.Amount__c != null &&
			gift.Amount__c > 0;
	}

	/**
	 * The first active rule that matches this gift, or null when none does (R-AK1).
	 *
	 * @param gift the gift, which need not have been inserted yet
	 * @param orderedRules the active rules, already sorted by Order then Name
	 * @param donorsWithEarlierGifts donor identifiers that already had a positive gift, as text,
	 *        so that a first gift rule can be answered without a query per gift
	 */
	public static RuleMatch matchFor(
		Gift__c gift,
		List<Acknowledgment_Rule__c> orderedRules,
		Set<String> donorsWithEarlierGifts
	) {
		if (!isAcknowledgeable(gift) || orderedRules == null) {
			return null;
		}
		for (Acknowledgment_Rule__c rule : orderedRules) {
			if (matches(rule, gift, donorsWithEarlierGifts)) {
				return new RuleMatch(rule);
			}
		}
		return null;
	}

	/**
	 * Every criterion on one rule, all of which have to hold. An empty criterion is not a
	 * criterion: an empty Gift Type matches every type rather than matching gifts with no type
	 * (R-AK2).
	 */
	@TestVisible
	private static Boolean matches(
		Acknowledgment_Rule__c rule,
		Gift__c gift,
		Set<String> donorsWithEarlierGifts
	) {
		if (rule.Active__c != true) {
			return false;
		}
		if (rule.Minimum_Amount__c != null && gift.Amount__c < rule.Minimum_Amount__c) {
			return false;
		}
		if (rule.Maximum_Amount__c != null && gift.Amount__c > rule.Maximum_Amount__c) {
			return false;
		}
		if (String.isNotBlank(rule.Gift_Type__c) && rule.Gift_Type__c != gift.Type__c) {
			return false;
		}
		if (rule.Appeal__c != null && rule.Appeal__c != gift.Appeal__c) {
			return false;
		}
		if (rule.First_Gift_Only__c == true) {
			String donorKey = donorKeyFor(gift);
			if (donorKey == null) {
				return false;
			}
			if (donorsWithEarlierGifts != null && donorsWithEarlierGifts.contains(donorKey)) {
				return false;
			}
		}
		return true;
	}

	/**
	 * The donor this gift credits, as one value, so that the contact path and the account path
	 * are one key rather than two branches everywhere downstream.
	 */
	public static String donorKeyFor(Gift__c gift) {
		if (gift.Donor_Contact__c != null) {
			return String.valueOf(gift.Donor_Contact__c);
		}
		if (gift.Donor_Account__c != null) {
			return String.valueOf(gift.Donor_Account__c);
		}
		return null;
	}

	/**
	 * The donors among these gifts who already had a positive gift, answered in one query rather
	 * than one per gift (R-AK2).
	 *
	 * The count is taken now rather than read from a rollup, because the rollup for a gift that is
	 * being inserted has not been calculated yet, and a welcome letter that went to a donor's
	 * fourth gift is exactly the mistake this rule exists to avoid.
	 *
	 * @param gifts the gifts being saved
	 * @param giftIdsToIgnore the gifts themselves, on an update, so a gift does not count as its
	 *        own predecessor
	 */
	public static Set<String> donorsWithEarlierGifts(List<Gift__c> gifts, Set<Id> giftIdsToIgnore) {
		Set<String> answered = new Set<String>();
		Set<Id> contactIds = new Set<Id>();
		Set<Id> accountIds = new Set<Id>();
		for (Gift__c gift : gifts) {
			if (gift.Donor_Contact__c != null) {
				contactIds.add(gift.Donor_Contact__c);
			} else if (gift.Donor_Account__c != null) {
				accountIds.add(gift.Donor_Account__c);
			}
		}
		if (contactIds.isEmpty() && accountIds.isEmpty()) {
			return answered;
		}
		Set<Id> ignore = giftIdsToIgnore == null ? new Set<Id>() : giftIdsToIgnore;
		for (Gift__c earlier : [
			SELECT Id, Donor_Contact__c, Donor_Account__c
			FROM Gift__c
			WHERE
				Amount__c > 0
				AND (Donor_Contact__c IN :contactIds
				OR Donor_Account__c IN :accountIds)
				AND Id NOT IN :ignore
			WITH USER_MODE
			LIMIT 10000
		]) {
			String key = donorKeyFor(earlier);
			if (key != null) {
				answered.add(key);
			}
		}
		return answered;
	}
}
