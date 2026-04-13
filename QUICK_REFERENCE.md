# Salesforce Field Sales Platform - Quick Reference Guide

## APEX CONTROLLERS AT A GLANCE

### 1. BeatPlanController
```
Purpose: Weekly territory planning & visit scheduling
Main Method: getWeeklyVisits(Date)
Returns: WeekData {stats, visits[]}
Key Feature: Approval workflow for planned visits
```

### 2. CreateCaseController
```
Purpose: Support case creation with validation
Main Method: getPicklistMetadata(), createCase(Map)
Returns: PicklistMetadata, Case ID
Key Feature: Multi-field validation, file attachment
```

### 3. OrdersByUserController
```
Purpose: Order history & filtering by user/status
Main Method: getOrdersByActivatedByUser(), getOrderDetail()
Returns: OrderWrapper[], OrderDetailWrapper
Key Feature: Status filtering, product breakdown
```

### 4. Outlet360Controller
```
Purpose: 360-degree customer account view
Main Method: getOutlet360Summary(Id, String)
Returns: Outlet360Response {revenue, payments, orders, cases}
Key Feature: Related list aggregation, payment scores
```

### 5. PlaceOrderController
```
Purpose: Multi-step order placement workflow
Main Method: getProductsByDistributor(), placeOrder()
Returns: ProductOrderWrapper[], Order ID
Key Feature: Dynamic scheme application, inventory check
```

### 6. VisitController
```
Purpose: Daily visit execution & performance tracking
Main Method: startDay(), checkInVisit(), getDashboardSnapshot()
Returns: Day_Attendance__c, Visit record, DashboardSnapshot
Key Feature: GPS capture, photo/note management, ratings
```

---

## LWC COMPONENTS ORGANIZED BY TIER

### TIER 1: PRIMARY EXPERIENCES (Must Know)

| Component | Purpose | Key Actions | Related Apex |
|-----------|---------|------------|-------------|
| **r_fieldDayHome** | Daily dashboard landing page | Start day, select beat, view metrics | VisitController |
| **visitDetail** | Visit execution & documentation | Check-in, photos, notes, rating, orders | VisitController, Outlet360Controller |
| **beatPlanWeekly** | Weekly planning calendar | Add/edit visits, drag reorder, approve | BeatPlanController |
| **placeOrder** | Multi-step order creation | Product selection, scheme, payment | PlaceOrderController |
| **outlet360Details** | Customer 360 dashboard | View revenue, orders, cases, contacts | Outlet360Controller |
| **expenseList** | Expense tracking | Add/edit/submit, group by date | ExpenseController |

### TIER 2: OPERATIONAL COMPONENTS

| Component | Purpose |
|-----------|---------|
| createCaseModal | Case creation from order context |
| ordersByUser | Order history view |
| accountRecordHub | Dealer/Franchise directory |
| managerExpenseQueue | Expense approval (Manager) |
| beatVisitPlanner | Detailed beat planning |
| viewSchemes | Display active discount schemes |

### TIER 3: UTILITY COMPONENTS

- `startDay` - GPS day initialization
- `navigationButtons` - Page navigation
- `paymentMethod` - Payment selection
- `salesProgressBar` - Target progress display
- `serviceConsoleCaseTimer` - SLA tracking
- `spotterEmbed` - 3D product visualization
- Plus 20+ display and supporting components

---

## DAILY WORKFLOW CHECKLIST

**Morning**:
- [ ] Open `r_fieldDayHome`
- [ ] Review dashboard (target vs current)
- [ ] Click "Start Day" and capture GPS
- [ ] Select beat from dropdown

**Visit Execution (Repeat for each)**:
- [ ] Click visit from list
- [ ] `visitDetail` opens
- [ ] Check-in (captures time + GPS)
- [ ] Upload photos if needed
- [ ] Add meeting notes
- [ ] Take order → `placeOrder` modal
- [ ] Create case if issue found → `createCaseModal`
- [ ] Rate visit (1-5 stars)
- [ ] Check-out (captures time + GPS)

