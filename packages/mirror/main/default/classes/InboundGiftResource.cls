/**
 * The inbound gift REST endpoint (feature X-03): `POST /services/apexrest/<namespace>/v1/gifts`,
 * one gift per request. The contract is `docs/api/inbound-gift-api.md`.
 *
 * `global` because the platform requires it of a REST resource, and permanent for the same
 * reason as `InboundGift` (ADR-0051). All the work is in `InboundGiftService`; this class only
 * turns a request body into a gift and a result into a status code and a body.
 */
@RestResource(urlMapping='/v1/gifts')
global with sharing class InboundGiftResource {
    @HttpPost
    global static void create() {
        RestRequest request = RestContext.request;
        InboundGiftResult result = InboundGiftService.recordBody(
            request == null ? null : request.requestBody
        );
        RestResponse response = RestContext.response;
        response.statusCode = InboundGiftResult.httpStatus(result);
        response.addHeader('Content-Type', 'application/json');
        response.responseBody = Blob.valueOf(JSON.serialize(result, true));
    }
}
