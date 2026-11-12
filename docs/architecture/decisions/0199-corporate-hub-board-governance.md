# ADR-0199: Corporate Hub board governance: boards and committees, meetings, motions and votes, disclosures, and the board portal template

**Status:** Accepted (builder decision; reversible calls listed under Consequences)
**Date:** 2026-11-11
**Source:** plan Section 5.8 (CH-09 to CH-20), Section 5.9 (PB-02), Section 6.0a releases 1.10,
1.11, 1.14 and 1.17, D-118, D-156, D-178, D-186, D-187; builds on ADR-0196
`0196-corporate-hub-module.md` (its extension points), ADR-0185 (Portal Builder), ADR-0191
(portal templates), ADR-0013, ADR-0017, ADR-0021 and Section 9.9 (portability).

## Context

Corporate Hub (D-118) runs the board without any portal; board members see and act on it through
Portal Builder's board template (PB-02). The module ADR reserved board governance for new
objects in this package, board policy acknowledgments as Policy Acknowledgment rows with
`Person__c`, and the portal acknowledging through Core's `PortalActionExtension` seam. A board
member is a Core person (Contact) with no Salesforce login.

## Decision

1. **Boards and committees are one object (CH-09, CH-17; canonical model 29CH7).**
   `Board__c` (label Board or Committee) with a Type (Board, Committee, Task Force, Working
   Group, Advisory Council, Chapter) and an optional Parent Board, so a committee of the board,
   a task force or a chapter is the same record with the same roster, meetings and votes. It
   carries the term length, the term limit (consecutive terms), the quorum share and the skills
   the board wants (CH-15). Sharing Public Read/Write: the board is the organization's.
2. **A seat is a dated row (CH-09, 29CH8).** `Board_Member__c`, a detail of the board: the
   person, role (Chair, Vice Chair, Treasurer, Secretary, Member, Ex Officio), term start and
   end, term number, voting or not, skills and two optional demographic fields. Current and At
   Term Limit are formulas; a new term is a new row, so the history is the related list. The
   nightly Corporate Hub step reminds the board's owner of each current seat whose term ends
   within the reminder days, once per end date (R-CR1).
3. **Meetings (CH-10, 29CH9, 29CH10).** `Board_Meeting__c` looks up to its board (Restrict
   delete), with the start, place, status, agenda, a packet link, minutes and their approval
   state. Packets and supporting papers are Salesforce Files on the meeting. **Invite Board**
   adds one `Meeting_Attendee__c` per current seat (unique key meeting and person; voting from
   the seat). Roll-ups count voting invitees, voting members present, minutes approvals and
   packet reads; Quorum Needed is `CEILING(voting invitees x quorum share / 100)` and Quorum Met
   compares. Minutes go Draft, Submitted for Approval, Approved: staff submit, members approve in
   the portal (their approval is stamped on their attendee row), and a holder of Manage Corporate
   Hub marks them Approved, which records the date. The board approves minutes by its own
   procedure; the count of portal approvals informs that step, it does not replace it.
4. **Motions and votes (CH-11, 29CH11, 29CH12).** `Board_Motion__c` is a detail of the meeting
   where it was taken: text, mover, seconder, status (Proposed, Voting Open, Passed, Failed,
   Tabled, Withdrawn), resolution number and decided date. **Open Voting** creates one
   `Board_Vote__c` per voting attendee with the vote blank; votes are counted by roll-up; **Close
   Voting** records Passed or Failed from the counts (more For than Against) and the date. A vote
   changes only while voting is open, unless the user holds Manage Corporate Hub (recording a
   voice vote afterwards), enforced by a validation rule. A written consent outside a meeting is
   recorded as a meeting whose Location says it was held in writing.
5. **Disclosures (CH-12).** A conflict-of-interest disclosure is a Policy Acknowledgment of the
   conflict-of-interest policy with two new fields: the interests disclosed and whether a
   conflict was disclosed. **Request From Board** asks the board's current seat holders
   (`Person__c` rows, owned by the requester). A library document gains Ask Every Year: its
   request key adds the year, so the same version is asked again each year. The portal answers
   as the person; the validation rule `Own_Acknowledgment` lets a `Person__c` row become
   Acknowledged when Answered in Portal is set, a field no permission set can edit and only the
   portal action writes.
