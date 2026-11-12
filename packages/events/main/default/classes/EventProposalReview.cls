/**
 * Session proposal management (EV-21; ADR-0207 `0207-events-paid-registration-proposals-ratings.md`,
 * decisions 8 to 12; canonical model R-SA6 to R-SA9, R-PP1): weighted review criteria per event,
 * co-presenters, and reviewer assignments. An assignment is a Speaker Review with a reviewer and no
 * score yet; only scored reviews count in the roll-ups.
 *
 * The weighted rule is the one `eventApplicationsModel` holds in the browser, repeated here and
 * tested against the same cases (the `EventPricing` pattern): each criterion is scored from 1 to 5,
 * the weighted score is sum(weight x score) / sum(weight) to two decimals, and the review's Score
 * is that rounded to the nearest whole number (halves up).
 */
public with sharing class EventProposalReview {
	public static final Integer MAX_CRITERIA = 10;
	public static final Integer MAX_WEIGHT = 10;
	public static final Integer MAX_LABEL = 40;
	public static final Integer MAX_PRESENTERS = 5;
	private static final String CONTEXT = 'EventProposalReview';
	private static final Set<String> UNDECIDED = new Set<String>{ 'Submitted', 'In Review' };

	/** One weighted criterion of an event's review. */
	public class Criterion {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public Integer weight;
	}

	/** The criteria an event's JSON holds; an unreadable or empty value gives none. */
	public static List<Criterion> criteriaOf(String criteriaJson) {
		try {
			return String.isBlank(criteriaJson) ? new List<Criterion>() : validated(criteriaJson);
		} catch (Exception unreadable) {
			return new List<Criterion>();
		}
	}

	/**
	 * Up to 10 criteria with a label (unique, ignoring case, up to 40 characters) and a whole
	 * weight from 1 to 10 (R-SA6).
	 *
	 * @throws IllegalArgumentException in words for the person when they are not
	 */
	public static List<Criterion> validated(String criteriaJson) {
		List<Criterion> criteria = String.isBlank(criteriaJson)
			? new List<Criterion>()
			: (List<Criterion>) JSON.deserialize(criteriaJson, List<Criterion>.class);
		Set<String> seen = new Set<String>();
		for (Criterion criterion : criteria) {
			criterion.label = criterion.label == null ? '' : criterion.label.trim();
			if (
				String.isBlank(criterion.label) ||
				criterion.label.length() > MAX_LABEL ||
				criterion.weight == null ||
				criterion.weight < 1 ||
				criterion.weight > MAX_WEIGHT ||
				!seen.add(criterion.label.toLowerCase())
			) {
				throw new IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Applications_CriteriaInvalid')
				);
			}
		}
		if (criteria.size() > MAX_CRITERIA) {
			throw new IllegalArgumentException(
				BarnHelp.text('Events', 'Events_Applications_CriteriaInvalid')
			);
		}
		return criteria;
	}

	/**
	 * R-SA7: the weighted score of one review, from a score of 1 to 5 for every criterion.
	 *
	 * @throws IllegalArgumentException when a criterion is unscored or out of range
	 */
	public static Decimal weightedScore(List<Criterion> criteria, Map<String, Object> scores) {
		Decimal total = 0;
		Decimal weights = 0;
		for (Criterion criterion : criteria) {
			Object given = scores == null ? null : scores.get(criterion.label);
			Integer score;
			try {
				score = given == null ? null : Integer.valueOf(String.valueOf(given));
			} catch (Exception notANumber) {
				score = null;
			}
			if (score == null || score < 1 || score > 5) {
				throw new IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Applications_ScoreEach')
				);
			}
			total += criterion.weight * score;
			weights += criterion.weight;
		}
		return weights == 0 ? null : (total / weights).setScale(2, System.RoundingMode.HALF_UP);
	}

	/**
	 * Saves the event's review criteria, or clears them with an empty list.
	 *
	 * @param eventId the event
	 * @param criteriaJson a JSON list of `{ "label": "Relevance", "weight": 2 }`
	 */
	@AuraEnabled
	public static void saveCriteria(Id eventId, String criteriaJson) {
		try {
			List<Criterion> criteria = validated(criteriaJson);
			update as user new Event__c(
				Id = eventId,
				Review_Criteria__c = criteria.isEmpty() ? null : JSON.serialize(criteria)
			);
		} catch (IllegalArgumentException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (JSONException unreadable) {
			throw UserErrors.message(
				BarnHelp.text('Events', 'Events_Applications_CriteriaInvalid')
			);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.saveCriteria', eventId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * R-PP1: names one more person on an undecided proposal: up to 5, never the applicant, never
	 * twice.
	 */
	@AuraEnabled
	public static Id addPresenter(Id applicationId, Id contactId, String role) {
		try {
			Speaker_Application__c application = undecided(applicationId);
			List<Proposal_Presenter__c> current = [
				SELECT Contact__c
				FROM Proposal_Presenter__c
				WHERE Speaker_Application__c = :applicationId
				WITH USER_MODE
			];
			if (current.size() >= MAX_PRESENTERS) {
				throw new IllegalArgumentException(
					BarnHelp.text(
						'Events',
						'Events_Applications_PresenterLimit',
						new List<Object>{ MAX_PRESENTERS }
					)
				);
			}
			Boolean twice = contactId == application.Contact__c;
			for (Proposal_Presenter__c presenter : current) {
				twice |= presenter.Contact__c == contactId;
			}
			if (twice) {
				throw new IllegalArgumentException(
					BarnHelp.text('Events', 'Events_Applications_PresenterTwice')
				);
			}
			Proposal_Presenter__c presenter = new Proposal_Presenter__c(
				Speaker_Application__c = applicationId,
				Contact__c = contactId,
				Role__c = String.isBlank(role) ? 'Speaker' : role
			);
			insert as user presenter;
			return presenter.Id;
		} catch (IllegalArgumentException refused) {
			throw UserErrors.message(refused.getMessage());
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.addPresenter', applicationId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** Takes a presenter off a proposal. */
	@AuraEnabled
	public static void removePresenter(Id presenterId) {
		try {
			delete as user new Proposal_Presenter__c(Id = presenterId);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.removePresenter', presenterId);
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/**
	 * R-SA8: assigns a reviewer to the chosen undecided proposals, skipping any they already
	 * review; an assignment is an unscored review.
	 *
	 * @return how many were assigned
	 */
	@AuraEnabled
	public static Integer assignReviewers(List<Id> applicationIds, Id reviewerId) {
		try {
			if (reviewerId == null || applicationIds == null || applicationIds.isEmpty()) {
				return 0;
			}
			Set<Id> already = new Set<Id>();
			for (Speaker_Review__c review : [
				SELECT Speaker_Application__c
				FROM Speaker_Review__c
				WHERE Speaker_Application__c IN :applicationIds AND Reviewer__c = :reviewerId
				WITH USER_MODE
			]) {
				already.add(review.Speaker_Application__c);
			}
			List<Speaker_Review__c> assignments = new List<Speaker_Review__c>();
			for (Speaker_Application__c application : [
				SELECT Id
				FROM Speaker_Application__c
				WHERE Id IN :applicationIds AND Status__c IN :UNDECIDED
				WITH USER_MODE
			]) {
				if (!already.contains(application.Id)) {
					assignments.add(
						new Speaker_Review__c(
							Speaker_Application__c = application.Id,
							Reviewer__c = reviewerId
						)
					);
				}
			}
			insert as user assignments;
			return assignments.size();
		} catch (DmlException e) {
			throw UserErrors.message(e.getDmlMessage(0));
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.assignReviewers');
			throw UserErrors.wrapShowingDml(e, BarnHelp.text('Events', 'Events_Shared_NotSaved'));
		}
	}

	/** The people named on a proposal besides its applicant, for making them speakers. */
	public static List<Id> presenterContacts(Id applicationId) {
		List<Id> contacts = new List<Id>();
		for (Proposal_Presenter__c presenter : [
			SELECT Contact__c
			FROM Proposal_Presenter__c
			WHERE Speaker_Application__c = :applicationId AND Contact__c != NULL
			WITH USER_MODE
			ORDER BY CreatedDate
		]) {
			contacts.add(presenter.Contact__c);
		}
		return contacts;
	}

	private static Speaker_Application__c undecided(Id applicationId) {
		List<Speaker_Application__c> found = [
			SELECT Id, Contact__c, Status__c
			FROM Speaker_Application__c
			WHERE Id = :applicationId
			WITH USER_MODE
			LIMIT 1
		];
		if (found.isEmpty() || !UNDECIDED.contains(found[0].Status__c)) {
			throw new IllegalArgumentException(
				BarnHelp.text('Events', 'Events_Applications_Decided')
			);
		}
		return found[0];
	}
}
