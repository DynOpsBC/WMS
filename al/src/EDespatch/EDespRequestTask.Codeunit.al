codeunit 72457 "DOPSWHS EDesp Request Task"
{
    // Background task scheduled when a request is created inside a posting transaction.
    Access = Public;
    TableNo = "DOPSWHS EDesp Request";

    trigger OnRun()
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        if not Rec.Get(Rec."Entry No.") then
            exit;
        RequestMgt.EnsureDraft(Rec);
    end;
}
