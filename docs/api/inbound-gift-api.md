# Inbound Gift API reference

For developers connecting a payment processor, online giving page or integration platform
to BarnCRM (feature X-03). The administrator's side, including the user and sign-in
setup, is in the admin guide: [Inbound Gift API](../admin-guide/inbound-gift-api.md). The
decisions behind this shape are in ADR-0051.

This contract is permanent once the Connect package is released as a managed package: new
optional fields may be added, and nothing below will be removed or renamed.

## Endpoint

```
POST /services/apexrest/<namespace>/v1/gifts
Content-Type: application/json
Authorization: Bearer <access token>
```

`<namespace>` is the package namespace. It is not registered yet, and in an org where the
package source is deployed without one (a development or test org) the path is
`/services/apexrest/v1/gifts`.

Authenticate with OAuth 2.0 as the integration user the administrator created, for example
with the client credentials flow of an External Client App. The user needs the Inbound Gift
API permission set and no other BarnCRM set. Without it Salesforce answers `403` before
BarnCRM sees the request.

One request records one gift. Sending the same request again is always safe.

## Request body

| Field | Type | Required | Meaning |
|---|---|---|---|
| `externalId` | string, up to 100 characters | yes | The gift's identifier in your system. It is what makes a resend safe, so it must never be reused for a different gift. Prefix it with your system's name (`stripe:ch_3N1xY2`) so two systems can never collide. It is matched **ignoring case**: `STRIPE:CH_3N1XY2` is the same gift as `stripe:ch_3N1xY2`, so two gifts must not differ only in case. |
| `amount` | number | yes | The amount received, greater than zero, at most two decimal places. |
| `paymentMethod` | string | yes | One of `Cash`, `Check`, `Card`, `ACH`, `Stock`, `Grant`, `Other`. Not case sensitive. |
| `giftDate` | string, `YYYY-MM-DD` | no | The day the money arrived. Today, in the integration user's time zone, when left out. |
| `paymentReference` | string, up to 255 characters | no | A check number, transaction id or deposit reference, shown on the gift and in the accounting export. |
| `donorId` | string | one of the two | The record id of the person (a contact, or a person account) or organization (an account) who gave. |
| `donorEmail` | string | one of the two | The donor's email address. Matched exactly, ignoring case, the way the importer matches: the oldest person with that address, whether stored as a contact or as a person account. |
| `fundCode` | string | no | The accounting code of the fund the gift is designated to. |
| `fundId` | string | no | The record id of that fund, instead of `fundCode`. Send one or neither: with neither, the gift goes to the organization's default fund. |
| `appealId` | string | no | The record id of the appeal the gift responds to. |

Send exactly one of `donorId` and `donorEmail`. Organizations are named by `donorId` only.
A field this API does not know is refused rather than ignored, so a misspelling cannot
quietly send a restricted gift to the default fund.

Every accepted gift is recorded with status Received and follows every rule a gift typed in
by hand follows: its household is filled in, it is designated to its fund, it counts in the
giving totals, and it can be receipted and acknowledged. The API never creates a donor,
never records a refund, and never changes a gift that is already recorded.

## Responses

Every response body has the same shape, with empty fields left out:

| Field | Meaning |
|---|---|
| `outcome` | `created`, `existing` or `rejected`. |
| `giftId` | The gift recorded, for `created` and `existing`, and the gift already holding the identifier for `external_id_conflict` when the integration user can see it. |
| `errorCode` | Present only when `outcome` is `rejected`. Stable: branch on this, not on the message. |
| `message` | A sentence for a person reading the log. Its wording may change. |

| HTTP status | `outcome` | `errorCode` | What happened, and what to do |
|---|---|---|---|
| `201` | `created` | | The gift is recorded. |
| `200` | `existing` | | A gift with this `externalId` and the same amount was already recorded, by an earlier send. Nothing changed. Treat it as success. |
| `400` | `rejected` | `invalid_request` | The body is not JSON, has a field this API does not know, or has a value of the wrong type. Fix the request. |
| `400` | `rejected` | `invalid_field` | A field is missing, too long or not an allowed value, or two fields that exclude each other were both sent. The message names the field. |
| `409` | `rejected` | `external_id_conflict` | This `externalId` already belongs to a gift with a different amount, or to a gift the integration user cannot see. Nothing changed. Find out which of the two is right in your system; do not retry. |
| `422` | `rejected` | `donor_not_found` | No donor the integration user can see matches. Add the person or organization (or ask the nonprofit to share its donors with the integration user), then send the same request again. |
| `422` | `rejected` | `fund_not_found` | No active fund has this `fundCode` or `fundId`. |
| `422` | `rejected` | `appeal_not_found` | No appeal has this `appealId`. |
| `422` | `rejected` | `gift_not_saved` | The gift broke a rule of the organization's own, for example a validation rule they added, or no default fund is set, or the gift is dated in a closed accounting period; or the integration user lacks access to something recording the gift needs. The message is the rule's or the platform's. Nothing was saved. Sending it again gives the same answer until the nonprofit fixes the rule or the access. |
| `500` | `rejected` | `internal_error` | Something unexpected. Nothing was saved and the Error Log has the details. Sending the same request again is safe. |

Every `rejected` outcome is also written to the organization's Error Log, with the
`externalId` and the error code only, so the nonprofit can see a gift that did not arrive.
The message is not logged, because it can repeat what was sent, such as a donor's email
address; it is in the response.

### Retrying

Retry on a timeout, a `5xx`, or a network failure, with the same body. A retry of a request
that did succeed the first time answers `200 existing`, never a second gift. Do not retry
`400`, `409` or `422` unchanged: the answer will be the same.

## Examples

Sample bodies are in [`samples/`](samples/).

A gift found by email, designated to the fund with accounting code 4100
([`gift-by-email.json`](samples/gift-by-email.json)):

```bash
curl -X POST "$INSTANCE_URL/services/apexrest/v1/gifts" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  --data @docs/api/samples/gift-by-email.json
```

The first call answers `201` with [`response-created.json`](samples/response-created.json).
The same call again answers `200` with [`response-existing.json`](samples/response-existing.json).
The same `externalId` with another amount answers `409` with
[`response-external-id-conflict.json`](samples/response-external-id-conflict.json).

Other samples: the smallest valid body ([`gift-minimal.json`](samples/gift-minimal.json)),
a grant from an organization named by record id, with a fund and an appeal
([`gift-by-donor-id.json`](samples/gift-by-donor-id.json), whose ids are placeholders), an
unknown donor ([`response-donor-not-found.json`](samples/response-donor-not-found.json)) and
an invalid amount ([`response-invalid-field.json`](samples/response-invalid-field.json)).

## The Flow action

Inside Salesforce, the same thing is the **Record Inbound Gift** action in Flow Builder, in
the BarnCRM category. Its inputs are the request fields above (labelled External Id,
Amount, Payment Method, Gift Date, Payment Reference, Donor Id, Donor Email, Fund
Accounting Code, Fund Id, Appeal Id) and its outputs are Outcome, Gift Id, Error Code and
Message, with the same values and the same rules. A rejected gift does not fail the flow:
check Outcome in a Decision element. One flow run can send many gifts; each gets its own
result, and one gift's refusal does not stop the others.
