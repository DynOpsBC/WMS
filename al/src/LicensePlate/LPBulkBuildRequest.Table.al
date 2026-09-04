table 72008 "DOPSWHS LP Bulk Request"
{
    Caption = 'DOPSWHS LP Bulk Request';
    DataClassification = CustomerContent;

    fields
    {
        field(1; "Request ID"; Guid)
        {
            Caption = 'Request ID';
            DataClassification = SystemMetadata;
        }
        field(10; "Source ILE No."; Integer)
        {
            Caption = 'Source Item Ledger Entry No.';
            DataClassification = CustomerContent;
            TableRelation = "Item Ledger Entry"."Entry No.";
        }
        field(20; "Template Code"; Code[20])
        {
            Caption = 'LP Template Code';
            DataClassification = CustomerContent;
            TableRelation = "DOPSWHS LP Template".Code;
        }
        field(30; "Location Code"; Code[10])
        {
            Caption = 'Location Code';
            DataClassification = CustomerContent;
            TableRelation = Location.Code;
        }
        field(40; "Bin Code"; Code[20])
        {
            Caption = 'Bin Code (blank = automatic)';
            DataClassification = CustomerContent;
            TableRelation = Bin.Code where("Location Code" = field("Location Code"));
        }
        field(50; "LP Count"; Integer)
        {
            Caption = 'LP Count';
            DataClassification = CustomerContent;
            MinValue = 1;
        }
        field(60; "Quantity per LP"; Decimal)
        {
            Caption = 'Quantity per LP';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 5;
            MinValue = 0;
        }
        field(70; Completed; Boolean)
        {
            Caption = 'Completed';
            DataClassification = SystemMetadata;
        }
        field(80; "Created At"; DateTime)
        {
            Caption = 'Created At';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(81; "Created By"; Code[50])
        {
            Caption = 'Created By';
            DataClassification = EndUserIdentifiableInformation;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Request ID") { Clustered = true; }
    }

    trigger OnInsert()
    begin
        if IsNullGuid("Request ID") then
            Error('Toplu LP işlem kimliği zorunludur.');
        TestField("Source ILE No.");
        TestField("Template Code");
        TestField("Location Code");
        TestField("LP Count");
        if "Quantity per LP" <= 0 then
            Error('LP başına miktar sıfırdan büyük olmalıdır.');
        "Created At" := CurrentDateTime();
        "Created By" := CopyStr(UserId(), 1, MaxStrLen("Created By"));
    end;

    trigger OnModify()
    begin
        // The only legal transition is the same transaction marking a fully
        // created batch complete. Its identity and plan remain immutable.
        if xRec.Completed or (not Completed) or
           ("Request ID" <> xRec."Request ID") or
           ("Source ILE No." <> xRec."Source ILE No.") or
           ("Template Code" <> xRec."Template Code") or
           ("Location Code" <> xRec."Location Code") or
           ("Bin Code" <> xRec."Bin Code") or
           ("LP Count" <> xRec."LP Count") or
           ("Quantity per LP" <> xRec."Quantity per LP") or
           ("Created At" <> xRec."Created At") or
           ("Created By" <> xRec."Created By")
        then
            Error('Toplu LP işlem kaydı değiştirilemez.');
    end;

    trigger OnDelete()
    begin
        Error('Toplu LP işlem kaydı silinemez.');
    end;

    trigger OnRename()
    begin
        Error('Toplu LP işlem kaydı değiştirilemez.');
    end;
}
