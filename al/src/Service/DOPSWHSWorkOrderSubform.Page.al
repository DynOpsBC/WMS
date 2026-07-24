page 72011 "DOPSWHS Work Order Subform"
{
    // NOT: Bu sayfa bu ortamda derlenmedi. Merge öncesi doğrulanmalı.
    Caption = 'Lines';
    PageType = ListPart;
    SourceTable = "DOPSWHS Work Order Line";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field(Type; Rec.Type) { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field(Posted; Rec.Posted) { ApplicationArea = All; Editable = false; }
                field(Notes; Rec.Notes) { ApplicationArea = All; }
            }
        }
    }
}
