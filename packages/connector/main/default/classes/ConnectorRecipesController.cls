/**
 * The Recipes and Run History sections of Super Connector, Recipe Access, the Recipe Clock and
 * the Integration User (CN-02, CN-03; canonical model R-CR1 to R-CR8, R-RUN4, R-CS1). Thin: the
 * rules live in `ConnectorRecipes`, `ConnectorIdentity`, `ConnectorClock`,
 * `ConnectorIntegrationUser` and `ConnectorRecipeDocument`. Granted by BarnCRM Connector Admin and Viewer; every change
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

	/** Roll Back, Discard Draft Changes, Export Recipe and file import (CN-08, R-CR11, R-CR12). */
	@AuraEnabled
	public static ConnectorRecipes.Recipe rollBack(Id recipeId) {
		try {
			return ConnectorRecipes.rollBack(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'rollBack');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Recipe discardDraft(Id recipeId) {
		try {
			return ConnectorRecipes.discardDraft(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'discardDraft');
		}
	}

	@AuraEnabled
	public static String exportRecipe(Id recipeId) {
		try {
			return ConnectorRecipeFiles.export(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'exportRecipe');
		}
	}

	@AuraEnabled
	public static ConnectorRecipeFiles.Imported importFile(String fileText) {
		try {
			return ConnectorRecipeFiles.read(fileText);
		} catch (Exception failure) {
			throw shown(failure, 'importFile');
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

	@AuraEnabled
	public static ConnectorRecipes.Recipe saveRecipeSettings(
		Id recipeId,
		Integer retryAttempts,
		Integer pauseAfterFailures,
		Integer keepRunsDays,
		Boolean ignoreOwnChanges
	) {
		try {
			return ConnectorRecipes.saveSettings(
				recipeId,
				retryAttempts,
				pauseAfterFailures,
				keepRunsDays,
				ignoreOwnChanges
			);
		} catch (Exception failure) {
			throw shown(failure, 'saveRecipeSettings');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Recipe pauseRecipe(Id recipeId) {
		try {
			return ConnectorRecipes.pause(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'pauseRecipe');
		}
	}

	@AuraEnabled
	public static ConnectorRecipes.Recipe resumeRecipe(Id recipeId) {
		try {
			return ConnectorRecipes.resume(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'resumeRecipe');
		}
	}

	@AuraEnabled
	public static Integer retryAllFailed(Id recipeId) {
		try {
			return ConnectorRecipes.retryAllFailed(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'retryAllFailed');
		}
	}

	/** The Recipe Clock card (CN-03, R-CR6). */
	@AuraEnabled
	public static ConnectorClock.Status getClock() {
		try {
			ConnectorConnections.requireManager();
			return ConnectorClock.status();
		} catch (Exception failure) {
			throw shown(failure, 'getClock');
		}
	}

	@AuraEnabled
	public static ConnectorClock.Status setRecipesPaused(Boolean paused) {
		try {
			return ConnectorClock.setPaused(paused);
		} catch (Exception failure) {
			throw shown(failure, 'setRecipesPaused');
		}
	}

	@AuraEnabled
	public static ConnectorClock.Status restartClock() {
		try {
			return ConnectorClock.restart();
		} catch (Exception failure) {
			throw shown(failure, 'restartClock');
		}
	}

	/** The Integration User card (CN-03, R-CR4, R-CS1). */
	@AuraEnabled
	public static ConnectorIntegrationUser.View getIntegrationUser() {
		try {
			ConnectorConnections.requireManager();
			return ConnectorIntegrationUser.view();
		} catch (Exception failure) {
			throw shown(failure, 'getIntegrationUser');
		}
	}

	@AuraEnabled
	public static ConnectorIntegrationUser.View chooseIntegrationUser(String userId) {
		try {
			return ConnectorIntegrationUser.choose(userId);
		} catch (Exception failure) {
			throw shown(failure, 'chooseIntegrationUser');
		}
	}

	/** A refusal written for a person as it is; anything else as Core's unexpected error, logged. */
	private static AuraHandledException shown(Exception failure, String method) {
		if (
			failure instanceof ConnectorConnections.ConnectorException ||
			failure instanceof ConnectorRecipeDocument.DocumentException ||
			failure instanceof ConnectorRecipeFiles.FileException
		) {
			return UserErrors.message(failure.getMessage());
		}
		return UserErrors.wrap(failure, CONTEXT + method, true);
	}
}
