/**
 * Starts stewardship plans and lays out the tasks they call for (canonical model Sections 25I to
 * 25K, plan feature G-15).
 *
 * The shape of the work is deliberately narrow. Starting a plan creates one `Stewardship_Plan__c`
 * and one Task per step, once, at the moment it starts (R-SP7). Nothing here closes a plan, edits
 * a task, or reaches back into a plan already running: a task in somebody's list is their work,
 * and moving it because an administrator edited a template would move a week somebody had planned.
 *
 * Nothing here throws at a trigger. A plan that could not start is a follow-up that did not
 * happen; a gift that could not save is money the organization lost track of (R-SP9).
 */
public with sharing class StewardshipService {
	@TestVisible
	private static final String CONTEXT = 'Stewardship plans';

	public static final String STATUS_RUNNING = 'Running';
	public static final String STATUS_COMPLETE = 'Complete';
	public static final String STATUS_CANCELLED = 'Cancelled';

	public static final String EVENT_MANUAL = 'Manual';
	public static final String EVENT_FIRST_GIFT = 'First gift';
	public static final String EVENT_GIFT_RECEIVED = 'Gift received';
	public static final String EVENT_COMMITMENT_STARTED = 'Commitment started';

	/** The commitment status that means the commitment is running (R-SP3a). */
	public static final String COMMITMENT_ACTIVE = 'Active';

	public static final String ASSIGN_RECORD_OWNER = 'Record owner';
	public static final String ASSIGN_PLAN_STARTER = 'Plan starter';
	public static final String ASSIGN_SPECIFIC_USER = 'Specific user';

	/**
	 * The gift statuses that count toward a donor's giving, matching the packaged rollups
	 * (canonical model Section 26, ADR-0022). Held here so the first gift test and the totals a
	 * donor sees agree about what a gift is.
	 */
	public static final Set<String> COUNTABLE_STATUSES = new Set<String>{
		'Received',
		'Refunded',
		'Written off'
	};

	/**
	 * Starts every plan the given gifts call for.
	 *
	 * Bulk safe by construction: two selector calls whatever the size of the list, one insert of
	 * every plan, one insert of every task. Called from the trigger handler, never directly, so
	 * the automation stays switchable (R-SP1).
	 */
	public static void startForGifts(List<Gift__c> gifts) {
		if (gifts == null || gifts.isEmpty()) {
			return;
		}
		List<Stewardship_Plan_Template__c> templates = StewardshipSelector.selectActiveTemplatesForEvents(
			new Set<String>{ EVENT_FIRST_GIFT, EVENT_GIFT_RECEIVED }
		);
		if (templates.isEmpty()) {
			return;
		}

		Set<Id> donorIds = new Set<Id>();
		Set<Id> contactIds = new Set<Id>();
		Set<Id> accountIds = new Set<Id>();
		Set<Id> giftIds = new Set<Id>();
		for (Gift__c gift : gifts) {
			if (!COUNTABLE_STATUSES.contains(gift.Status__c)) {
				continue;
			}
			giftIds.add(gift.Id);
			if (gift.Donor_Contact__c != null) {
				contactIds.add(gift.Donor_Contact__c);
				donorIds.add(gift.Donor_Contact__c);
			} else if (gift.Donor_Account__c != null) {
				accountIds.add(gift.Donor_Account__c);
				donorIds.add(gift.Donor_Account__c);
			}
		}
		if (donorIds.isEmpty()) {
			return;
		}

		Map<String, Integer> priorGifts = needsFirstGiftTest(templates)
			? StewardshipSelector.countCountableGifts(donorIds, giftIds)
			: new Map<String, Integer>();
		Set<String> alreadyRunning = runningKeys(
			StewardshipSelector.selectRunningPlansFor(contactIds, accountIds)
		);

		List<Stewardship_Plan__c> toStart = new List<Stewardship_Plan__c>();
		List<Stewardship_Plan_Template__c> usedTemplates = new List<Stewardship_Plan_Template__c>();
		for (Gift__c gift : gifts) {
			if (!COUNTABLE_STATUSES.contains(gift.Status__c)) {
				continue;
			}
			Id donorId = gift.Donor_Contact__c == null
				? gift.Donor_Account__c
				: gift.Donor_Contact__c;
			if (donorId == null) {
				continue;
			}
			Boolean isFirstGift = firstGift(priorGifts, donorId);
			for (Stewardship_Plan_Template__c template : templates) {
				if (!applies(template, gift, isFirstGift)) {
					continue;
				}
				String key = runningKey(template.Id, donorId);
				if (alreadyRunning.contains(key)) {
					continue;
				}
				alreadyRunning.add(key);
				toStart.add(
					plan(template.Id, gift.Donor_Contact__c, gift.Donor_Account__c, gift.Id)
				);
				usedTemplates.add(template);
			}
		}
		StewardshipWriter.startPlans(toStart, usedTemplates);
	}

	/**
	 * Starts every plan the given commitments call for.
	 *
	 * The caller decides which commitments have started (R-SP3a); this only has to lay the plans
	 * out. Bulk safe the same way the gift path is: one selector call for the templates, one for
	 * the plans already running, one insert of plans and one insert of tasks, whatever the size
	 * of the list.
	 *
	 * Minimum Amount is not read here. It is a condition on a gift, and the Amount Only For Gift
	 * Events rule refuses it on a commitment template at save, so there is nothing to apply.
	 */
	public static void startForCommitments(List<Commitment__c> commitments) {
		if (commitments == null || commitments.isEmpty()) {
			return;
		}
		List<Stewardship_Plan_Template__c> templates = StewardshipSelector.selectActiveTemplatesForEvents(
			new Set<String>{ EVENT_COMMITMENT_STARTED }
		);
		if (templates.isEmpty()) {
			return;
		}

		Set<Id> contactIds = new Set<Id>();
		Set<Id> accountIds = new Set<Id>();
		for (Commitment__c commitment : commitments) {
			if (commitment.Donor_Contact__c != null) {
				contactIds.add(commitment.Donor_Contact__c);
			} else if (commitment.Donor_Account__c != null) {
				accountIds.add(commitment.Donor_Account__c);
			}
		}
		if (contactIds.isEmpty() && accountIds.isEmpty()) {
			return;
		}
		Set<String> alreadyRunning = runningKeys(
			StewardshipSelector.selectRunningPlansFor(contactIds, accountIds)
		);

		List<Stewardship_Plan__c> toStart = new List<Stewardship_Plan__c>();
		List<Stewardship_Plan_Template__c> usedTemplates = new List<Stewardship_Plan_Template__c>();
		for (Commitment__c commitment : commitments) {
			Id donorId = commitment.Donor_Contact__c == null
				? commitment.Donor_Account__c
				: commitment.Donor_Contact__c;
			if (donorId == null) {
				continue;
			}
			for (Stewardship_Plan_Template__c template : templates) {
				String key = runningKey(template.Id, donorId);
				if (alreadyRunning.contains(key)) {
					continue;
				}
				alreadyRunning.add(key);
				Stewardship_Plan__c started = plan(
					template.Id,
					commitment.Donor_Contact__c,
					commitment.Donor_Account__c,
					null
				);
				started.Commitment__c = commitment.Id;
				toStart.add(started);
				usedTemplates.add(template);
			}
		}
		StewardshipWriter.startPlans(toStart, usedTemplates);
	}

	/**
	 * Starts one plan on one donor because somebody asked for it. Returns the plan, or throws a
	 * `StewardshipException` with a readable reason: a person who pressed a button is owed an
	 * answer, which is why this one throws where the trigger path logs (R-SP9).
	 */
	public static Stewardship_Plan__c start(Id templateId, Id contactId, Id accountId) {
		if (templateId == null) {
			throw new StewardshipException(
				BarnHelp.text('Giving', 'Giving_Stewardship_ErrorNoTemplate')
			);
		}
		if ((contactId == null) == (accountId == null)) {
			throw new StewardshipException(
				BarnHelp.text('Giving', 'Giving_Stewardship_ErrorOneDonor')
			);
		}
		List<Stewardship_Plan_Template__c> found = StewardshipSelector.selectTemplateById(
			templateId
		);
		if (found.isEmpty() || found[0].Active__c != true) {
			throw new StewardshipException(
				BarnHelp.text('Giving', 'Giving_Stewardship_ErrorNoTemplate')
			);
		}
		Id donorId = contactId == null ? accountId : contactId;
		Set<String> running = runningKeys(
			StewardshipSelector.selectRunningPlansFor(
				contactId == null ? new Set<Id>() : new Set<Id>{ contactId },
				accountId == null ? new Set<Id>() : new Set<Id>{ accountId }
			)
		);
		if (running.contains(runningKey(templateId, donorId))) {
			throw new StewardshipException(
				BarnHelp.text('Giving', 'Giving_Stewardship_ErrorAlreadyRunning')
			);
		}
		Stewardship_Plan__c started = plan(templateId, contactId, accountId, null);
		StewardshipWriter.startPlans(
			new List<Stewardship_Plan__c>{ started },
			new List<Stewardship_Plan_Template__c>{ found[0] }
		);
		return started;
	}

	/** The tasks one template's steps call for, dated from the day the plan starts (R-SP5). */
	public static List<Task> tasksFor(
		Stewardship_Plan_Template__c template,
		Stewardship_Plan__c startedPlan,
		Id ownerId
	) {
		List<Task> tasks = new List<Task>();
		if (template == null || template.Steps__r == null || startedPlan == null) {
			return tasks;
		}
		Date startedOn = startedPlan.Started_Date__c == null
			? System.today()
			: startedPlan.Started_Date__c;
		for (Stewardship_Plan_Step__c step : template.Steps__r) {
			Integer offset = step.Days_After_Start__c == null
				? 0
				: Integer.valueOf(step.Days_After_Start__c);
			tasks.add(
				new Task(
					Subject = step.Subject__c,
					Description = step.Comments__c,
					ActivityDate = startedOn.addDays(Math.max(offset, 0)),
					Priority = String.isBlank(step.Priority__c) ? 'Normal' : step.Priority__c,
					Status = 'Not Started',
					OwnerId = assignee(step, ownerId),
					WhatId = startedPlan.Id
				)
			);
		}
		return tasks;
	}

	/**
	 * Who a step's task goes to. A step naming nobody, or naming somebody the package cannot use,
	 * falls back to the person who started the plan rather than to nobody at all (R-SP4).
	 */
	private static Id assignee(Stewardship_Plan_Step__c step, Id ownerId) {
		Id fallback = ownerId == null ? UserInfo.getUserId() : ownerId;
		if (ASSIGN_SPECIFIC_USER.equals(step.Assign_To__c) && step.Assigned_User__c != null) {
			return step.Assigned_User__c;
		}
		if (ASSIGN_PLAN_STARTER.equals(step.Assign_To__c)) {
			return UserInfo.getUserId();
		}
		return fallback;
	}

	/** Whether a template's conditions are met by this gift. */
	private static Boolean applies(
		Stewardship_Plan_Template__c template,
		Gift__c gift,
		Boolean isFirstGift
	) {
		if (EVENT_FIRST_GIFT.equals(template.Trigger_Event__c) && isFirstGift != true) {
			return false;
		}
		if (
			template.Minimum_Amount__c != null &&
			(gift.Amount__c == null ||
			gift.Amount__c < template.Minimum_Amount__c)
		) {
			return false;
		}
		return true;
	}

	private static Boolean needsFirstGiftTest(List<Stewardship_Plan_Template__c> templates) {
		for (Stewardship_Plan_Template__c template : templates) {
			if (EVENT_FIRST_GIFT.equals(template.Trigger_Event__c)) {
				return true;
			}
		}
		return false;
	}

	private static Boolean firstGift(Map<String, Integer> priorGifts, Id donorId) {
		Integer prior = priorGifts.get(String.valueOf(donorId));
		return prior == null || prior == 0;
	}

	private static Stewardship_Plan__c plan(Id templateId, Id contactId, Id accountId, Id giftId) {
		return new Stewardship_Plan__c(
			Stewardship_Plan_Template__c = templateId,
			Contact__c = contactId,
			Account__c = accountId,
			Gift__c = giftId,
			Status__c = STATUS_RUNNING,
			Started_Date__c = System.today()
		);
	}

	private static Set<String> runningKeys(List<Stewardship_Plan__c> plans) {
		Set<String> keys = new Set<String>();
		for (Stewardship_Plan__c running : plans) {
			Id donorId = running.Contact__c == null ? running.Account__c : running.Contact__c;
			keys.add(runningKey(running.Stewardship_Plan_Template__c, donorId));
		}
		return keys;
	}

	private static String runningKey(Id templateId, Id donorId) {
		return String.valueOf(templateId) + '|' + String.valueOf(donorId);
	}

	/** Raised only on the path a person is waiting on. The trigger path logs instead. */
	public class StewardshipException extends Exception {
	}
}
