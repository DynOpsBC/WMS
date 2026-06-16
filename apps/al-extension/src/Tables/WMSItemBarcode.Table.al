table 50029009 "WMS Item Barcode"
{
    Caption = 'WMS Item Barcode';
    DataClassification = CustomerContent;

    fields
    {
        field(1; Barcode; Code[40]) { Caption = 'Barcode'; NotBlank = true; }
        field(2; "Item No."; Code[20]) { Caption = 'Item No.'; TableRelation = Item; }
        field(3; "Variant Code"; Code[10]) { Caption = 'Variant Code'; TableRelation = "Item Variant".Code where("Item No." = field("Item No.")); }
        field(4; "Unit of Measure Code"; Code[10]) { Caption = 'Unit of Measure Code'; TableRelation = "Item Unit of Measure".Code where("Item No." = field("Item No.")); }
        field(5; "Quantity per UoM"; Decimal) { Caption = 'Quantity per UoM'; DecimalPlaces = 0 : 5; }
        field(6; Symbology; Enum "WMS Barcode Symbology") { Caption = 'Symbology'; }
        field(7; Primary; Boolean) { Caption = 'Primary'; }
    }
    keys
    {
        key(PK; Barcode) { Clustered = true; }
        key(Item; "Item No.", "Variant Code", "Unit of Measure Code") { }
    }
}
