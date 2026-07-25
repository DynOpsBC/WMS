page 72004 "DOPSWHS Service SLAs"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Service SLAs';
    PageType = List;
    SourceTable = "DOPSWHS Service SLA";
    UsageCategory = Lists;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(Code; Rec.Code) { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field(Priority; Rec.Priority) { ApplicationArea = All; }
                field("Response Time (Hours)"; Rec."Response Time (Hours)") { ApplicationArea = All; }
                field("Resolution Time (Hours)"; Rec."Resolution Time (Hours)") { ApplicationArea = All; }
                field("Repeat Fault Window (Days)"; Rec."Repeat Fault Window (Days)") { ApplicationArea = All; }
            }
        }
    }
}
