codeunit 72456 "DOPSWHS EDesp Request Runner"
{
    // Runs one provider step of an e-despatch request in isolation: an error rolls back only this step.
    Access = Public;
    TableNo = "DOPSWHS EDesp Request";

    var
        Mode: Enum "DOPSWHS EDesp Run Mode";
        ModePayload: Text;

    trigger OnRun()
    var
        RequestMgt: Codeunit "DOPSWHS EDesp Request Mgt";
    begin
        RequestMgt.ExecuteMode(Rec, Mode, ModePayload);
    end;

    procedure SetMode(NewMode: Enum "DOPSWHS EDesp Run Mode"; Payload: Text)
    begin
        Mode := NewMode;
        ModePayload := Payload;
    end;
}