6. **Giving participation without a Giving dependency (CH-13).** The board panel reads the
   Contact field `Giving_This_Year__c` by describe, the way the Funders board dashboard does:
   present and readable means Giving is installed, and the share of current seat holders with a
   gift this fiscal year is shown; absent means the line is hidden.
7. **Board dashboard (CH-14).** Standard reports and one dashboard in the folder BarnCRM
   Corporate Hub: current roster, terms ending in the next 90 days, attendance this year and
   open disclosures. Giving participation stays on the board panel, since a shipped report on a
   Giving field would make this package depend on Giving. It complements the Funders financial
   board dashboard (F-07) and repeats nothing from it.
8. **Skills and diversity matrix (CH-15).** The board's Needed Skills against the skills its
   current seat holders hold, with each gap named; computed in the framework-free
   `boardModel` module. Demographic fields (age range, gender) are shown only when the setting
   Show Board Demographics is on (off by default); they are optional on every seat.
9. **Action items (CH-16, 29CH13).** `Meeting_Action_Item__c`, a detail of the board, names
   the meeting that raised it. Every later meeting of the board lists the board's open items
   raised before it, so an item is carried to each next agenda until it is Done or Dropped.
10. **Self-assessment (CH-19, 29CH14, 29CH15).** `Board_Assessment__c` (a detail of the board)
    and `Assessment_Answer__c` (one row per person per question). **Start Self-Assessment**
    copies the questions of a template in `BarnCorporateHubTemplates` (`assessments`, key
    `board-self-assessment`) to every current seat holder. A rating is 1 to 5 with a comment, and
    can change only while the assessment is Open. Results are a standard report (average rating
    by question).
11. **Availability poll (CH-20).** Up to three candidate times on the meeting; each attendee
    answers Yes, If Needed or No for each in the portal while the poll is open; roll-ups count the
    Yes answers; **Choose Time** sets the meeting's start and closes the poll.
12. **Board portal template (PB-02, CH-18).** `portal-client/templates/board.json`, requiring
    `CorporateHub`: My Meetings (agenda, packet link, attendance, Mark Packet Read), Minutes
    (Approve Minutes), My Votes (For, Against, Abstain), Disclosures and Policies (write the
    disclosure, Acknowledge), Self-Assessment, Meeting Availability, My Board Seats and My
    Details. The actions are `CorporateHubPortalExtension` (`CorporateHub.MarkPacketRead`,
    `CorporateHub.ApproveMinutes`, `CorporateHub.VoteFor`, `CorporateHub.VoteAgainst`,
    `CorporateHub.Abstain`, `CorporateHub.Acknowledge`), listed in Core's
    `PortalActionExtensions.EXTENSION_CLASSES`; `without sharing` in system mode (Without Sharing
    Register, Portal), each first re-reads the row by the verified person and refuses when the
    meeting, motion or request is not open. Packet read tracking (CH-18) is the member's own Mark
    Packet Read on their attendee row: the portal shows the packet link the staff set and does
    not serve files.
13. **Pages.** A Board panel (roster, terms, skills gaps, giving participation, open action
    items, Request From Board, Start Self-Assessment) and a Meeting panel (Invite Board,
    attendance and quorum, minutes, carried action items, motions and votes, the poll), both
    thin over `HubBoard`, text from `BarnHelp_CorporateHub`, no custom labels. Boards and Board
    Meetings tabs join the module's staff tabs.

## Alternatives Considered

- **Serve packet files through the portal API.** A session-scoped file endpoint is the
  stronger design for read tracking, but Apex response and heap limits cap a file near 2 MB,
  below a typical packet. Per-person expiring public links (ContentDistribution) would weaken
  file security and need an org setting. Rejected for now; the packet link is the staff's
  choice of where the packet lives.
- **Votes as an editable picklist on a portal page.** No Apex, but no server-side check that
  voting is open at the moment of the vote beyond the validation rule, and no voted-at time.
- **Poll options as their own object.** Any number of times, but two more objects for a feature
  where three candidates cover the common case.
- **Committees as a separate object.** Rejected by D-186: the roster generalizes.

## Consequences

- Staff run the board with no portal; the portal adds self-service for members.
- Reversible calls: three poll options; minutes approval by an admin after member approvals;
  a written consent recorded as a meeting; packets linked, not served; demographic fields
  limited to age range and gender, off by default.
- Ten objects join Corporate Hub (Module Manager's uninstall report lists them).
