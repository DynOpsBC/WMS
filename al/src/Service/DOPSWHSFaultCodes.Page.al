page 72005 "DOPSWHS Fault Codes"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Fault Codes';
    PageType = List;
    SourceTable = "DOPSWHS Fault Code";
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
                field("Default Severity"; Rec."Default Severity") { ApplicationArea = All; }
            }
        }
    }
}
