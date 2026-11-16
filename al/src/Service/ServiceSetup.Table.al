table 72100 "DOPSWHS Service Setup"
{
    DataClassification = CustomerContent;
    fields
    {
        field(1; "Primary Key"; Code[10]) { }
        field(2; Enabled; Boolean) { }
        field(3; "Hide Warehouse Modules"; Boolean) { }
        field(4; "Default Work Type Code"; Code[10]) { TableRelation = "Work Type"; }
        field(5; "Default Location Code"; Code[10]) { TableRelation = Location; }
        field(6; "Allow Terminal Posting"; Boolean) { InitValue = true; }
        field(7; "Require Signature"; Boolean) { }
        field(8; "Labor Rounding (Hours)"; Decimal) { InitValue = 0.25; MinValue = 0; }
    }
    keys { key(PK; "Primary Key") { Clustered = true; } }
    procedure GetSetup()
    begin
        if not Get('') then begin
            Init();
            Insert(true);
        end;
    end;
}
