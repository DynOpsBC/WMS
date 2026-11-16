page 72107 "DOPSWHS Service Lines API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceLine';
    EntitySetName = 'serviceLines';
    SourceTable = "Service Line";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    SourceTableView = where("Document Type" = const(Order));
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(documentNo; Rec."Document No.") { Caption = 'documentNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(serviceItemLineNo; Rec."Service Item Line No.") { Caption = 'serviceItemLineNo'; }
                field(no; Rec."No.") { Caption = 'no'; }
                field(description; Rec."Description") { Caption = 'description'; }
                field(quantity; Rec."Quantity") { Caption = 'quantity'; }
                field(unitOfMeasureCode; Rec."Unit of Measure Code") { Caption = 'unitOfMeasureCode'; }
                field(locationCode; Rec."Location Code") { Caption = 'locationCode'; }
                field(quantityShipped; Rec."Quantity Shipped") { Caption = 'quantityShipped'; }
                field(quantityConsumed; Rec."Quantity Consumed") { Caption = 'quantityConsumed'; }
                field(quantityInvoiced; Rec."Quantity Invoiced") { Caption = 'quantityInvoiced'; }
                field(workTypeCode; Rec."Work Type Code") { Caption = 'workTypeCode'; }
                field(type; typeValue) { Caption = 'type'; }
            }
        }
    }
    trigger OnAfterGetRecord()
    begin
        typeValue := Rec.Type.Names.Get(Rec.Type.Ordinals.IndexOf(Rec.Type.AsInteger()));
    end;
    var
        typeValue: Text;
}
