page 72110 "DOPSWHS Svc Comments API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceComment';
    EntitySetName = 'serviceComments';
    SourceTable = "Service Comment Line";
    ODataKeyFields = SystemId;
    DelayedInsert = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;
    Editable = false;
    ApplicationArea = All;
    SourceTableView = where("Table Name" = const("Service Header"), "Table Subtype" = const("1"));
    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(id; Rec.SystemId) { Caption = 'id'; }
                field(no; Rec."No.") { Caption = 'no'; }
                field(tableLineNo; Rec."Table Line No.") { Caption = 'tableLineNo'; }
                field(lineNo; Rec."Line No.") { Caption = 'lineNo'; }
                field(date; Rec."Date") { Caption = 'date'; }
                field(comment; Rec."Comment") { Caption = 'comment'; }
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
