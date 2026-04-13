/**
 * ExpensePolicyService
 * Core validation engine for expense policy and allowance checks.
 *
 * Called by ExpenseController.createExpense() and updateExpense() at save time.
 *
 * Rules:
 *  - Amount > cap * 1.5  → HARD BLOCK  (throws AuraHandledException)
 *  - Amount > cap        → SOFT WARN   (saves, returns warning, stamps breach fields)
 *  - No policy found     → PASS        (no policy configured = no restriction)
 *
 * Both type-cap and monthly-allowance checks follow the same thresholds.
 */
public with sharing class ExpensePolicyService {

    // ─────────────────────────────────────────────
    // RESULT WRAPPER returned to ExpenseController
    // ─────────────────────────────────────────────
    public class PolicyCheckResult {
        public Boolean  hasBreach          = false;
        public Boolean  typeBreach         = false;
        public Boolean  allowanceBreach    = false;
        public String   breachType         = null;   // 'Type Cap' | 'Monthly Allowance' | 'Both'
        public String   warningMessage     = null;   // shown as amber toast to rep
        public Decimal  capAtTime          = null;
        public Decimal  breachAmount       = null;
        public Decimal  allowanceAtTime    = null;
        public Decimal  allowanceUsedAtTime= null;
    }

    // Hard-block multiplier: amount > cap * BLOCK_MULTIPLIER → throw
    private static final Decimal BLOCK_MULTIPLIER = 1.5;

    // ─────────────────────────────────────────────
    // MAIN ENTRY POINT
    // expenseId: null when creating, populated when updating
    // ─────────────────────────────────────────────
    public static PolicyCheckResult evaluate(
            String  userId,
            String  expenseType,
            Decimal amount,
            String  expenseDate,
            String  expenseId) {

        PolicyCheckResult result = new PolicyCheckResult();

        // ── 1. Resolve manager and policy ────────────────
        User rep = [SELECT Id, ManagerId FROM User WHERE Id = :userId LIMIT 1];
        if (rep.ManagerId == null) return result; // no manager → no policy to check

        List<Expense_Policy__c> policies = [
            SELECT Travel_Cap__c, Food_Cap__c, Market_Execution_Cap__c,
                   Communications_Cap__c, Miscellaneous_Cap__c, Other_Cap__c,
                   Warn_Threshold_Pct__c
            FROM   Expense_Policy__c
            WHERE  Manager__c = :rep.ManagerId
            LIMIT  1
        ];
        if (policies.isEmpty()) return result; // no policy configured → pass
        Expense_Policy__c policy = policies[0];

        // ── 2. Per-type cap check ─────────────────────────
        Decimal typeCap = getCapForType(policy, expenseType);
        if (typeCap != null && typeCap > 0) {
            if (amount > typeCap * BLOCK_MULTIPLIER) {
                String fmt = formatCurrency(typeCap);
                String fmtHard = formatCurrency(typeCap * BLOCK_MULTIPLIER);
                throw new AuraHandledException(
                    expenseType + ' expenses are capped at ' + fmt +
                    ' per claim. Your amount of ' + formatCurrency(amount) +
                    ' exceeds the hard limit of ' + fmtHard + ' (150% of cap). Please reduce the amount.'
                );
            }
            if (amount > typeCap) {
                result.typeBreach      = true;
                result.capAtTime       = typeCap;
                result.breachAmount    = amount - typeCap;
            }
        }

        // ── 3. Monthly allowance check ────────────────────
        Date   parsed   = Date.valueOf(expenseDate);
        String monthKey = parsed.year() + '-' + String.valueOf(parsed.month()).leftPad(2, '0');

        List<Rep_Monthly_Allowance__c> allowances = [
            SELECT Allowance_Amount__c
            FROM   Rep_Monthly_Allowance__c
            WHERE  Sales_Rep__c  = :userId
            AND    Month_Year__c = :monthKey
            LIMIT  1
        ];

        if (!allowances.isEmpty()) {
            Decimal allowance = allowances[0].Allowance_Amount__c;

            // Sum existing spend this month (exclude the expense being edited)
            AggregateResult[] agg = [
                SELECT SUM(Amount__c) total
                FROM   Expense__c
                WHERE  Sales_Rep__c     = :userId
                AND    Expense_Date__c  >= :Date.newInstance(parsed.year(), parsed.month(), 1)
                AND    Expense_Date__c  <  :Date.newInstance(parsed.year(), parsed.month(), 1).addMonths(1)
                AND    Status__c       != 'Draft'
                AND    Id              != :expenseId
            ];
            Decimal usedSoFar = (agg[0].get('total') != null)
                ? (Decimal) agg[0].get('total') : 0;

            Decimal projectedTotal = usedSoFar + amount;

            if (projectedTotal > allowance * BLOCK_MULTIPLIER) {
                throw new AuraHandledException(
                    'Adding this expense would bring your ' + monthKey +
                    ' total to ' + formatCurrency(projectedTotal) +
                    ', which exceeds 150% of your monthly allowance of ' + formatCurrency(allowance) +
                    '. Please contact your manager.'
                );
            }
            if (projectedTotal > allowance) {
                result.allowanceBreach     = true;
                result.allowanceAtTime     = allowance;
                result.allowanceUsedAtTime = usedSoFar;
            }
        }

        // ── 4. Consolidate result ─────────────────────────
        if (result.typeBreach || result.allowanceBreach) {
            result.hasBreach = true;

            if      (result.typeBreach && result.allowanceBreach) result.breachType = 'Both';
            else if (result.typeBreach)                           result.breachType = 'Type Cap';
            else                                                  result.breachType = 'Monthly Allowance';

            result.warningMessage = buildWarning(result, expenseType);
        }

        return result;
    }

    // ─────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────

    private static Decimal getCapForType(Expense_Policy__c p, String expenseType) {
        if (expenseType == 'Travel')                       return p.Travel_Cap__c;
        if (expenseType == 'Food & Beverages')             return p.Food_Cap__c;
        if (expenseType == 'Market Execution Expenses')    return p.Market_Execution_Cap__c;
        if (expenseType == 'Communications Expenses')      return p.Communications_Cap__c;
        if (expenseType == 'Miscellaneous Expenses')       return p.Miscellaneous_Cap__c;
        if (expenseType == 'Other')                        return p.Other_Cap__c;
        return null;
    }

    private static String buildWarning(PolicyCheckResult r, String expenseType) {
        List<String> parts = new List<String>();
        if (r.typeBreach) {
            parts.add(expenseType + ' cap is ' + formatCurrency(r.capAtTime) +
                      '. You are over by ' + formatCurrency(r.breachAmount) + '.');
        }
        if (r.allowanceBreach) {
            Decimal remaining = r.allowanceAtTime - r.allowanceUsedAtTime;
            parts.add('Monthly allowance of ' + formatCurrency(r.allowanceAtTime) +
                      ': ' + formatCurrency(remaining) + ' remaining before this expense.');
        }
        return String.join(parts, ' ') +
               ' This expense has been saved and flagged for your manager\'s attention.';
    }

    private static String formatCurrency(Decimal val) {
        if (val == null) return '₹0';
        return '₹' + val.setScale(0).format();
    }
}