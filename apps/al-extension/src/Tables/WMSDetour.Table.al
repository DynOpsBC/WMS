table 50106 "WMS Detour"
{
    Caption = 'WMS Detour';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Detour Code"; Code[20]) { Caption = 'Detour Code'; NotBlank = true; }
        field(2; "Flow ID"; Code[50]) { Caption = 'Flow ID'; }
        field(3; "Step Tag"; Code[30]) { Caption = 'Step Tag'; }
        field(4; "Inner Flow ID"; Code[50]) { Caption = 'Inner Flow ID'; ToolTip = 'Sub-flow invoked when this detour is triggered.'; }
        field(5; "Label"; Text[100]) { Caption = 'Label'; }
        field(6; Enabled; Boolean) { Caption = 'Enabled'; }
        field(7; "Auto Trigger"; Boolean) { Caption = 'Auto Trigger'; }
    }
    keys { key(PK; "Detour Code") { Clustered = true; } }
}
