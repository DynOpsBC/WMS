table 72017 "DOPSWHS Count Sheet Line"
{
    Caption = 'Count Sheet Line';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Sheet No."; Code[20]) { Caption = 'Sheet No.'; DataClassification = CustomerContent; TableRelation = "DOPSWHS Count Sheet Header"; }
        field(2; "Line No."; Integer) { Caption = 'Line No.'; DataClassification = CustomerContent; }
        field(10; "Item No."; Code[20]) { Caption = 'Item No.'; DataClassification = CustomerContent; TableRelation = Item; }
        field(20; "Variant Code"; Code[10]) { Caption = 'Variant Code'; DataClassification = CustomerContent; TableRelation = "Item Variant".Code where("Item No." = field("Item No.")); }
        field(30; "Bin Code"; Code[20]) { Caption = 'Bin Code'; DataClassification = CustomerContent; TableRelation = Bin.Code; }
        field(40; "LP No."; Code[20]) { Caption = 'LP No.'; DataClassification = CustomerContent; TableRelation = "DOPSWHS LP Header"; }
        field(50; "System Qty"; Decimal)
        {
            Caption = 'System Qty';
            FieldClass = FlowField;
            CalcFormula = sum("Bin Content".Quantity where("Item No." = field("Item No."), "Variant Code" = field("Variant Code"), "Bin Code" = field("Bin Code")));
            Editable = false;
        }
        field(60; "Counted Qty 1"; Decimal) { Caption = 'Counted Qty 1'; DataClassification = CustomerContent; }
        field(70; "Counted Qty 2"; Decimal) { Caption = 'Counted Qty 2'; DataClassification = CustomerContent; }
        field(80; "Counted Qty 3"; Decimal) { Caption = 'Counted Qty 3'; DataClassification = CustomerContent; }
        field(90; Variance; Decimal) { Caption = 'Variance'; DataClassification = CustomerContent; Editable = false; }
        field(100; "Recount Required"; Boolean) { Caption = 'Recount Required'; DataClassification = CustomerContent; }
    }

    keys
    {
        key(PK; "Sheet No.", "Line No.") { Clustered = true; }
        key(ItemBin; "Item No.", "Variant Code", "Bin Code") { }
        key(Recount; "Recount Required") { }
    }
}
