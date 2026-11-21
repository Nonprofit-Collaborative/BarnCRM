/**
 * The Webhook card of a recipe on Super Connector (CN-04; canonical model R-CR3, R-CR10): the
 * receiver addresses, New Webhook Token and Webhook Hourly Cap. Thin: the rules live in
 * `ConnectorWebhooks`. Granted by BarnCRM Connector Admin and Viewer; a new token and the cap
 * need Manage BarnCRM Connector (R-CR3). The token is returned only by `newWebhookToken`, once.
 */
public with sharing class ConnectorWebhooksController {
	private static final String CONTEXT = 'ConnectorWebhooksController.';

	@AuraEnabled
	public static ConnectorWebhooks.View getWebhook(Id recipeId) {
		try {
			return ConnectorWebhooks.view(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'getWebhook');
		}
	}

	@AuraEnabled
	public static ConnectorWebhooks.View newWebhookToken(Id recipeId) {
		try {
			return ConnectorWebhooks.newToken(recipeId);
		} catch (Exception failure) {
			throw shown(failure, 'newWebhookToken');
		}
	}

	@AuraEnabled
	public static ConnectorWebhooks.View saveWebhookCap(Id recipeId, Integer hourlyCap) {
		try {
			return ConnectorWebhooks.saveCap(recipeId, hourlyCap);
		} catch (Exception failure) {
			throw shown(failure, 'saveWebhookCap');
		}
	}

	private static AuraHandledException shown(Exception failure, String method) {
		if (failure instanceof ConnectorConnections.ConnectorException) {
			return UserErrors.message(failure.getMessage());
		}
		return UserErrors.wrap(failure, CONTEXT + method, true);
	}
}