**End of Day**:
- [ ] Open `expenseList`
- [ ] Add daily expenses
- [ ] Submit daily report
- [ ] Click "End Day"

---

## DATA STRUCTURES QUICK REFERENCE

### VisitWrapper (Individual Visit)
```
id, name, beatId, beatName, outletId, outletName
visitStatus: "Planned" | "In Progress" | "Completed" | "Missed"
approvalStatus: "Planned" | "Pending Approval" | "Approved" | "Rejected"
visitDate, plannedStartTime, plannedEndTime
checkInTime, checkOutTime, sequence, dayOfWeek
colorClass (visual status), missedReason, missedRemarks
```

### WeekStats (Weekly Summary)
```
totalVisits, completed, pending, missed
weekLabel, beatId, beatName, beatStatus
beatStartDate, beatEndDate
```

### OrderWrapper (Order Summary)
```
orderId, orderNumber, status, orderType
productCount, totalAmount, orderDate
shippingStreet, shippingCity, shippingState, shippingPostalCode, shippingCountry
dealerId, dealerName, activatedByName
products: List<ProductWrapper>
```

### ProductWrapper (Line Item)
```
productId, productName, quantity, unitPrice
totalPrice = quantity × unitPrice
```

### Outlet360Response (Customer 360)
```
HEADER: outletName, outletCode, outletStatus, outletPhone, outletAddress

REVENUE:
pastRevenue, ordersCount, ordersCount, invoicesCount

RECORDS:
recentOrders[], allOrders[], orderProducts[], cases[], recentInvoices[]

PAYMENT:
pendingAmount, overdueCount, lastPaymentDate, paymentRating

ENGAGEMENT:
visitRating, ownerName, ownerEmail
```

### DashboardSnapshot (Daily KPIs)
```
monthLabel, salesTargetName, targetAmount
actualSales, achievementPercent (vs target)
completedVisits, plannedVisits, visitCompletionPercent
performanceRating, incentiveAmount (5% of sales)
```

---

## FEATURE MATRIX

| Feature | Component | Apex Dependency | User Type |
|---------|-----------|-----------------|-----------|
| Day Initialization | startDay | VisitController.startDay() | Rep |
| Weekly Planning | beatPlanWeekly | BeatPlanController | Rep |
| Visit Execution | visitDetail | VisitController | Rep |
| Photo Upload | visitDetail | VisitController | Rep |
| Place Order | placeOrder | PlaceOrderController | Rep |
| Create Case | createCaseModal | CreateCaseController | Rep |
| View Order History | ordersByUser | OrdersByUserController | Rep |
| Customer 360 | outlet360Details | Outlet360Controller | Rep |
| Track Expenses | expenseList | ExpenseController | Rep |
| Approve Expenses | managerExpenseQueue | ManagerExpenseController | Manager |
| Browse Accounts | accountRecordHub | AccountRecordHubController | Rep/Manager |

---

## COMMON BUSINESS SCENARIOS

### Scenario 1: Rep Discovers Product Issue During Visit
```
Step 1: Rep checks inventory at outlet
Step 2: Outlet360Details shows product history
Step 3: Rep creates case via createCaseModal with photo
Step 4: Support team notified
Step 5: Manager can see case count in Outlet360 dashboard
```

### Scenario 2: Rep Needs to Place Order with Discount
```
Step 1: Rep clicks "New Order" in visitDetail
Step 2: placeOrder modal opens
Step 3: selects products (e.g., 15 units)
Step 4: PlaceOrderController.getSchemesByThresholdQuantity() returns 5% discount
Step 5: Rep accepts, submits order
Result: Order created with discount applied automatically
```

### Scenario 3: Manager Reviews Daily Performance
```
Step 1: Manager checks managerExpenseQueue
Step 2: Reviews pending expense reports with breach flagging
Step 3: Approval status updated in real-time
Step 4: Rep receives notification
```

