table 50112 "WMS Wave"
{
    Caption = 'WMS Wave';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Wave No."; Code[20]) { Caption = 'Wave No.'; NotBlank = true; }
        field(2; "Location Code"; Code[10]) { Caption = 'Location Code'; TableRelation = Location; }
        field(3; "Planned Release"; DateTime) { Caption = 'Planned Release'; }
        field(4; "Released At"; DateTime) { Caption = 'Released At'; }
        field(5; Status; Enum "WMS Wave Status") { Caption = 'Status'; }
        field(6; "Pick Group Method"; Enum "WMS Pick Grouping") { Caption = 'Pick Group Method'; }
    }
    keys { key(PK; "Wave No.") { Clustered = true; } }
}
