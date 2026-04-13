public with sharing class OrderMonthlyPerformanceRollup {
    public static void handle(List<Order> newList, List<Order> oldList) {
        Set<String> impactedKeys = new Set<String>();
        Set<Id> userIds = new Set<Id>();
        Set<Date> monthStarts = new Set<Date>();

        addImpacted(newList, impactedKeys, userIds, monthStarts);
        addImpacted(oldList, impactedKeys, userIds, monthStarts);

        if (impactedKeys.isEmpty()) return;

        Date minStart = null;
        Date maxStart = null;
        for (Date d : monthStarts) {
            if (minStart == null || d < minStart) minStart = d;
            if (maxStart == null || d > maxStart) maxStart = d;
        }
        Date maxEndExclusive = maxStart.addMonths(1);

        List<AggregateResult> sums = [
            SELECT CreatedById creator,
                   CALENDAR_YEAR(CreatedDate) yr,
                   CALENDAR_MONTH(CreatedDate) mo,
                   SUM(TotalAmount) total
            FROM Order
            WHERE Status = 'Activated'
            AND CreatedById IN :userIds
            AND CreatedDate >= :minStart
            AND CreatedDate < :maxEndExclusive
            GROUP BY CreatedById, CALENDAR_YEAR(CreatedDate), CALENDAR_MONTH(CreatedDate)
        ];

        Map<String, Decimal> sumByKey = new Map<String, Decimal>();
        for (AggregateResult ar : sums) {
            Id creator = (Id) ar.get('creator');
            Integer yr = (Integer) ar.get('yr');
            Integer mo = (Integer) ar.get('mo');
            Date monthStart = Date.newInstance(yr, mo, 1);
            sumByKey.put(keyFor(creator, monthStart), (Decimal) ar.get('total'));
        }

        Map<String, Monthly_Performance__c> existingByKey = new Map<String, Monthly_Performance__c>();
        for (Monthly_Performance__c mp : [
            SELECT Id, Sales_Rep__c, Month_Year__c, Actual_Sales__c
            FROM Monthly_Performance__c
            WHERE Sales_Rep__c IN :userIds
            AND Month_Year__c >= :minStart
            AND Month_Year__c < :maxEndExclusive
        ]) {
            existingByKey.put(keyFor(mp.Sales_Rep__c, mp.Month_Year__c), mp);
        }

        List<Monthly_Performance__c> toUpdate = new List<Monthly_Performance__c>();
        List<Monthly_Performance__c> toInsert = new List<Monthly_Performance__c>();

        for (String key : impactedKeys) {
            Decimal sum = sumByKey.containsKey(key) ? sumByKey.get(key) : 0;
            Monthly_Performance__c existing = existingByKey.get(key);
            if (existing != null) {
                if (existing.Actual_Sales__c != sum) {
                    existing.Actual_Sales__c = sum;
                    toUpdate.add(existing);
                }
            } else if (sum > 0) {
                Monthly_Performance__c mp = new Monthly_Performance__c();
                List<String> parts = key.split('\\|');
                mp.Sales_Rep__c = (Id) parts[0];
                mp.Month_Year__c = Date.valueOf(parts[1]);
                mp.Actual_Sales__c = sum;
                toInsert.add(mp);
            }
        }

        if (!toUpdate.isEmpty()) update toUpdate;
        if (!toInsert.isEmpty()) insert toInsert;
    }

    private static void addImpacted(
        List<Order> orders,
        Set<String> impactedKeys,
        Set<Id> userIds,
        Set<Date> monthStarts
    ) {
        if (orders == null) return;
        for (Order o : orders) {
            if (o.CreatedById == null || o.CreatedDate == null) continue;
            Date monthStart = Date.newInstance(o.CreatedDate.year(), o.CreatedDate.month(), 1);
            String key = keyFor(o.CreatedById, monthStart);
            impactedKeys.add(key);
            userIds.add(o.CreatedById);
            monthStarts.add(monthStart);
        }
    }

    private static String keyFor(Id userId, Date monthStart) {
        return String.valueOf(userId) + '|' + String.valueOf(monthStart);
    }
}