### Scenario 4: Rep Plans Week Ahead
```
Step 1: Opens beatPlanWeekly on Saturday
Step 2: Sees calendar grid MON-SUN
Step 3: Adds 35 visits across week
Step 4: Drags to reorder within each day
Step 5: Sets all to status "Planned"
Step 6: Clicks "Submit for Approval"
Result: Manager reviews, approves; visits locked
```

---

## NAVIGATION MAP

```
LOGIN
  ↓
r_fieldDayHome (Dashboard)
  ├→ Start Day (startDay)
  ├→ Select Beat (dropdown)
  ├→ View Schemes (viewSchemes modal)
  ├→ View New Products (newProductsCardView modal)
  ├→ View Beat Plan (beatPlanWeekly modal)
  │   ├→ Add/Edit Visit (modal)
  │   └→ Submit for Approval
  │
  └→ Click Visit → visitDetail
     ├→ Check-in/Check-out (GPS capture)
     ├→ Upload Photos (gallery)
     ├→ Add Meeting Notes (modal)
     ├→ Manage Tasks
     ├→ Place Order → placeOrder (multi-step)
     │   ├→ Franchise selection
     │   ├→ Distributor selection
     │   ├→ Product grid (placeOrder)
     │   ├→ Scheme selection (auto-apply)
     │   ├→ Shipping address
     │   ├→ Payment method (paymentMethod)
     │   └→ Submit order
     │
     ├→ Create Case → createCaseModal
     │   ├→ Form validation
     │   ├→ File attachment
     │   └→ Submit
     │
     ├→ View Customer (outlet360Details)
     │   ├→ Revenue metrics
     │   ├→ Contacts (quick dial/email)
     │   ├→ Orders (ordersByUser)
     │   ├→ Cases
     │   └→ Payment history
     │
     ├→ Rate & Feedback
     └→ End Visit

SIDE FLOWS:
  ├→ expenseList (Daily tracking)
  │   ├→ Add Expense (addExpenseModal)
  │   ├→ View Receipt
  │   └→ Submit Daily Report
  │
  └→ accountRecordHub (Browse accounts)
      └→ View Account Details
```

---

## APEX QUERYES PATTERNS

### Visit Query (Example from BeatPlanController)
```apex
List<Visit__c> records = [
  SELECT  Id, Name, Visit_Status__c, 
          Outlet1__r.Name, Outlet1__r.Phone,
          Planned_Start_Time__c, Planned_End_Time__c,
          Check_In_Time__c, Check_Out_Time__c
  FROM    Visit__c
  WHERE   Beat__c IN :beatIds
  AND     Visit_Date__c BETWEEN :weekStart AND :weekEnd
  ORDER BY Sequence__c ASC
  LIMIT   500
];
```

### Performance Dashboard Query
```apex
List<Monthly_Performance__c> perf = [
  SELECT Actual_Sales__c, Achievement__c,
         Completed_Visits__c, Planned_Visits__c,
         Visit_Completion__c, Performance_Rating__c
  FROM   Monthly_Performance__c
  WHERE  Sales_Rep__c = :userId
  AND    CALENDAR_MONTH(Month_Year__c) = :monthNum
  AND    CALENDAR_YEAR(Month_Year__c) = :yearNum
  LIMIT  1
];
```

---

## KEY METRICS & FORMULAS

### Achievement %
```
Achievement % = (Actual_Sales / Target_Amount) × 100
Example: Rs 35,000 / Rs 50,000 = 70%
```

### Visit Completion %
```
Visit Completion % = (Completed_Visits / Planned_Visits) × 100
Example: 8 / 10 = 80%
```

### Incentive Calculation
```
Incentive Amount = Actual_Sales × 0.05 (5%)
Example: Rs 35,000 × 0.05 = Rs 1,750
```

### Discount from Scheme
```
Final Price = (Unit Price × Qty) × (1 - Discount%)
Example: (100 × 10) × (1 - 0.05) = Rs 950 (5% discount applied)
```

### Payment Rating
```
Average of Payment_Score__c from all Payment records
Range: 1-10
Interpretation: 8.5+ = Healthy, 5-7 = Monitor, <5 = Risk
```

---

## COMMON APEX METHODS REFERENCE

