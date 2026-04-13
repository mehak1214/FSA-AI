/**
 * AccountStatusService
 * Enforces valid OutletStatus__c transitions for Account records.
 * All status changes must go through this service — never set OutletStatus__c directly.
 *
 * Valid transitions:
 *   Draft      → Submitted
 *   Submitted  → Active | Rejected
 *   Active     → Inactive
 *   Inactive   → Active
 *   Rejected   → Submitted  (resubmit after editing)
 *   Rejected   → Abandoned  (sales rep drops the record)
 */
public with sharing class AccountStatusService {

    public static final String STATUS_DRAFT      = 'Draft';
    public static final String STATUS_SUBMITTED  = 'Submitted';
    public static final String STATUS_ACTIVE     = 'Active';
    public static final String STATUS_INACTIVE   = 'Inactive';
    public static final String STATUS_REJECTED   = 'Rejected';
    public static final String STATUS_ABANDONED  = 'Abandoned';

    // Map of allowed transitions: current status → set of allowed next statuses
    private static final Map<String, Set<String>> ALLOWED_TRANSITIONS = new Map<String, Set<String>>{
        STATUS_DRAFT     => new Set<String>{ STATUS_SUBMITTED },
        STATUS_SUBMITTED => new Set<String>{ STATUS_ACTIVE, STATUS_REJECTED },
        STATUS_ACTIVE    => new Set<String>{ STATUS_INACTIVE },
        STATUS_INACTIVE  => new Set<String>{ STATUS_ACTIVE },
        STATUS_REJECTED  => new Set<String>{ STATUS_SUBMITTED, STATUS_ABANDONED }
    };

    /**
     * Transition a single Account to a new status.
     * Throws AuraHandledException if the transition is invalid.
     */
    @AuraEnabled
    public static void transitionStatus(Id accountId, String newStatus) {
        if (accountId == null || String.isBlank(newStatus)) {
            throw new AuraHandledException('accountId and newStatus are required.');
        }

        Account acc = [
            SELECT Id, OutletStatus__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        String currentStatus = acc.OutletStatus__c;
        validateTransition(currentStatus, newStatus);

        acc.OutletStatus__c = newStatus;
        try {
            update acc;
        } catch (DmlException e) {
            throw new AuraHandledException('Status update failed: ' + e.getDmlMessage(0));
        }
    }

    /**
     * Validate and apply transition without a DML — used internally when
     * the caller already holds an Account record and will do their own DML.
     */
    public static void validateTransition(String currentStatus, String newStatus) {
        // Null/blank current status is only allowed when moving to Draft (new record)
        if (String.isBlank(currentStatus)) {
            if (newStatus != STATUS_DRAFT) {
                throw new AuraHandledException(
                    'New accounts must start in Draft status.'
                );
            }
            return;
        }

        // Same-status save (e.g. Draft→Draft, Rejected→Rejected) is always allowed —
        // it means the user edited fields without changing status.
        if (currentStatus == newStatus) {
            return;
        }

        Set<String> allowed = ALLOWED_TRANSITIONS.get(currentStatus);
        if (allowed == null || !allowed.contains(newStatus)) {
            throw new AuraHandledException(
                'Invalid status transition: ' + currentStatus + ' → ' + newStatus + '. ' +
                'Allowed: ' + (allowed != null ? String.join(new List<String>(allowed), ', ') : 'none') + '.'
            );
        }
    }

    /**
     * Returns the set of statuses a given status can transition to.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getAllowedNextStatuses(String currentStatus) {
        Set<String> allowed = ALLOWED_TRANSITIONS.get(currentStatus);
        return allowed != null ? new List<String>(allowed) : new List<String>();
    }

    /**
     * Submits an Account record to the standard Salesforce Approval Process.
     * Transitions status to Submitted first, then routes to Approval.
     * Throws a clear AuraHandledException if no approval process is configured.
     */
    @AuraEnabled
    public static void submitForApproval(Id accountId) {
        if (accountId == null) {
            throw new AuraHandledException('accountId is required.');
        }

        Account acc = [
            SELECT Id, OutletStatus__c FROM Account
            WHERE Id = :accountId LIMIT 1
        ];

        // Validate the transition before touching Approval
        validateTransition(acc.OutletStatus__c, STATUS_SUBMITTED);

        // Transition status to Submitted and clear any previous rejection reason
        acc.OutletStatus__c    = STATUS_SUBMITTED;
        acc.Rejection_Reason__c = null;
        try {
            update acc;
        } catch (DmlException e) {
            throw new AuraHandledException('Status update failed: ' + e.getDmlMessage(0));
        }

        // Submit to Approval Process
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(accountId);
        req.setSkipEntryCriteria(false);

        try {
            Approval.ProcessResult result = Approval.process(req);
            if (!result.isSuccess()) {
                // Roll back status if approval submission failed
                acc.OutletStatus__c = STATUS_DRAFT;
                update acc;
                throw new AuraHandledException(
                    'Approval submission failed: ' + result.getErrors()
                );
            }
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            // Roll back status
            acc.OutletStatus__c = STATUS_DRAFT;
            try { update acc; } catch (Exception ignored) {}

            String msg = e.getMessage() != null ? e.getMessage() : '';
            if (msg.containsIgnoreCase('no applicable approval process') ||
                msg.containsIgnoreCase('NO_APPLICABLE_PROCESS') ||
                msg.containsIgnoreCase('cannot be submitted')) {
                throw new AuraHandledException(
                    'No Approval Process found for this record. Please contact your admin.'
                );
            }
            throw new AuraHandledException('Approval submission error: ' + msg);
        }
    }
}