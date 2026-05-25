codeunit 72032 "DOPSWHS Telemetry"
{
    Access = Public;

    procedure Log(Category: Text; Message: Text; Verbosity: Verbosity; CustomDimensions: Dictionary of [Text, Text])
    var
        EventId: Text;
    begin
        EventId := EnsureCategoryPrefix(Category);
        Session.LogMessage(EventId, Message, Verbosity, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, CustomDimensions);
    end;

    procedure LogInfo(Category: Text; Message: Text)
    var
        CustomDimensions: Dictionary of [Text, Text];
    begin
        Log(Category, Message, Verbosity::Normal, CustomDimensions);
    end;

    local procedure EnsureCategoryPrefix(Category: Text): Text
    begin
        if CopyStr(Category, 1, 7) = 'AdvWMS-' then
            exit(Category);

        exit('AdvWMS-' + Category);
    end;
}

