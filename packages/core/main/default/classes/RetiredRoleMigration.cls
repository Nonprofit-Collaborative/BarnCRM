/**
 * Carries the holders of a retired BarnCRM role over to the role that replaces it (ADR-0194,
 * simpler permission sets, D1): every holder of Coordinator (`Volunteer_Coordinator`) is given
 * Team Member (`Program_Staff`), which grants exactly what Coordinator granted in Core.
 *
 * This release only adds: nobody loses the retired role here, so nobody is ever without access.
 * The next release takes the retired role away once the successor is held.
 *
 * `carryOver` runs in the tab access job (`TabAccessService.Job`), which every install, upgrade,
 * source deploy and the hourly check queue, and which writes only setup objects. It gives the
 * successor to active holders only. An inactive holder is never tried, because Salesforce may
 * refuse to assign to an inactive user; `logInactiveHolders`, which the post-install runs, names
 * each one in the Error Log instead, once per install or upgrade rather than every hour. They
 * keep the retired role, so if they are reactivated during this release the hourly check gives
 * them the successor. Neither method throws: an install must never fail over this step.
 */
public with sharing class RetiredRoleMigration {
	private static final String CONTEXT = 'RetiredRoleMigration';
	private static final String READY = 'Updated';

	/**
	 * Gives each active holder of a retired role its successor, up to `budget` assignments, in
	 * system mode (the package keeping its own roles in step, as the tab sync does). A refused
	 * assignment is logged as a Warning naming the person, and the next run tries again. Does
	 * nothing while the successor role is still being calculated. Never throws.
	 */
	public static void carryOver(Integer budget) {
		try {
			List<Holder> tried = new List<Holder>();
			List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
			for (Holder holder : holdersWithoutSuccessor(packagedRoles())) {
				if (toInsert.size() >= budget) {
					break;
				}
				if (holder.active && READY.equalsIgnoreCase(holder.successor.Status)) {
					tried.add(holder);
					toInsert.add(
						new PermissionSetAssignment(
							AssigneeId = holder.userId,
							PermissionSetGroupId = holder.successor.Id
						)
					);
				}
			}
			if (!toInsert.isEmpty()) {
				List<Database.SaveResult> results = Database.insert(
					toInsert,
					false,
					AccessLevel.SYSTEM_MODE
				);
				ErrorLogger.logMessages(
					refusalMessages(tried, results),
					CONTEXT,
					ErrorLogger.SEVERITY_WARNING
				);
			}
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
		}
	}

	/**
	 * Names each inactive holder of a retired role who does not hold its successor, as a Warning
	 * in the Error Log. Reads only, so the post-install calls it directly. Never throws.
	 *
	 * @return the messages logged
	 */
	public static List<String> logInactiveHolders() {
		List<String> messages = new List<String>();
		try {
			for (Holder holder : holdersWithoutSuccessor(packagedRoles())) {
				if (holder.active) {
					continue;
				}
				messages.add(
					String.format(
						BarnHelp.text('Core', 'Core_Access_RetiredRoleInactive'),
						new List<Object>{
							holder.name,
							holder.retired.MasterLabel,
							holder.successor.MasterLabel
						}
					)
				);
			}
			ErrorLogger.logMessages(messages, CONTEXT, ErrorLogger.SEVERITY_WARNING);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
		}
		return messages;
	}

	/**
	 * One message per refused assignment, naming the person, the retired role and its successor,
	 * with what Salesforce said. A duplicate is not a refusal: another job gave the role first.
	 */
	@TestVisible
	private static List<String> refusalMessages(
		List<Holder> tried,
		List<Database.SaveResult> results
	) {
		List<String> messages = new List<String>();
		for (Integer i = 0; i < results.size(); i++) {
			Database.SaveResult result = results[i];
			if (result.isSuccess() || isDuplicate(result.getErrors())) {
				continue;
			}
			List<String> said = new List<String>();
			for (Database.Error error : result.getErrors()) {
				said.add(error.getMessage());
			}
			Holder holder = tried[i];
			messages.add(
				String.format(
					BarnHelp.text('Core', 'Core_Access_RetiredRoleRefused'),
					new List<Object>{
						holder.name,
						holder.retired.MasterLabel,
						holder.successor.MasterLabel,
						String.join(said, ' ')
					}
				)
			);
		}
		return messages;
	}

	private static Boolean isDuplicate(List<Database.Error> errors) {
		for (Database.Error error : errors) {
			if (error.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
				return false;
			}
		}
		return !errors.isEmpty();
	}

	/** The retired roles and their successors this org has, in this product's namespace. */
	private static Map<String, PermissionSetGroup> packagedRoles() {
		Set<String> names = new Set<String>(AccessService.RETIRED_ROLES.keySet());
		names.addAll(AccessService.RETIRED_ROLES.values());
		String prefix = NamespaceUtil.prefix().removeEnd('__');
		String namespace = String.isBlank(prefix) ? null : prefix;
		Map<String, PermissionSetGroup> roles = new Map<String, PermissionSetGroup>();
		for (PermissionSetGroup role : [
			SELECT Id, DeveloperName, MasterLabel, Status
			FROM PermissionSetGroup
			WHERE DeveloperName IN :names AND NamespacePrefix = :namespace
			WITH SYSTEM_MODE
		]) {
			roles.put(role.DeveloperName, role);
		}
		return roles;
	}

	/** Each holder of a retired role who does not hold its successor yet. */
	private static List<Holder> holdersWithoutSuccessor(Map<String, PermissionSetGroup> roles) {
		Map<Id, String> roleNames = new Map<Id, String>();
		for (PermissionSetGroup role : roles.values()) {
			roleNames.put(role.Id, role.DeveloperName);
		}
		Map<String, Set<Id>> holdersByRole = new Map<String, Set<Id>>();
		Map<Id, User> people = new Map<Id, User>();
		for (PermissionSetAssignment row : [
			SELECT AssigneeId, Assignee.Name, Assignee.IsActive, PermissionSetGroupId
			FROM PermissionSetAssignment
			WHERE PermissionSetGroupId IN :roleNames.keySet()
			WITH SYSTEM_MODE
		]) {
			String role = roleNames.get(row.PermissionSetGroupId);
			if (!holdersByRole.containsKey(role)) {
				holdersByRole.put(role, new Set<Id>());
			}
			holdersByRole.get(role).add(row.AssigneeId);
			people.put(row.AssigneeId, row.Assignee);
		}
		List<Holder> holders = new List<Holder>();
		for (String retired : AccessService.RETIRED_ROLES.keySet()) {
			String successor = AccessService.RETIRED_ROLES.get(retired);
			if (!roles.containsKey(retired) || !roles.containsKey(successor)) {
				continue;
			}
			Set<Id> already = holdersByRole.containsKey(successor)
				? holdersByRole.get(successor)
				: new Set<Id>();
			Set<Id> retiredHolders = holdersByRole.containsKey(retired)
				? holdersByRole.get(retired)
				: new Set<Id>();
			for (Id userId : retiredHolders) {
				if (!already.contains(userId)) {
					holders.add(
						new Holder(
							userId,
							people.get(userId),
							roles.get(retired),
							roles.get(successor)
						)
					);
				}
			}
		}
		return holders;
	}

	/** One person holding a retired role and not its successor. */
	@TestVisible
	private class Holder {
		final Id userId;
		@TestVisible
		final String name;
		final Boolean active;
		final PermissionSetGroup retired;
		final PermissionSetGroup successor;

		@TestVisible
		Holder(Id userId, User person, PermissionSetGroup retired, PermissionSetGroup successor) {
			this.userId = userId;
			this.name = person?.Name == null ? String.valueOf(userId) : person.Name;
			this.active = person != null && person.IsActive == true;
			this.retired = retired;
			this.successor = successor;
		}
	}
}
