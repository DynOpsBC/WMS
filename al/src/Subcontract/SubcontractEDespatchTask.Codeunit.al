codeunit 72452 "DOPSWHS Subcontract EDesp Task"
{
    Access = Internal;
    TableNo = "DOPSWHS Subcontract EDesp Out";
    Permissions =
        tabledata "DOPSWHS Subcontract EDesp Out" = RIMD,
        tabledata "DOPSWHS Subcontract Dispatch" = RM,
        tabledata "Transfer Shipment Header" = RM;

    trigger OnRun()
    var
        EDespatchMgmt: Codeunit "DOPSWHS Subcontract EDesp Mgt";
    begin
        if Rec."Entry No." <> 0 then
            EDespatchMgmt.Submit(Rec."Entry No.");
    end;
}
