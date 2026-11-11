/**
 * Reviews (SG-03) and reviewer panels (SG-10): the rubric (R-SG4), a review's weighted score
 * (R-SG6), saving, submitting and recusing one's own review (R-SG7), Assign Reviewers (R-SG8)
 * and the cycle's ranked review board. User mode throughout (ADR-NEXT
 * `NEXT-scholarships-outbound-grants-module.md`, decisions 6 and 7).
 */
public with sharing class ScholarshipReviews {
	public static final String ASSIGNED = 'Assigned';
	public static final String SUBMITTED = 'Submitted';
	public static final String RECUSED = 'Recused';
	/** Applications that can be reviewed. */
	public static final Set<String> REVIEWABLE = new Set<String>{
		'Submitted',
		'Eligible',
		'In Review'
	};
	private static final Integer MAX_ROWS = 2000;

	/** One rubric criterion. */
	public class Criterion {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public Decimal max;
		@AuraEnabled
		public Decimal weight;
	}

	/** One line of the review board. */
	public class BoardRow {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String applicant;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Decimal requested;
		@AuraEnabled
		public Decimal average;
		@AuraEnabled
		public Integer submitted;
		@AuraEnabled
		public Integer rank;
	}

	/** The rubric of a cycle; blank or unreadable means one overall score from 0 to 10. */
	public static List<Criterion> rubric(String rubricJson) {
		List<Criterion> criteria = new List<Criterion>();
		if (String.isNotBlank(rubricJson)) {
			try {
				for (Object item : (List<Object>) JSON.deserializeUntyped(rubricJson)) {
					Map<String, Object> raw = (Map<String, Object>) item;
					Criterion one = criterion(
						String.valueOf(raw.get('key')),
						raw.get('label') == null
							? String.valueOf(raw.get('key'))
							: String.valueOf(raw.get('label')),
						number(raw.get('max'), 10),
						number(raw.get('weight'), 1)
					);
					if (String.isNotBlank(one.key)) {
						criteria.add(one);
					}
				}
			} catch (Exception unreadable) {
				ErrorLogger.log(unreadable, 'ScholarshipReviews.rubric');
				criteria.clear();
			}
		}
		if (criteria.isEmpty()) {
			criteria.add(
				criterion(
					'overall',
					BarnHelp.text('Scholarships', 'Scholarships_Review_Overall'),
					10,
					1
				)
			);
		}
		return criteria;
	}

	/** R-SG6: each criterion's score, between 0 and its max, times its weight, added together. */
	public static Decimal score(List<Criterion> criteria, Map<String, Object> scores) {
		Decimal total = 0;
		for (Criterion one : criteria) {
			Decimal given = scores == null ? 0 : number(scores.get(one.key), 0);
			total += Math.max(0, Math.min(given, one.max)) * one.weight;
		}
		return total.setScale(2);
	}

	/**
	 * Saves the running user's own review of an application: `save`, `submit` or `recuse` (with a
	 * reason). A person with no review yet gets one. Returns the review.
	 */
	public static Application_Review__c saveOwn(
		Id applicationId,
		Map<String, Object> scores,
		String comments,
		String action,
		String reason
	) {
		Award_Application__c application = [
			SELECT Id, Cycle__r.Rubric__c
			FROM Award_Application__c
			WHERE Id = :applicationId
			WITH USER_MODE
		];
		Application_Review__c review = own(applicationId);
		if (review == null) {
			review = new Application_Review__c(
				Application__c = applicationId,
				Reviewer__c = UserInfo.getUserId()
			);
		}
		if (action == 'recuse') {
			if (String.isBlank(reason)) {
				throw Scholarships.refuse(
					BarnHelp.text('Scholarships', 'Scholarships_Review_ReasonNeeded')
				);
			}
			review.Status__c = RECUSED;
			review.Recusal_Reason__c = reason.abbreviate(255);
		} else {
			review.Scores__c = JSON.serialize(scores == null ? new Map<String, Object>() : scores);
			review.Score__c = score(rubric(application.Cycle__r.Rubric__c), scores);
			review.Comments__c = comments;
			review.Status__c = action == 'submit' ? SUBMITTED : ASSIGNED;
		}
		upsert as user review;
		return review;
	}

	/** The running user's review of an application, or null. */
	public static Application_Review__c own(Id applicationId) {
		List<Application_Review__c> reviews = [
			SELECT Id, Status__c, Scores__c, Score__c, Comments__c, Recusal_Reason__c
			FROM Application_Review__c
			WHERE Application__c = :applicationId AND Reviewer__c = :UserInfo.getUserId()
			WITH USER_MODE
			ORDER BY CreatedDate
			LIMIT 1
		];
		return reviews.isEmpty() ? null : reviews[0];
	}

	/**
	 * R-SG8 Assign Reviewers: fills each reviewable application up to the cycle's reviewers per
	 * application from its panel group, each next review to the least loaded member, never to one
	 * who already has a review of it. Returns how many reviews it created.
	 */
	public static Integer assign(Id cycleId) {
		Scholarships.requireManage();
		Award_Cycle__c cycle = [
			SELECT Id, Name, Reviewer_Group__c, Reviewers_Per_Application__c
			FROM Award_Cycle__c
			WHERE Id = :cycleId
			WITH USER_MODE
		];
		List<Id> panel = panel(cycle.Reviewer_Group__c);
		if (panel.isEmpty()) {
			throw Scholarships.refuse(BarnHelp.text('Scholarships', 'Scholarships_Assign_NoPanel'));
		}
		Integer perApplication = cycle.Reviewers_Per_Application__c == null
			? 2
			: Math.max(1, cycle.Reviewers_Per_Application__c.intValue());
		Map<Id, Integer> load = new Map<Id, Integer>();
		for (Id member : panel) {
			load.put(member, 0);
		}
		List<Award_Application__c> applications = [
			SELECT Id, Status__c, (SELECT Reviewer__c, Status__c FROM Reviews__r)
			FROM Award_Application__c
			WHERE Cycle__c = :cycleId AND Status__c IN :REVIEWABLE
			WITH USER_MODE
			ORDER BY Submitted_Date__c NULLS LAST, Name
			LIMIT :MAX_ROWS
		];
		for (Award_Application__c application : applications) {
			for (Application_Review__c review : application.Reviews__r) {
				if (review.Status__c == ASSIGNED && load.containsKey(review.Reviewer__c)) {
					load.put(review.Reviewer__c, load.get(review.Reviewer__c) + 1);
				}
			}
		}
		List<Application_Review__c> created = new List<Application_Review__c>();
		List<Award_Application__c> started = new List<Award_Application__c>();
		for (Award_Application__c application : applications) {
			Set<Id> already = new Set<Id>();
			Integer active = 0;
			for (Application_Review__c review : application.Reviews__r) {
				already.add(review.Reviewer__c);
				active += review.Status__c == RECUSED ? 0 : 1;
			}
			while (active < perApplication) {
				Id next = leastLoaded(load, already);
				if (next == null) {
					break;
				}
				created.add(
					new Application_Review__c(
						Application__c = application.Id,
						Reviewer__c = next,
						Status__c = ASSIGNED
					)
				);
				already.add(next);
				load.put(next, load.get(next) + 1);
				active++;
			}
			if (active > 0 && application.Status__c != 'In Review') {
				started.add(new Award_Application__c(Id = application.Id, Status__c = 'In Review'));
			}
		}
		insert as user created;
		update as user started;
		Set<String> notified = new Set<String>();
		for (Application_Review__c review : created) {
			notified.add(review.Reviewer__c);
		}
		Scholarships.notify(
			notified,
			BarnHelp.text(
				'Scholarships',
				'Scholarships_Notify_Assigned',
				new List<Object>{ cycle.Name }
			),
			cycle.Id
		);
		return created.size();
	}

	/** R-SG8: the member with the fewest open reviews who has none of this application. */
	@TestVisible
	private static Id leastLoaded(Map<Id, Integer> load, Set<Id> excluded) {
		Id best;
		for (Id member : load.keySet()) {
			if (!excluded.contains(member) && (best == null || load.get(member) < load.get(best))) {
				best = member;
			}
		}
		return best;
	}

	/** The active users in the panel group, by its API name. */
	private static List<Id> panel(String groupName) {
		List<Id> members = new List<Id>();
		if (String.isBlank(groupName)) {
			return members;
		}
		Set<Id> userIds = new Set<Id>();
		for (GroupMember member : [
			SELECT UserOrGroupId
			FROM GroupMember
			WHERE Group.DeveloperName = :groupName.trim() AND Group.Type = 'Regular'
			WITH SYSTEM_MODE
		]) {
			if (member.UserOrGroupId.getSObjectType() == User.SObjectType) {
				userIds.add(member.UserOrGroupId);
			}
		}
		for (User person : [
			SELECT Id
			FROM User
			WHERE Id IN :userIds AND IsActive = TRUE
			WITH SYSTEM_MODE
			ORDER BY Name
		]) {
			members.add(person.Id);
		}
		return members;
	}

	/** The cycle's applications ranked by average score; blind review hides applicants from reviewers. */
	public static List<BoardRow> board(Id cycleId, Boolean hideApplicants) {
		List<BoardRow> rows = new List<BoardRow>();
		Integer rank = 0;
		for (Award_Application__c application : [
			SELECT
				Id,
				Name,
				Status__c,
				Amount_Requested__c,
				Average_Score__c,
				Review_Count__c,
				Contact__r.Name,
				Organization__r.Name
			FROM Award_Application__c
			WHERE Cycle__c = :cycleId AND Status__c NOT IN ('Draft', 'Withdrawn')
			WITH USER_MODE
			ORDER BY Average_Score__c DESC NULLS LAST, Name
			LIMIT :MAX_ROWS
		]) {
			BoardRow row = new BoardRow();
			row.id = application.Id;
			row.name = application.Name;
			row.applicant = hideApplicants
				? null
				: application.Organization__r?.Name ?? application.Contact__r?.Name;
			row.status = application.Status__c;
			row.requested = application.Amount_Requested__c;
			row.average = application.Average_Score__c;
			row.submitted = application.Review_Count__c == null
				? 0
				: application.Review_Count__c.intValue();
			row.rank = application.Average_Score__c == null ? null : ++rank;
			rows.add(row);
		}
		return rows;
	}

	private static Criterion criterion(String key, String label, Decimal max, Decimal weight) {
		Criterion one = new Criterion();
		one.key = key;
		one.label = label;
		one.max = max;
		one.weight = weight;
		return one;
	}

	private static Decimal number(Object value, Decimal fallback) {
		if (value == null) {
			return fallback;
		}
		try {
			return Decimal.valueOf(String.valueOf(value));
		} catch (TypeException notANumber) {
			return fallback;
		}
	}
}