```apex
// Day Management
VisitController.startDay(lat, lon)           → Id (Day_Attendance)
VisitController.endDay(lat, lon)             → Day_Attendance
VisitController.getTodayAttendance()         → Day_Attendance

// Visit Data
VisitController.getDayTimeline(Date)         → List<Visit__c>
VisitController.getVisitDetail(Id)           → Visit__c (expanded)
VisitController.checkInVisit(Id, lat, lon)   → Timestamp
VisitController.checkOutVisit(Id, lat, lon)  → Timestamp

// Documentation
VisitController.uploadVisitPhoto(Id, file)   → ContentDocument Id
VisitController.saveMeetingNotes(Id, text)   → Note record
VisitController.saveRatingAndFeedback()      → Rating record

// Performance
VisitController.getDashboardSnapshot(Date)   → DashboardSnapshot {sales, visits, incentive}
VisitController.getTodayBeats(Date)          → List<Beat__c>

// Ordering
PlaceOrderController.getProductsByDistributor(Id)    → List<ProductOrderWrapper>
PlaceOrderController.getSchemesByThresholdQuantity(Qty) → List<SchemeOption>
PlaceOrderController.placeOrder(Map)                 → Order Id

// Beat Planning
BeatPlanController.getWeeklyVisits(Date)     → WeekData {stats, visits}
BeatPlanController.createVisitsAndSubmitForApproval() → Result

// Customer View
Outlet360Controller.getOutlet360Summary(Id)  → Outlet360Response {revenue, orders, cases}

// Case Management
CreateCaseController.getPicklistMetadata()   → PicklistMetadata
CreateCaseController.createCase(Map)         → Case Id

// History
OrdersByUserController.getOrdersByActivatedByUser() → List<OrderWrapper>
OrdersByUserController.getOrderDetail(Id)    → OrderDetailWrapper
```

---

## PERFORMANCE TIPS

### For Field Representatives
- Start day immediately to ensure GPS trail
- Batch photos upload at day end (better bandwidth use)
- Use offline cache for expense entries
- Create cases before internet drops
- Link expenses to visits for analytics

### For Managers
- Review approval queue daily
- Use Outlet360 to identify at-risk accounts (payment rating <7)
- Check beat plan submissions by Friday
- Monitor rep performance from dashboards

### For Developers
- Use `cacheable=true` for read-only Apex methods
- Limit relationship scans to 60 (mobile optimization)
- Use pagination for large result sets (8-10 per page)
- Batch file uploads before submission
- Implement offline queue for connectivity outages

---

## TROUBLESHOOTING QUICK GUIDE

| Issue | Likely Cause | Fix |
|-------|--------------|-----|
| GPS not capturing | Location permission not granted | Grant location access in device settings |
| Photos not uploading | File >5MB or wrong format | Compress image or convert to jpg/png |
| Order won't submit | Missing required field (Type, Reason) | Verify all picklist fields are selected |
| Visit not showing in timeline | Beat not assigned to rep | Assign beat via BeatPlanController query |
| Case creation fails | Subject too short (<10 chars) | Lengthen subject to 10+ characters |
| Scheme not applying | Quantity below threshold | Increase qty to meet minimum (e.g., 10 units for 5% off) |
| Dashboard metrics not updating | Cacheable method still returning old data | Refresh page or wait for cache expiry |
| Expense status stuck | Report still in draft | Ensure all items are complete before batch submit |

---

## DOCUMENT VERSION CONTROL

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | Jan 2024 | Initial comprehensive analysis |
| 1.1 | Jan 2024 | Added quick reference & troubleshooting |

---

**For CV Documentation**: This platform demonstrates expertise in:
- ✅ Enterprise Apex development (6 major controllers)
- ✅ LWC component design & composition (48+ components)
- ✅ Complex data structures & SOL queries
- ✅ Mobile-first UX/UI for field operations
- ✅ Offline-first architecture thinking
- ✅ Real-time dashboard design
- ✅ Multi-user approval workflows
- ✅ GPS & location tracking integration

