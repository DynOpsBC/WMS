table 50108 "WMS Packing Policy"
{
    Caption = 'WMS Packing Policy';
    DataClassification = CustomerContent;

    fields
    {
        field(1; Code; Code[20]) { Caption = 'Code'; NotBlank = true; }
        field(2; Description; Text[100]) { Caption = 'Description'; }
        field(3; "Auto Create Container"; Boolean) { Caption = 'Auto Create Container'; }
        field(4; "Auto Close Container"; Boolean) { Caption = 'Auto Close Container'; }
        field(5; "Require Worker ID"; Boolean) { Caption = 'Require Worker ID'; ToolTip = 'WMA 2025 W1 parity: log worker on every container event.'; }
        field(6; "Capture Weight"; Boolean) { Caption = 'Capture Weight'; }
        field(7; "Capture Dimensions"; Boolean) { Caption = 'Capture Dimensions'; }
        field(8; "Default Container Type"; Code[20]) { Caption = 'Default Container Type'; }
    }
    keys { key(PK; Code) { Clustered = true; } }
}
