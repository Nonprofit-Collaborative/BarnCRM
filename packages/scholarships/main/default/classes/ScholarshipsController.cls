/**
 * The Scholarships and Grants page, the review board, the review panel and the award panel
 * (ADR-0204 `0204-scholarships-outbound-grants-module.md`). Thin by design (plan Section 9.9): it
 * returns plain shapes and leaves the work to `ScholarshipReviews` and `ScholarshipAwards`, in
 * user mode. A refusal written for the person, or a save's own message, is shown as it is;
 * anything else is logged and shown as one message.
 */
public with sharing class ScholarshipsController {
	private static final String CONTEXT = 'ScholarshipsController';

	/** One line of a list on the Scholarships and Grants page. */
	public class Row {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String detail;
		@AuraEnabled
		public Date due;
		@AuraEnabled
		public Integer count;
	}

	public class Home {
		@AuraEnabled
		public List<Row> reviews = new List<Row>();
		@AuraEnabled
		public List<Row> cycles = new List<Row>();
		@AuraEnabled
		public List<ScholarshipAwards.Payment> due = new List<ScholarshipAwards.Payment>();
		@AuraEnabled
		public Boolean canManage = false;
	}

	public class Board {
		@AuraEnabled
		public List<ScholarshipReviews.BoardRow> rows;
		@AuraEnabled
		public Boolean canManage = false;
		@AuraEnabled
		public Boolean blind = false;
		@AuraEnabled
		public Decimal budget;
		@AuraEnabled
		public Decimal remaining;
		@AuraEnabled
		public String formLink;
	}

	public class Review {
		@AuraEnabled
		public List<ScholarshipReviews.Criterion> criteria;
		@AuraEnabled
		public MyReview mine;
		@AuraEnabled
		public Boolean blind = false;
		@AuraEnabled
		public Boolean open = false;
	}

	/** The running user's own review, by unprefixed names (works namespaced or not). */
	public class MyReview {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String scores;
		@AuraEnabled
		public Decimal score;
		@AuraEnabled
		public String comments;
		@AuraEnabled
		public String recusalReason;

		public MyReview(Application_Review__c review) {
			id = review.Id;
			status = review.Status__c;
			scores = review.Scores__c;
			score = review.Score__c;
			comments = review.Comments__c;
			recusalReason = review.Recusal_Reason__c;
		}
	}

	/** One requirement on an award, by unprefixed names. */
	public class Requirement {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String type;
		@AuraEnabled
		public Date dueDate;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String formLink;
		@AuraEnabled
		public String blocks;

		public Requirement(Award_Requirement__c requirement) {
			id = requirement.Id;
			name = requirement.Name;
			type = requirement.Type__c;
			dueDate = requirement.Due_Date__c;
			status = requirement.Status__c;
			formLink = requirement.Form_Link__c;
			blocks = requirement.Disbursement__r?.Name;
		}
	}

	public class AwardPanel {
		@AuraEnabled
		public List<ScholarshipAwards.Payment> payments;
		@AuraEnabled
		public List<Requirement> requirements = new List<Requirement>();
		@AuraEnabled
		public Boolean canManage = false;
	}

	@AuraEnabled
	public static Home getHome() {
		try {
			Home home = new Home();
			home.canManage = Scholarships.canManage();
			for (Application_Review__c review : [
				SELECT
					Application__c,
					Application__r.Name,
					Application__r.Cycle__r.Name,
					Application__r.Cycle__r.Close_Date__c
				FROM Application_Review__c
				WHERE
					Reviewer__c = :UserInfo.getUserId()
					AND Status__c = :ScholarshipReviews.ASSIGNED
				WITH USER_MODE
				ORDER BY CreatedDate
				LIMIT 200
			]) {
				home.reviews.add(
					row(
						review.Application__c,
						review.Application__r.Name,
						review.Application__r.Cycle__r.Name,
						null,
						null
					)
				);
			}
			for (Award_Cycle__c cycle : [
				SELECT Id, Name, Program__r.Name, Close_Date__c, Applications__c
				FROM Award_Cycle__c
				WHERE Status__c IN ('Open', 'Reviewing')
				WITH USER_MODE
				ORDER BY Close_Date__c NULLS LAST
				LIMIT 100
			]) {
				home.cycles.add(
					row(
						cycle.Id,
						cycle.Name,
						cycle.Program__r.Name,
						cycle.Close_Date__c,
						cycle.Applications__c?.intValue()
					)
				);
			}
			home.due = ScholarshipAwards.due(30);
			return home;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Board getBoard(Id cycleId) {
		try {
			Award_Cycle__c cycle = [
				SELECT Blind_Review__c, Budget__c, Remaining_Budget__c, Application_Form_Key__c
				FROM Award_Cycle__c
				WHERE Id = :cycleId
				WITH USER_MODE
			];
			Board board = new Board();
			board.canManage = Scholarships.canManage();
			board.blind = cycle.Blind_Review__c;
			board.budget = cycle.Budget__c;
			board.remaining = cycle.Remaining_Budget__c;
			board.rows = ScholarshipReviews.board(cycleId, board.blind && !board.canManage);
			if (String.isNotBlank(cycle.Application_Form_Key__c)) {
				board.formLink = FormCatalogExtensions.publicLink(
					Id.valueOf(cycle.Application_Form_Key__c.trim()),
					cycleId
				);
			}
			return board;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Integer assignReviewers(Id cycleId) {
		try {
			return ScholarshipReviews.assign(cycleId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id decide(Id applicationId, Boolean award, Decimal amount) {
		try {
			return ScholarshipAwards.decide(applicationId, award, amount);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Review getReview(Id applicationId) {
		try {
			Award_Application__c application = [
				SELECT Status__c, Cycle__r.Rubric__c, Cycle__r.Blind_Review__c
				FROM Award_Application__c
				WHERE Id = :applicationId
				WITH USER_MODE
			];
			Review review = new Review();
			review.criteria = ScholarshipReviews.rubric(application.Cycle__r.Rubric__c);
			Application_Review__c mine = ScholarshipReviews.own(applicationId);
			review.mine = mine == null ? null : new MyReview(mine);
			review.blind = application.Cycle__r.Blind_Review__c && !Scholarships.canManage();
			review.open = ScholarshipReviews.REVIEWABLE.contains(application.Status__c);
			return review;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	/** `action` is save, submit or recuse; `scoresJson` maps each criterion key to its score. */
	@AuraEnabled
	public static MyReview saveReview(
		Id applicationId,
		String scoresJson,
		String comments,
		String action,
		String reason
	) {
		try {
			Map<String, Object> scores = String.isBlank(scoresJson)
				? new Map<String, Object>()
				: (Map<String, Object>) JSON.deserializeUntyped(scoresJson);
			return new MyReview(
				ScholarshipReviews.saveOwn(applicationId, scores, comments, action, reason)
			);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static AwardPanel getAward(Id awardId) {
		try {
			AwardPanel panel = new AwardPanel();
			panel.payments = ScholarshipAwards.payments(awardId);
			for (Award_Requirement__c requirement : [
				SELECT Id, Name, Type__c, Due_Date__c, Status__c, Form_Link__c, Disbursement__r.Name
				FROM Award_Requirement__c
				WHERE Award__c = :awardId
				WITH USER_MODE
				ORDER BY Due_Date__c NULLS LAST, Name
			]) {
				panel.requirements.add(new Requirement(requirement));
			}
			panel.canManage = Scholarships.canManage();
			return panel;
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id makeLetter(Id awardId) {
		try {
			return ScholarshipAwards.makeLetter(awardId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void respond(Id awardId, Boolean accepted) {
		try {
			ScholarshipAwards.respond(awardId, accepted);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Integer buildSchedule(
		Id awardId,
		Integer count,
		Date firstDate,
		Integer monthsApart
	) {
		try {
			return ScholarshipAwards.buildSchedule(awardId, count, firstDate, monthsApart);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void markPaid(Id paymentId, Date paidOn, String method, String reference) {
		try {
			ScholarshipAwards.markPaid(paymentId, paidOn, method, reference);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static void setRequirement(Id requirementId, String status) {
		try {
			ScholarshipAwards.setRequirement(requirementId, status);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static Id startRenewal(Id awardId) {
		try {
			return ScholarshipAwards.startRenewal(awardId);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	@AuraEnabled
	public static List<ScholarshipAwards.Payment> exportDisbursements(Date fromDate, Date toDate) {
		try {
			return ScholarshipAwards.export(fromDate, toDate);
		} catch (Exception e) {
			throw failure(e);
		}
	}

	private static Row row(Id id, String name, String detail, Date due, Integer count) {
		Row line = new Row();
		line.id = id;
		line.name = name;
		line.detail = detail;
		line.due = due;
		line.count = count;
		return line;
	}

	/** A refusal or a save's own message as it is; anything else logged, then one message. */
	private static AuraHandledException failure(Exception e) {
		if (!(e instanceof Scholarships.ScholarshipException) && !(e instanceof DmlException)) {
			ErrorLogger.log(e, CONTEXT);
		}
		return UserErrors.wrapShowingDml(
			e,
			BarnHelp.text('Scholarships', 'Scholarships_Error_Generic')
		);
	}
}
