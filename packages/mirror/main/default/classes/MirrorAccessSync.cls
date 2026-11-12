/**
 * Carries the holders of Mirror's retired permission sets over to the sets that replace them
 * (ADR-0194, simpler permission sets, D4): every holder of Campaign Sync, Opportunity Mirror or
 * Gift Transaction Mirror gets Salesforce Records Sync, and every holder of Inbound Gift API or
 * Record Inbound Gift Action gets Inbound Gifts.
 *
 * This release only adds: nobody loses a retired set here, so nobody is ever without access. The
 * next release takes the retired sets away once the successor is held.
 *
 * The giving is Core's module access sync (`ModuleAccessSyncBase`): queued, so the setup write
 * never meets the install's record writes; active users only, so Salesforce is never asked to
 * assign to an inactive one; each refusal logged as a Warning naming the person and the set; run
 * at install and upgrade (`MirrorPostInstall`), at Turn on and with the hourly access check.
 * Core finds it by its name, the module key followed by `AccessSync` (`ModuleAccessSyncs`), so the
 * class keeps this name. `logInactiveHolders` names each inactive holder once per install or
 * upgrade instead. It does nothing while the module is turned off.
 */
@NamespaceAccessible
public with sharing class MirrorAccessSync extends ModuleAccessSyncBase {
	/** The module key in the Module Manager. */
	public static final String MODULE_NAME = 'Mirror';
	private static final String CONTEXT = 'MirrorAccessSync';

	/** Each new set, and the retired sets whose holders get it. */
	@TestVisible
	private static final Map<String, List<String>> BY_SET = new Map<String, List<String>>{
		'Salesforce_Records_Sync' => new List<String>{
			'Campaign_Sync',
			'Opportunity_Mirror',
			'Gift_Transaction_Mirror'
		},
		'Inbound_Gifts' => new List<String>{ 'Inbound_Gift_API', 'Record_Inbound_Gift_Action' }
	};

	/** Assignments one run gives per set: two sets, well inside the 10,000 DML rows. */
	private static final Integer ROWS_PER_SET = 4000;

	@NamespaceAccessible
	public MirrorAccessSync() {
		// Built by name from Core (ModuleAccessSyncs), so it needs a public constructor.
	}

	/** One slice now. Returns true when more is left. */
	public static Boolean syncOnce() {
		return new MirrorAccessSync().sync();
	}

	public override String moduleName() {
		return MODULE_NAME;
	}

	public override String logContext() {
		return CONTEXT;
	}

	public override Map<String, List<String>> setsByPermissionSet() {
		return BY_SET;
	}

	public override Map<String, List<String>> setsByRole() {
		return new Map<String, List<String>>();
	}

	public override Integer sliceSize() {
		return ROWS_PER_SET;
	}

	/**
	 * Names each inactive holder of a retired set who does not hold its successor, as a Warning
	 * in the Error Log. Reads only, so the post-install calls it directly. Never throws.
	 *
	 * @return the messages logged
	 */
	public static List<String> logInactiveHolders() {
		List<String> messages = new List<String>();
		try {
			Set<String> names = new Set<String>(BY_SET.keySet());
			for (List<String> retired : BY_SET.values()) {
				names.addAll(retired);
			}
			String prefix = NamespaceUtil.prefix().removeEnd('__');
			String namespace = String.isBlank(prefix) ? null : prefix;
			Map<String, String> labels = new Map<String, String>();
			Map<Id, Set<String>> held = new Map<Id, Set<String>>();
			Map<Id, User> people = new Map<Id, User>();
			for (PermissionSetAssignment row : [
				SELECT
					AssigneeId,
					Assignee.Name,
					Assignee.IsActive,
					PermissionSet.Name,
					PermissionSet.Label
				FROM PermissionSetAssignment
				WHERE PermissionSet.Name IN :names AND PermissionSet.NamespacePrefix = :namespace
				WITH SYSTEM_MODE
			]) {
				labels.put(row.PermissionSet.Name, row.PermissionSet.Label);
				if (!held.containsKey(row.AssigneeId)) {
					held.put(row.AssigneeId, new Set<String>());
				}
				held.get(row.AssigneeId).add(row.PermissionSet.Name);
				people.put(row.AssigneeId, row.Assignee);
			}
			for (Id userId : held.keySet()) {
				messages.addAll(inactiveMessages(people.get(userId), held.get(userId), labels));
			}
			ErrorLogger.logMessages(messages, CONTEXT, ErrorLogger.SEVERITY_WARNING);
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT);
		}
		return messages;
	}

	/** One message per successor an inactive person is owed, naming the first retired set. */
	@TestVisible
	private static List<String> inactiveMessages(
		User person,
		Set<String> sets,
		Map<String, String> labels
	) {
		List<String> messages = new List<String>();
		if (person == null || person.IsActive == true) {
			return messages;
		}
		for (String successor : BY_SET.keySet()) {
			if (sets.contains(successor)) {
				continue;
			}
			for (String retired : BY_SET.get(successor)) {
				if (sets.contains(retired)) {
					messages.add(
						String.format(
							BarnHelp.text('Mirror', 'Mirror_Access_RetiredSetInactive'),
							new List<Object>{
								person.Name,
								labels.get(retired),
								labels.containsKey(successor) ? labels.get(successor) : successor
							}
						)
					);
					break;
				}
			}
		}
		return messages;
	}
}
