/**
 * BarnCRM Connector's checks in Health Check (CN-01; design `integration-hub-design.md` Section
 * 3.9; security review F11 and F12; ADR-0057's extension seam). Core finds this class by name
 * (`HealthCheckExtensions.EXTENSION_CLASSES`). Asked only while the module is on, of a viewer
 * who may manage settings:
 * - connections whose callouts are still off in Setup (warning);
 * - connections missing from the "BarnCRM Connections" permission set (warning);
 * - keys replaced in the last 7 days (info, F11), so a key swapped to another account shows;
 * - the "BarnCRM Connections" set giving access to anything but connection principals (warning,
 *   F12);
 * - recipes that run as System, with who chose it and when (info, CN-02);
 * - Active BarnCRM Automation recipes while Recipe Access was never saved (warning, CN-02);
 * - the CN-03 clock checks of canonical model R-CR8 (`ConnectorClockChecks`).
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ConnectorHealthCheckExtension implements HealthCheckExtension {
	private static final String MODULE = ConnectorConnections.MODULE;
	private static final Integer REPLACED_DAYS = 7;

	@NamespaceAccessible
	public ConnectorHealthCheckExtension() {
		// Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
	}

	public List<HealthCheckService.Finding> findings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		if (
			!HealthCheckService.canManageSettings() || ModuleManagerService.turnedOff().contains(MODULE.toLowerCase())
		) {
			return found;
		}
		try {
			List<String> calloutsOff = new List<String>();
			List<String> accessMissing = new List<String>();
			for (ConnectorConnections.Connection row : ConnectorConnections.page().connections) {
				if (!row.calloutsEnabled) {
					calloutsOff.add(row.label);
				}
				if (!row.accessGranted) {
					accessMissing.add(row.label);
				}
			}
			if (!calloutsOff.isEmpty()) {
				found.add(
					finding(
						'connector_callouts_off',
						BarnHelp.text('Connector', 'Connector_Health_CalloutsOff_Title'),
						BarnHelp.text(
							'Connector',
							'Connector_Health_CalloutsOff_Detail',
							new List<Object>{ joined(calloutsOff) }
						),
						HealthCheckService.SEVERITY_WARNING
					)
				);
			}
			if (!accessMissing.isEmpty()) {
				found.add(
					finding(
						'connector_access_missing',
						BarnHelp.text('Connector', 'Connector_Health_AccessMissing_Title'),
						BarnHelp.text(
							'Connector',
							'Connector_Health_AccessMissing_Detail',
							new List<Object>{ joined(accessMissing) }
						),
						HealthCheckService.SEVERITY_WARNING
					)
				);
			}
			List<String> replaced = ConnectorConnections.keysReplacedSince(REPLACED_DAYS);
			if (!replaced.isEmpty()) {
				found.add(
					finding(
						'connector_keys_replaced',
						BarnHelp.text('Connector', 'Connector_Health_KeysReplaced_Title'),
						BarnHelp.text(
							'Connector',
							'Connector_Health_KeysReplaced_Detail',
							new List<Object>{ joined(replaced) }
						),
						HealthCheckService.SEVERITY_INFO
					)
				);
			}
			if (accessSetHoldsMore()) {
				found.add(
					finding(
						'connector_access_set_extra',
						BarnHelp.text('Connector', 'Connector_Health_AccessSetExtra_Title'),
						BarnHelp.text('Connector', 'Connector_Health_AccessSetExtra_Detail'),
						HealthCheckService.SEVERITY_WARNING
					)
				);
			}
			found.addAll(recipeFindings());
			found.addAll(ConnectorClockChecks.findings());
		} catch (Exception e) {
			found.add(HealthCheckService.checkFailed('connector', e));
		}
		return found;
	}

	/**
	 * CN-02 (R-CR4): every recipe that runs as System, with who chose it and when (info), and
	 * Active BarnCRM Automation recipes while Recipe Access has never been saved (warning).
	 */
	@TestVisible
	private static List<HealthCheckService.Finding> recipeFindings() {
		List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
		List<String> systemRecipes = new List<String>();
		Integer automationActive = 0;
		for (Connector_Recipe__c recipe : [
			SELECT Name, Status__c, Run_As__c, Run_As_Chosen_By__r.Name, Run_As_Chosen_At__c
			FROM Connector_Recipe__c
			WHERE Run_As__c = :ConnectorRecipes.RUN_AS_SYSTEM OR Status__c = :ConnectorRunStore.ACTIVE
			WITH SYSTEM_MODE
			ORDER BY Name
			LIMIT 500
		]) {
			if (recipe.Run_As__c == ConnectorRecipes.RUN_AS_SYSTEM) {
				systemRecipes.add(
					BarnHelp.text(
						'Connector',
						'Connector_Health_SystemRecipe',
						new List<Object>{
							recipe.Name,
							recipe.Run_As_Chosen_By__r?.Name,
							recipe.Run_As_Chosen_At__c?.format()
						}
					)
				);
			} else if (recipe.Run_As__c == ConnectorRecipes.RUN_AS_AUTOMATION) {
				automationActive++;
			}
		}
		if (!systemRecipes.isEmpty()) {
			found.add(
				finding(
					'connector_system_recipes',
					BarnHelp.text('Connector', 'Connector_Health_SystemRecipes_Title'),
					BarnHelp.text(
						'Connector',
						'Connector_Health_SystemRecipes_Detail',
						new List<Object>{ String.join(systemRecipes, '; ') }
					),
					HealthCheckService.SEVERITY_INFO
				)
			);
		}
		if (automationActive > 0 && !ConnectorIdentity.accessSaved()) {
			found.add(
				finding(
					'connector_recipe_access_unsaved',
					BarnHelp.text('Connector', 'Connector_Health_RecipeAccess_Title'),
					BarnHelp.text('Connector', 'Connector_Health_RecipeAccess_Detail'),
					HealthCheckService.SEVERITY_WARNING
				)
			);
		}
		return found;
	}

	/**
	 * Whether "BarnCRM Connections" grants anything besides `BarnConn_` principal access: an
	 * object or field permission, or another setup entity (a class, a page, another credential).
	 */
	@TestVisible
	private static Boolean accessSetHoldsMore() {
		PermissionSet target = ConnectorConnections.accessSet();
		if (target == null) {
			return false;
		}
		Set<Id> entities = ConnectorConnections.store().grantedEntities(target.Id);
		entities.removeAll(ConnectorConnections.store().principalIds().values());
		Id setId = target.Id;
		return !entities.isEmpty() ||
			[SELECT COUNT() FROM ObjectPermissions WHERE ParentId = :setId WITH SYSTEM_MODE] > 0 ||
			[SELECT COUNT() FROM FieldPermissions WHERE ParentId = :setId WITH SYSTEM_MODE] > 0;
	}

	private static String joined(List<String> labels) {
		return String.join(labels, ', ');
	}

	private static HealthCheckService.Finding finding(String key, String title, String detail, String severity) {
		return new HealthCheckService.Finding(key, title, detail, severity, HealthCheckService.CATEGORY_SETTINGS);
	}
}
