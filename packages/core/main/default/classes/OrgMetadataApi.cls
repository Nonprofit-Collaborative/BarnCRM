/**
 * The org's own Metadata API (SOAP), called through the org connection `Barn_Org_Connection`
 * (ADR-0148) with the running job's session in the SOAP header, for the Duplicate Rules Starter
 * (C-61, ADR "Duplicate Rules Starter and report subscriptions through the org connection").
 * Only a queued job calls it: a Lightning session cannot call the API.
 */
public with sharing class OrgMetadataApi {
	private static final String NS = 'http://soap.sforce.com/2006/04/metadata';
	private static final Integer TIMEOUT_MS = 120000;

	public class MetadataException extends Exception {
	}

	/** One component's result: its full name, whether it was saved, and the API's words if not. */
	public class Result {
		public String fullName;
		public Boolean success = false;
		public String message;
	}

	/**
	 * Creates or updates components of one type in one call (10 at most). Each body is the
	 * component's elements in the WSDL's sequence order, written with `element`.
	 */
	public static List<Result> upsertMetadata(String type, List<String> bodies) {
		String metadata = '';
		for (String body : bodies) {
			metadata += '<met:metadata xsi:type="met:' + type + '">' + body + '</met:metadata>';
		}
		HttpRequest call = new HttpRequest();
		call.setEndpoint(
			'callout:' +
				ImportNewFieldService.CONNECTION +
				'/services/Soap/m/' +
				ImportNewFieldService.API_VERSION
		);
		call.setMethod('POST');
		call.setHeader('Content-Type', 'text/xml; charset=UTF-8');
		call.setHeader('SOAPAction', '""');
		call.setTimeout(TIMEOUT_MS);
		call.setBody(envelope('upsertMetadata', metadata, UserInfo.getSessionId()));
		return results(new Http().send(call).getBody());
	}

	@TestVisible
	private static String envelope(String operation, String metadata, String sessionId) {
		return '<?xml version="1.0" encoding="UTF-8"?><soapenv:Envelope ' +
			'xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
			'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:met="' +
			NS +
			'"><soapenv:Header><met:SessionHeader><met:sessionId>' +
			String.valueOf(sessionId).escapeXml() +
			'</met:sessionId></met:SessionHeader></soapenv:Header><soapenv:Body><met:' +
			operation +
			'>' +
			metadata +
			'</met:' +
			operation +
			'></soapenv:Body></soapenv:Envelope>';
	}

	/** Each `result` of the response; a SOAP fault (a refused session, a bad call) throws. */
	@TestVisible
	private static List<Result> results(String responseBody) {
		Dom.Document document = new Dom.Document();
		document.load(responseBody);
		Dom.XmlNode root = document.getRootElement();
		List<Dom.XmlNode> faults = find(root, 'faultstring');
		if (!faults.isEmpty()) {
			throw new MetadataException(faults[0].getText());
		}
		List<Result> found = new List<Result>();
		for (Dom.XmlNode node : find(root, 'result')) {
			Result each = new Result();
			List<String> messages = new List<String>();
			for (Dom.XmlNode child : node.getChildElements()) {
				if (child.getName() == 'fullName') {
					each.fullName = child.getText();
				} else if (child.getName() == 'success') {
					each.success = child.getText() == 'true';
				} else if (child.getName() == 'errors') {
					for (Dom.XmlNode message : find(child, 'message')) {
						messages.add(message.getText());
					}
				}
			}
			each.message = messages.isEmpty() ? null : String.join(messages, ' ');
			found.add(each);
		}
		return found;
	}

	/** `<met:name>value</met:name>`, the value escaped. */
	public static String element(String name, Object value) {
		return '<met:' + name + '>' + String.valueOf(value).escapeXml() + '</met:' + name + '>';
	}

	/** `<met:name>children</met:name>`, the children already written. */
	public static String wrap(String name, String children) {
		return '<met:' + name + '>' + children + '</met:' + name + '>';
	}

	private static List<Dom.XmlNode> find(Dom.XmlNode node, String localName) {
		List<Dom.XmlNode> found = new List<Dom.XmlNode>();
		if (node.getNodeType() == Dom.XmlNodeType.ELEMENT) {
			if (node.getName() == localName) {
				found.add(node);
				return found;
			}
			for (Dom.XmlNode child : node.getChildElements()) {
				found.addAll(find(child, localName));
			}
		}
		return found;
	}
}
