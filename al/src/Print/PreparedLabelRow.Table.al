/// Company-owned label snapshots. Customer product/bin data stays in BC, outside public APKs.
table 72200 "DOPSWHS Prepared Label Row"
{
    DataClassification = CustomerContent;
    Caption = 'Prepared Label Row';
    fields
    {
        field(1; "List Code"; Code[20]) { }
        field(2; "Line No."; Integer) { }
        field(3; "Item No."; Code[20]) { }
        field(4; Description; Text[100]) { }
        field(5; "Bin Code"; Code[20]) { }
        field(6; "Source Date"; Date) { }
    }
    keys
    {
        key(PK; "List Code", "Line No.") { Clustered = true; }
    }
}
