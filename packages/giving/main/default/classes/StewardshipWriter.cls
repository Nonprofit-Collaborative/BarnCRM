/**
 * The only place stewardship plans and their tasks are written.
 *
 * DOCUMENTED EXCEPTION to the user-mode rule (plan Section 4.13), on the same ground ADR-0021
 * states for the rest of the module's package-owned data. A plan is started as a consequence of a
 * gift somebody entered, not as a record they chose to create, so requiring create access on
 * `Stewardship_Plan__c` from everyone who enters gifts would mean the follow-up silently stops for
 * the users least likely to notice. Nothing is read back to the caller and no record data leaves
 * this class.
 *
 * The tasks are the exception to the exception: a task is somebody's own work, and it is inserted
 * in system mode only so that a plan started by a gift entry clerk can be assigned to the donor's
 * owner, who may be somebody else entirely.
 *
 * It never throws (rule R-E2). A failure to start a plan is logged and swallowed, because the
 * caller is usually inside the save of a gift (R-SP9).
 */
public without sharing class StewardshipWriter {
	private static final String CONTEXT = 'Stewardship plans';

	/**
	 * Inserts the plans and then the tasks their templates call for. Two statements whatever the
	 * number of plans, because the tasks cannot be built until the plans have ids.
	 *
	 * The two lists are positional: `templates[i]` is the template `plans[i]` was made from. They
	 * are kept apart rather than looked up again so that starting two hundred plans costs no
	 * further queries.
	 */
	public static void startPlans(
		List<Stewardship_Plan__c> plans,
		List<Stewardship_Plan_Template__c> templates
	) {
		if (plans == null || plans.isEmpty() || templates == null) {
			return;
		}
		if (plans.size() != templates.size()) {
			ErrorLogger.logMessage(
				BarnHelp.text('Giving', 'Giving_Stewardship_ErrorStartFailed'),
				CONTEXT,
				ErrorLogger.SEVERITY_ERROR
			);
			return;
		}
		List<Database.SaveResult> saved;
		try {
			saved = Database.insert(plans, false, AccessLevel.SYSTEM_MODE);
		} catch (Exception cannotStart) {
			ErrorLogger.log(cannotStart, CONTEXT);
			return;
		}

		Map<Id, Id> owners = ownersFor(plans, saved);
		List<Task> tasks = new List<Task>();
		List<Exception> refused = new List<Exception>();
		for (Integer i = 0; i < saved.size(); i++) {
			if (!saved[i].isSuccess()) {
				continue;
			}
			try {
				tasks.addAll(
					StewardshipService.tasksFor(
						templates[i],
						plans[i],
						owners.get(donorOf(plans[i]))
					)
				);
			} catch (Exception cannotBuild) {
				refused.add(cannotBuild);
			}
		}
		if (!refused.isEmpty()) {
			ErrorLogger.log(refused, CONTEXT);
		}
		if (tasks.isEmpty()) {
			return;
		}
		try {
			Database.insert(tasks, false, AccessLevel.SYSTEM_MODE);
		} catch (Exception cannotAssign) {
			ErrorLogger.log(cannotAssign, CONTEXT);
		}
	}

	/**
	 * Who each started plan's donor belongs to, in one query for the whole list. A donor the
	 * package cannot read is simply absent from the map, and the service falls back to the person
	 * who started the plan rather than leaving a task unowned (R-SP4).
	 */
	private static Map<Id, Id> ownersFor(
		List<Stewardship_Plan__c> plans,
		List<Database.SaveResult> saved
	) {
		Set<Id> contactIds = new Set<Id>();
		Set<Id> accountIds = new Set<Id>();
		for (Integer i = 0; i < saved.size(); i++) {
			if (!saved[i].isSuccess()) {
				continue;
			}
			if (plans[i].Contact__c != null) {
				contactIds.add(plans[i].Contact__c);
			} else if (plans[i].Account__c != null) {
				accountIds.add(plans[i].Account__c);
			}
		}
		if (contactIds.isEmpty() && accountIds.isEmpty()) {
			return new Map<Id, Id>();
		}
		return StewardshipSelector.selectOwners(contactIds, accountIds);
	}

	private static Id donorOf(Stewardship_Plan__c plan) {
		return plan.Contact__c == null ? plan.Account__c : plan.Contact__c;
	}
}
