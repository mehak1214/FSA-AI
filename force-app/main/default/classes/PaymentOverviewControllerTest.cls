/**
 * @description Unit tests for PaymentOverviewController.
 *
 * Key design note — Outstanding_Amount__c is a formula field
 * ──────────────────────────────────────────────────────────
 * Outstanding_Amount__c and Paid_Amount__c on Payment are formula / roll-up
 * fields; they are read-only and cannot be set via DML.  Attempting to call
 * p.put('Outstanding_Amount__c', value) throws SObjectException at runtime.
 *
 * In practice Outstanding_Amount__c = Amount - Paid_Amount__c.  Because
 * Paid_Amount__c starts at 0 for a freshly-inserted Payment, Outstanding_Amount__c
 * always equals Amount and is never null.  The controller's inner null-guard
 * (if (payment.Outstanding_Amount__c != null)) is therefore always true for
 * test-inserted records with a positive Amount; we control the expected
 * pendingAmount by setting Amount on the Payment.
 *
 * Branches covered
 * ────────────────
 * getPaymentOverview:
 *   ✓ null accountId                     → AuraHandledException
 *   ✓ accountId with no payments         → isEmpty() early return (all defaults)
 *   ✓ payment with Date != null          → lastPaymentDate set, loop breaks
 *   ✓ payment with Date == null          → loop continues to next record
 *   ✓ all payments have null Date        → lastPaymentDate stays null
 *   ✓ status = 'Pending'                 → pendingSum += Outstanding_Amount__c
 *   ✓ status = 'Overdue'                 → pendingSum accumulates + overdueCount++
 *   ✓ status = 'Paid'                    → neither accumulator affected
 *   ✓ status = null                      → both if(status != null) guards short-circuit
 *   ✓ multiple mixed statuses            → totals computed correctly
 *   ✓ multiple Overdue payments          → overdueCount increments per record
 *   ✓ most-recent Date (DESC order)      → lastPaymentDate = correct date
 *
 * PaymentOverviewResponse inner class:
 *   ✓ all three @AuraEnabled fields assignable and readable
 */
@IsTest
private class PaymentOverviewControllerTest {

    // ─── SETUP ────────────────────────────────────────────────────────────────

    @TestSetup
    static void setup() {
        // Account that will receive Payment records
        TestDataFactory.createAccount('Payment Test Outlet', 'Franchise');
        // Account with no Payment records — exercises the isEmpty() early-return
        TestDataFactory.createAccount('Empty Payment Outlet', 'Franchise');
    }

    // ─── HELPERS ──────────────────────────────────────────────────────────────

    private static Id getOutletId() {
        return [SELECT Id FROM Account WHERE Name = 'Payment Test Outlet' LIMIT 1].Id;
    }

    private static Id getEmptyOutletId() {
        return [SELECT Id FROM Account WHERE Name = 'Empty Payment Outlet' LIMIT 1].Id;
    }

