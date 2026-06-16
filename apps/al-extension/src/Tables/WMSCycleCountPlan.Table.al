table 50029013 "WMS Cycle Count Plan"
{
    Caption = 'WMS Cycle Count Plan';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Plan No."; Code[20]) { Caption = 'Plan No.'; NotBlank = true; }
        field(2; Description; Text[100]) { Caption = 'Description'; }
        field(3; "Location Code"; Code[10]) { Caption = 'Location Code'; TableRelation = Location; }
        field(4; "Zone Filter"; Code[10]) { Caption = 'Zone Filter'; TableRelation = Zone.Code where("Location Code" = field("Location Code")); }
        field(5; "Bin Filter"; Code[20]) { Caption = 'Bin Filter'; }
        field(6; "Item Filter"; Code[20]) { Caption = 'Item Filter'; TableRelation = Item; }
        field(7; "Scheduled For"; Date) { Caption = 'Scheduled For'; }
        field(8; "Requires Supervisor"; Boolean) { Caption = 'Requires Supervisor'; }
        field(9; "Recount On Variance"; Boolean) { Caption = 'Recount On Variance'; }
        field(10; "Recount Times"; Integer) { Caption = 'Recount Times'; MinValue = 0; MaxValue = 5; }
        field(11; Status; Enum "WMS Count Plan Status") { Caption = 'Status'; }
    }
    keys { key(PK; "Plan No.") { Clustered = true; } }
}
