page 72316 "DOPSWHS Prod Pick Repair Lines"
{
    Caption = 'Kayıtlı Çekme Satırları';
    AdditionalSearchTerms = 'üretim çekmesi, kayıtlı çekme, LP onarım denetimi';
    PageType = List;
    SourceTable = "Registered Whse. Activity Line";
    SourceTableView = where("Activity Type" = const(Pick));
    ApplicationArea = All;
    UsageCategory = History;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("No."; Rec."No.") { ApplicationArea = All; Caption = 'Kayıtlı Çekme No.'; }
                field("Line No."; Rec."Line No.") { ApplicationArea = All; }
                field("Action Type"; Rec."Action Type") { ApplicationArea = All; Caption = 'Al/Yer'; }
                field("Whse. Activity No."; Rec."Whse. Activity No.") { ApplicationArea = All; }
                field("Source No."; Rec."Source No.") { ApplicationArea = All; Caption = 'Üretim Emri'; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; Caption = 'Kaynak/Hedef Göz'; }
                field("Qty. (Base)"; Rec."Qty. (Base)") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; }
            }
        }
    }
}
