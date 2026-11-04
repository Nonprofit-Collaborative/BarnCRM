/**
 * The Service Plan panel's server side (P-10; canonical model Sections 29ZA3 and 29ZA4). Thin:
 * each method parses the panel's JSON, asks `ServicePlanService`, and returns the whole plan again
 * as plain JSON, so the panel redraws from one shape (plan 9.9). A refused save comes back in its
 * own words; anything unexpected is recorded in the Error Log first (plan Section 7.2).
 */
public with sharing class ServicePlanController {
	private static final String CONTEXT = 'Service plan panel';

	/** The plan on this enrollment. Not cacheable: it changes with every save. */
	@AuraEnabled
	public static Map<String, Object> getPlan(Id enrollmentId) {
		try {
			return ServicePlanService.read(enrollmentId);
		} catch (Exception e) {
			throw handled(e, enrollmentId);
		}
	}

	/** The Logic Models outcomes a goal here can work toward; empty without Logic Models. */
	@AuraEnabled
	public static List<Map<String, String>> getOutcomes(Id enrollmentId) {
		try {
			return ServicePlanService.outcomes(enrollmentId);
		} catch (Exception e) {
			throw handled(e, enrollmentId);
		}
	}

	/** Adds or changes a goal (see `ServicePlanService.saveGoal`), then returns the plan. */
	@AuraEnabled
	public static Map<String, Object> saveGoal(String goalJson) {
		try {
			return ServicePlanService.read(ServicePlanService.saveGoal(parse(goalJson)));
		} catch (Exception e) {
			throw handled(e, null);
		}
	}

	/** Adds or changes a step (see `ServicePlanService.saveStep`), then returns the plan. */
	@AuraEnabled
	public static Map<String, Object> saveStep(String stepJson) {
		try {
			return ServicePlanService.read(ServicePlanService.saveStep(parse(stepJson)));
		} catch (Exception e) {
			throw handled(e, null);
		}
	}

	/** Records a review today and the next review date, then returns the plan. */
	@AuraEnabled
	public static Map<String, Object> markReviewed(Id goalId, Date nextReviewDate) {
		try {
			return ServicePlanService.read(ServicePlanService.markReviewed(goalId, nextReviewDate));
		} catch (Exception e) {
			throw handled(e, goalId);
		}
	}

	private static Map<String, Object> parse(String payload) {
		Object value = String.isBlank(payload) ? null : JSON.deserializeUntyped(payload);
		if (!(value instanceof Map<String, Object>)) {
			throw new ServicePlanService.PlanException(
				BarnHelp.text('Programs', 'Programs_Fail_Plan')
			);
		}
		return (Map<String, Object>) value;
	}

	/** The message the panel shows: a refused save's own words, or the generic one. */
	@TestVisible
	private static AuraHandledException handled(Exception e, Id recordId) {
		String message = BarnHelp.text('Programs', 'Programs_Fail_Plan');
		if (e instanceof AuraHandledException) {
			return (AuraHandledException) e;
		} else if (e instanceof DmlException) {
			message = ((DmlException) e).getDmlMessage(0);
		} else if (e instanceof ServicePlanService.PlanException) {
			message = e.getMessage();
		} else if (e instanceof QueryException || e instanceof System.NoAccessException) {
			message = Label.Programs_Plan_NotFound;
		} else {
			ErrorLogger.log(e, CONTEXT, recordId);
		}
		return UserErrors.message(message);
	}
}
