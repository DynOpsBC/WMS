page 72472 "DOPSWHS EDesp Request Lines"
{
    Caption = 'Lines';
    PageType = ListPart;
    ApplicationArea = All;
    SourceTable = "DOPSWHS EDesp Request Line";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(General)
            {
                field("Item No."; Rec."Item No.") { ApplicationArea = All; ToolTip = 'Specifies the item.'; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; ToolTip = 'Specifies the variant.'; }
                field(Description; Rec.Description) { ApplicationArea = All; ToolTip = 'Specifies the description.'; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; ToolTip = 'Specifies the quantity.'; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Specifies the unit of measure.'; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; ToolTip = 'Specifies the lot no.'; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; ToolTip = 'Specifies the serial no.'; }
                field("From Bin Code"; Rec."From Bin Code") { ApplicationArea = All; ToolTip = 'Specifies the source bin.'; }
                field("To Bin Code"; Rec."To Bin Code") { ApplicationArea = All; ToolTip = 'Specifies the target bin.'; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; ToolTip = 'Specifies the license plate.'; }
            }
        }
    }
}
