page 72123 "DOPSWHS Svc Sales Orders API"
{
    // Open sales orders of a customer, for "which sales order is this service for" on the terminal (read-only).
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceSalesOrder';
    EntitySetName = 'serviceSalesOrders';
    SourceTable = "Sales Header";
    SourceTableView = where("Document Type" = const(Order));
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(no; Rec."No.") { Caption = 'no'; }
                field(customerNo; Rec."Sell-to Customer No.") { Caption = 'customerNo'; }
                field(customerName; Rec."Sell-to Customer Name") { Caption = 'customerName'; }
                field(orderDate; Rec."Order Date") { Caption = 'orderDate'; }
                field(externalDocumentNo; Rec."External Document No.") { Caption = 'externalDocumentNo'; }
                field(yourReference; Rec."Your Reference") { Caption = 'yourReference'; }
            }
        }
    }
}
