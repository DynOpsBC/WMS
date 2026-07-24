page 72001 "DOPSWHS Service Asset Card"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Service Asset Card';
    PageType = Card;
    SourceTable = "DOPSWHS Service Asset";
    ApplicationArea = All;
    UsageCategory = None;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Fixed Asset No."; Rec."Fixed Asset No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Warranty Expiry"; Rec."Warranty Expiry") { ApplicationArea = All; }
                field("Open Work Order Count"; Rec."Open Work Order Count") { ApplicationArea = All; }
                field(Blocked; Rec.Blocked) { ApplicationArea = All; }
            }
            part(WorkOrders; "DOPSWHS Work Orders")
            {
                Caption = 'Work Orders';
                SubPageLink = "Asset No." = field("No.");
            }
            part(MaintenancePlans; "DOPSWHS Maintenance Plans")
            {
                Caption = 'Maintenance Plans';
                SubPageLink = "Asset No." = field("No.");
            }
        }
    }
}
