table 72453 "DOPSWHS Pick Stock Candidate"
{
    TableType = Temporary;
    DataClassification = SystemMetadata;
    fields
    {
        field(1; "Entry No."; Integer) { }
        field(2; "Priority Date"; Date) { }
        field(3; "Posting Date"; Date) { }
        field(4; "Lot No."; Code[50]) { }
        field(5; "Expiration Date"; Date) { }
        field(6; "Remaining Quantity"; Decimal) { }
    }
    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Priority; "Priority Date", "Posting Date", "Entry No.") { }
    }
}
