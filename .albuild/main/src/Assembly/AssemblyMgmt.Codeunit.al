codeunit 72049 "DOPSWHS Assembly Mgmt"
{
    Access = Public;

    procedure PostAssembly(var AssemblyHeader: Record "Assembly Header")
    var
        AssemblyPost: Codeunit "Assembly-Post";
    begin
        AssemblyHeader.TestField(Status, AssemblyHeader.Status::Released);
        if AssemblyHeader."Assemble to Order" then
            LogTelemetry('AdvWMS.Assembly.AssembleToOrderTracked', AssemblyHeader."No.");

        AssemblyPost.Run(AssemblyHeader);
        LogTelemetry('AdvWMS.Assembly.Posted', AssemblyHeader."No.");
    end;

    local procedure LogTelemetry(EventName: Text; DocumentNo: Code[20])
    var
        Telemetry: Codeunit "DOPSWHS Telemetry";
    begin
        Telemetry.LogInfo(EventName, DocumentNo);
    end;
}
