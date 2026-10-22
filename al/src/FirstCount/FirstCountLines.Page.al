page 72003 "DOPSWHS First Count Lines"
{
    Caption = 'İlk Sayım Satırları';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = None;
    SourceTable = "DOPSWHS First Count Line";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Count No."; Rec."Count No.") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; }
                field("Quantity (Base)"; Rec."Quantity (Base)") { ApplicationArea = All; }
                field("User ID"; Rec."User ID") { ApplicationArea = All; }
                field("Created DateTime"; Rec."Created DateTime") { ApplicationArea = All; }
            }
        }
    }
}