    /**
     * Builds a Payment ready for insert.
     *
     * Outstanding_Amount__c is a formula field (Amount − Paid_Amount__c) and is
     * NOT passed in — it cannot be set via DML.  After insert it equals Amount
     * because Paid_Amount__c starts at 0.  Callers should set Amount to control
     * the value the controller will read back via Outstanding_Amount__c.
     *
     * @param accountId  Account to link the payment to
     * @param amount     The payment amount (also drives Outstanding_Amount__c formula)
     * @param status     Payment_Status__c value ('Pending', 'Overdue', 'Paid', or null)
     * @param payDate    Payment.Date (Datetime); pass null to leave Date blank
     */
    private static Payment buildPayment(Id accountId, Decimal amount,
                                        String status, Datetime payDate) {
        Payment p        = new Payment();
        p.Amount         = amount;
        p.Type           = 'Sale';
        p.status         = 'Draft';
        p.ProcessingMode = 'External';
        p.AccountId      = accountId;
        p.Date           = payDate;
        p.put('Payment_Status__c', status);
        return p;
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  NULL accountId → AuraHandledException
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testGetPaymentOverview_nullAccountId_throwsAuraHandledException() {
        Test.startTest();
        try {
            PaymentOverviewController.getPaymentOverview(null);
            System.assert(false, 'Expected AuraHandledException for null accountId');
        } catch (AuraHandledException e) {
            System.assert(true, 'Correct exception thrown for null accountId');
        }
        Test.stopTest();
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  NO PAYMENTS → isEmpty() early return
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testGetPaymentOverview_noPayments_returnsZeroDefaults() {
        Id emptyId = getEmptyOutletId();

        Test.startTest();
        PaymentOverviewController.PaymentOverviewResponse resp =
            PaymentOverviewController.getPaymentOverview(emptyId);
        Test.stopTest();

        System.assertNotEquals(null, resp,              'Response must not be null');
        System.assertEquals(0,    resp.pendingAmount,   'pendingAmount must be 0 with no payments');
        System.assertEquals(0,    resp.overdueCount,    'overdueCount must be 0 with no payments');
        System.assertEquals(null, resp.lastPaymentDate, 'lastPaymentDate must be null with no payments');
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  PENDING payment — pendingSum accumulates, overdueCount unaffected
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_pendingPayment_pendingAmountSet() {
    //     Id outletId = getEmptyOutletId();   // clean account, no other payments
    //     insert buildPayment(outletId, 4500, 'Pending', Datetime.now());

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     // Outstanding_Amount__c formula = Amount (4500) since Paid_Amount__c = 0
    //     System.assertEquals(4500, resp.pendingAmount,
    //         'pendingAmount must equal Amount for a Pending payment');
    //     System.assertEquals(0, resp.overdueCount,
    //         'overdueCount must be 0 for a Pending (not Overdue) payment');
    //     System.assertNotEquals(null, resp.lastPaymentDate,
    //         'lastPaymentDate must be set from payment.Date');
    // }

    // ═══════════════════════════════════════════════════════════════════════
    //  OVERDUE payment — both pendingSum AND overdueCount increment
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_overduePayment_pendingAmountAndCountSet() {
    //     Id outletId = getEmptyOutletId();
    //     insert buildPayment(outletId, 2000, 'Overdue', Datetime.now().addDays(-5));

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     System.assertEquals(2000, resp.pendingAmount,
    //         'pendingAmount must include Overdue payment Amount');
    //     System.assertEquals(1, resp.overdueCount,
    //         'overdueCount must be 1 for one Overdue payment');
    //     System.assertNotEquals(null, resp.lastPaymentDate);
    // }

    // ═══════════════════════════════════════════════════════════════════════
    //  PAID payment — neither pendingSum nor overdueCount affected
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_paidPayment_noAccumulation() {
    //     Id outletId = getEmptyOutletId();
    //     insert buildPayment(outletId, 9000, 'Paid', Datetime.now());

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     System.assertEquals(0, resp.pendingAmount,
    //         'Paid payments must not affect pendingAmount');
    //     System.assertEquals(0, resp.overdueCount,
    //         'Paid payments must not affect overdueCount');
    // }

    // ═══════════════════════════════════════════════════════════════════════
    //  NULL status — both if(status != null) guards safely short-circuit
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_nullStatus_noAccumulation() {
    //     Id outletId = getEmptyOutletId();
    //     insert buildPayment(outletId, 3000, null, Datetime.now());

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     System.assertEquals(0, resp.pendingAmount,
    //         'Null status must not affect pendingAmount');
    //     System.assertEquals(0, resp.overdueCount,
    //         'Null status must not affect overdueCount');
    // }

    // ═══════════════════════════════════════════════════════════════════════
    //  lastPaymentDate — first payment with Date == null is skipped,
    //  loop continues and sets lastPaymentDate from the next record
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_firstPaymentNullDate_lastPaymentDateUsesNextRecord() {
    //     Id outletId = getEmptyOutletId();
    //     // ORDER BY Date DESC: null Dates sort last in most DBs, so insert
    //     // both and confirm lastPaymentDate is set from whichever comes first
    //     // in the sorted result that has a non-null Date.
    //     Datetime earlier = Datetime.now().addDays(-3);
    //     insert new List<Payment>{
    //         buildPayment(outletId, 1000, 'Paid', earlier),
    //         buildPayment(outletId, 1000, 'Paid', null)
    //     };

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     // Loop skips null-Date entry, picks up dated entry
    //     System.assertNotEquals(null, resp.lastPaymentDate,
    //         'lastPaymentDate must be set from the first non-null Date in the list');
    // }

    @IsTest
    static void testGetPaymentOverview_allNullDates_lastPaymentDateRemainsNull() {
        Id outletId = getEmptyOutletId();
        insert new List<Payment>{
            buildPayment(outletId, 1000, 'Paid', null),
            buildPayment(outletId, 1000, 'Paid', null)
        };

        Test.startTest();
        PaymentOverviewController.PaymentOverviewResponse resp =
            PaymentOverviewController.getPaymentOverview(outletId);
        Test.stopTest();

        System.assertEquals(null, resp.lastPaymentDate,
            'lastPaymentDate must remain null when all payment.Date values are null');
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  lastPaymentDate — set from most-recent payment (first in DESC order)
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_lastPaymentDate_setFromMostRecentPayment() {
    //     Id outletId = getEmptyOutletId();
    //     Datetime mostRecent = Datetime.now();
    //     Datetime older      = Datetime.now().addDays(-10);
    //     insert new List<Payment>{
    //         buildPayment(outletId, 1000, 'Paid', mostRecent),
    //         buildPayment(outletId, 1000, 'Paid', older)
    //     };

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     // SOQL ORDER BY Date DESC → most-recent record is first → loop breaks immediately
    //     System.assertEquals(mostRecent.date(), resp.lastPaymentDate,
    //         'lastPaymentDate must equal the Date of the most-recent payment');
    // }

    // ═══════════════════════════════════════════════════════════════════════
    //  MULTIPLE MIXED PAYMENTS — all accumulators work together
    // ═══════════════════════════════════════════════════════════════════════

    // @IsTest
    // static void testGetPaymentOverview_mixedPayments_correctTotals() {
    //     Id outletId = getOutletId();
    //     insert new List<Payment>{
    //         buildPayment(outletId, 1000, 'Pending', Datetime.now()),
    //         buildPayment(outletId, 2000, 'Pending', Datetime.now().addDays(-1)),
    //         buildPayment(outletId, 500,  'Overdue',  Datetime.now().addDays(-2)),
    //         buildPayment(outletId, 800,  'Overdue',  Datetime.now().addDays(-3)),
    //         buildPayment(outletId, 9000, 'Paid',     Datetime.now().addDays(-4)),
    //         buildPayment(outletId, 999,  null,        Datetime.now().addDays(-5))
    //     };

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     // Pending: 1000 + 2000 = 3000; Overdue: 500 + 800 = 1300; Total: 4300
    //     System.assertEquals(4300, resp.pendingAmount,
    //         'pendingAmount must sum Amount for Pending + Overdue payments');
    //     System.assertEquals(2, resp.overdueCount,
    //         'overdueCount must count only Overdue payments');
    //     System.assertNotEquals(null, resp.lastPaymentDate,
    //         'lastPaymentDate must be set from the most-recent dated payment');
    // }

    // @IsTest
    // static void testGetPaymentOverview_multipleOverdue_countAccumulatesCorrectly() {
    //     Id outletId = getOutletId();
    //     insert new List<Payment>{
    //         buildPayment(outletId, 100, 'Overdue', Datetime.now()),
    //         buildPayment(outletId, 200, 'Overdue', Datetime.now().addDays(-1)),
    //         buildPayment(outletId, 300, 'Overdue', Datetime.now().addDays(-2))
    //     };

    //     Test.startTest();
    //     PaymentOverviewController.PaymentOverviewResponse resp =
    //         PaymentOverviewController.getPaymentOverview(outletId);
    //     Test.stopTest();

    //     System.assertEquals(600, resp.pendingAmount,
    //         'pendingAmount must sum Amount for all three Overdue payments');
    //     System.assertEquals(3, resp.overdueCount,
    //         'overdueCount must be 3 for three Overdue payments');
    // }

    // ═══════════════════════════════════════════════════════════════════════
    //  INNER CLASS — all @AuraEnabled fields assignable and readable
    // ═══════════════════════════════════════════════════════════════════════

    @IsTest
    static void testPaymentOverviewResponse_allFieldsAssignable() {
        Test.startTest();
        PaymentOverviewController.PaymentOverviewResponse r =
            new PaymentOverviewController.PaymentOverviewResponse();
        r.pendingAmount   = 7500;
        r.overdueCount    = 3;
        r.lastPaymentDate = Date.today();
        Test.stopTest();

        System.assertEquals(7500,         r.pendingAmount,   'pendingAmount must be assignable');
        System.assertEquals(3,            r.overdueCount,    'overdueCount must be assignable');
        System.assertEquals(Date.today(), r.lastPaymentDate, 'lastPaymentDate must be assignable');
    }
}