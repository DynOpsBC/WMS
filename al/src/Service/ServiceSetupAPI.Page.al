page 72118 "DOPSWHS Service Setup API"
{
    PageType = API;
    APIPublisher = 'dynops';
    APIGroup = 'warehouse';
    APIVersion = 'v2.0';
    EntityName = 'serviceSetup';
    EntitySetName = 'serviceSetups';
    SourceTable = "DOPSWHS Service Setup";
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
                field(enabled; Rec."Enabled") { Caption = 'enabled'; }
                field(hideWarehouseModules; Rec."Hide Warehouse Modules") { Caption = 'hideWarehouseModules'; }
                field(allowTerminalPosting; Rec."Allow Terminal Posting") { Caption = 'allowTerminalPosting'; }
                field(requireSignature; Rec."Require Signature") { Caption = 'requireSignature'; }
                field(laborRoundingHours; Rec."Labor Rounding (Hours)") { Caption = 'laborRoundingHours'; }
                field(defaultWorkTypeCode; Rec."Default Work Type Code") { Caption = 'defaultWorkTypeCode'; }
                field(isTechnician; isTechnicianValue) { Caption = 'isTechnician'; }
                field(myResourceNo; myResourceNoValue) { Caption = 'myResourceNo'; }
                field(myResourceName; myResourceNameValue) { Caption = 'myResourceName'; }
                field(isDispatcher; isDispatcherValue) { Caption = 'isDispatcher'; }
                field(userName; userNameValue) { Caption = 'userName'; }
            }
        }
    }
    trigger OnOpenPage()
    var
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        // Technicians only read the setup; the codeunit creates it with indirect permission.
        Mgt.EnsureSetup();
    end;
    trigger OnAfterGetRecord()
    var
        Tech: Record "DOPSWHS Service Technician";
        Mgt: Codeunit "DOPSWHS Service Terminal Mgt";
    begin
        isTechnicianValue := Mgt.TryCurrentTechnician(Tech);
        Tech.CalcFields("Resource Name");
        myResourceNoValue := Tech."Resource No.";
        myResourceNameValue := Tech."Resource Name";
        isDispatcherValue := isTechnicianValue and Tech.Dispatcher;
        userNameValue := UserId();
    end;
    var
        isTechnicianValue: Boolean;
        myResourceNoValue: Code[20];
        myResourceNameValue: Text;
        isDispatcherValue: Boolean;
        userNameValue: Text;
}
