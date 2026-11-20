/**
 * The Recipes and Run History sections of Super Connector, and Recipe Access (CN-02; canonical
 * model R-CR1 to R-CR5, R-RUN4). Thin: the rules live in `ConnectorRecipes`, `ConnectorIdentity`
 * and `ConnectorRecipeDocument`. Granted by BarnCRM Connector Admin and Viewer; every change
 * needs Manage BarnCRM Connector, which only the Admin set holds (R-CR3). Nothing is cacheable,
 * so a page always shows the runs as they are.
 */
public with sharing class ConnectorRecipesController {
	private static final String CONTEXT = 'ConnectorRecipesController.';

	@AuraEnabled
	public static ConnectorRecipes.RecipesPage getRecipes() {
		try {
			return ConnectorRecipes.page();
		} catch (Exception failure) {
			throw shown(failure, 'getRecipes');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Recipe saveDraft(
		Id recipeId,
		String name,
		String description,
		String draftJson,
		String recordOwnerId
	) {
		try {
			return ConnectorRecipes.saveDraft(recipeId, name, description, draftJson, recordOwnerId);
		} catch (Exception failure) {
			throw shown(failure, 'saveDraft');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Recipe publish(Id recipeId) {
		try {
			return ConnectorRecipes.publish(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'publish');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Recipe setRunAs(Id recipeId, String runAs, Boolean confirmed) {
		try {
			return ConnectorRecipes.setRunAs(recipeId, runAs, confirmed);
		} catch (Exception failure) {
			throw shown(failure, 'setRunAs');
		}
	}

	@AuraEnabled
	public static void deleteRecipe(Id recipeId) {
		try {
			ConnectorRecipes.remove(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'deleteRecipe');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Run runNow(Id recipeId, String inputJson) {
		try {
			return ConnectorRecipes.runNow(recipeId, inputJson);
		} catch (Exception failure) {
			throw shown(failure, 'runNow');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Run testRecipe(
		Id recipeId,
		String sampleJson,
		String recordId,
		Boolean sendForReal
	) {
		try {
			return ConnectorRecipes.test(recipeId, sampleJson, recordId, sendForReal);
		} catch (Exception failure) {
			throw shown(failure, 'testRecipe');
		}
	}

	@AuraEnabled
	public static List<ConnectorRecipes.Run> getRuns(Id recipeId) {
		try {
			return ConnectorRecipes.runs(recipeId, null);
		} catch (Exception failure) {
			throw shown(failure, 'getRuns');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Run getRun(Id runId) {
		try {
			List<ConnectorRecipes.Run> found = ConnectorRecipes.runs(null, runId);
			return found.isEmpty() ? null : found[0];
		} catch (Exception failure) {
			throw shown(failure, 'getRun');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Run retryRun(Id runId) {
		try {
			return ConnectorRecipes.retry(runId);
		} catch (Exception failure) {
			throw shown(failure, 'retryRun');
		}
	}

	@AuraEnabled
	public static ConnectorIdentity.Access getRecipeAccess() {
		try {
			ConnectorConnections.requireManager();
			return ConnectorIdentity.access();
		} catch (Exception failure) {
			throw shown(failure, 'getRecipeAccess');
		}
	}

	@AuraEnabled
	public static ConnectorIdentity.Access saveRecipeAccess(List<String> permissionSetIds) {
		try {
			return ConnectorIdentity.save(permissionSetIds);
		} catch (Exception failure) {
			throw shown(failure, 'saveRecipeAccess');
		}
	}

	/** A refusal written for a person as it is; anything else as Core's unexpected error, logged. */
	private static AuraHandledException shown(Exception failure, String method) {
		if (
			failure instanceof ConnectorConnections.ConnectorException ||
			failure instanceof ConnectorRecipeDocument.DocumentException
		) {
			return UserErrors.message(failure.getMessage());
		}
		return UserErrors.wrap(failure, CONTEXT + method, true);
	}
}
