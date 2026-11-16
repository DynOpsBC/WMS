page 72111 "DOPSWHS Svc Repair Status API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceRepairStatus';
    EntitySetName = 'serviceRepairStatuses';
    SourceTable = "Repair Status";
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
                field(code; Rec."Code") { Caption = 'code'; }
                field(description; Rec."Description") { Caption = 'description'; }
                field(initial; Rec."Initial") { Caption = 'initial'; }
                field(inProcess; Rec."In Process") { Caption = 'inProcess'; }
                field(finished; Rec."Finished") { Caption = 'finished'; }
                field(partlyServiced; Rec."Partly Serviced") { Caption = 'partlyServiced'; }
                field(referred; Rec."Referred") { Caption = 'referred'; }
                field(sparePartOrdered; Rec."Spare Part Ordered") { Caption = 'sparePartOrdered'; }
                field(waitingForCustomer; Rec."Waiting for Customer") { Caption = 'waitingForCustomer'; }
                field(serviceOrderStatus; statusValue) { Caption = 'serviceOrderStatus'; }
                field(serviceOrderStatusText; statusValue) { Caption = 'serviceOrderStatusText'; }
            }
        }
    }
    trigger OnAfterGetRecord()
    begin
        statusValue := Rec."Service Order Status".Names.Get(Rec."Service Order Status".Ordinals.IndexOf(Rec."Service Order Status".AsInteger()));
    end;
    var
        statusValue: Text;
}
