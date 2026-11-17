page 72124 "DOPSWHS Svc Log API"
{
    // Service history shown on the terminal: the same log the office reads in Business Central (read-only).
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceLogEntry';
    EntitySetName = 'serviceLogEntries';
    SourceTable = "DOPSWHS Service Log Entry";
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
                field(entryNo; Rec."Entry No.") { Caption = 'entryNo'; }
                field(loggedAt; Rec."Logged At") { Caption = 'loggedAt'; }
                field(serviceOrderNo; Rec."Service Order No.") { Caption = 'serviceOrderNo'; }
                field(serviceItemLineNo; Rec."Service Item Line No.") { Caption = 'serviceItemLineNo'; }
                field(salesOrderNo; Rec."Sales Order No.") { Caption = 'salesOrderNo'; }
                field(technicianName; Rec."Technician Name") { Caption = 'technicianName'; }
                field(userName; Rec."User ID") { Caption = 'userName'; }
                field(entryType; entryTypeValue) { Caption = 'entryType'; }
                field(entryText; Rec."Entry Text") { Caption = 'entryText'; }
                field(fromTerminal; Rec."From Terminal") { Caption = 'fromTerminal'; }
            }
        }
    }
    trigger OnAfterGetRecord()
    begin
        entryTypeValue := Rec."Entry Type".Names.Get(Rec."Entry Type".Ordinals.IndexOf(Rec."Entry Type".AsInteger()));
    end;

    var
        entryTypeValue: Text;
}
