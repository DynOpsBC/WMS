page 72002 "DOPSWHS Service Contracts"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Service Contracts';
    PageType = List;
    SourceTable = "DOPSWHS Service Contract";
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "DOPSWHS Service Contract Card";

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field("Customer No."; Rec."Customer No.") { ApplicationArea = All; }
                field("Covered Asset No."; Rec."Covered Asset No.") { ApplicationArea = All; }
                field("SLA Code"; Rec."SLA Code") { ApplicationArea = All; }
                field("Start Date"; Rec."Start Date") { ApplicationArea = All; }
                field("End Date"; Rec."End Date") { ApplicationArea = All; }
                field("Billing Type"; Rec."Billing Type") { ApplicationArea = All; }
                field(Blocked; Rec.Blocked) { ApplicationArea = All; }
            }
        }
    }
}
