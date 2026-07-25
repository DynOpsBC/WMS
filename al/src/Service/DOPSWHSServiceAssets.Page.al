page 72000 "DOPSWHS Service Assets"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Service Assets';
    PageType = List;
    SourceTable = "DOPSWHS Service Asset";
    UsageCategory = Lists;
    ApplicationArea = All;
    CardPageId = "DOPSWHS Service Asset Card";

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Fixed Asset No."; Rec."Fixed Asset No.") { ApplicationArea = All; }
                field("Warranty Expiry"; Rec."Warranty Expiry") { ApplicationArea = All; }
                field("Open Work Order Count"; Rec."Open Work Order Count") { ApplicationArea = All; }
                field(Blocked; Rec.Blocked) { ApplicationArea = All; }
            }
        }
    }
}
