table 72010 "DOPSWHS LP Header"
{
    Caption = 'DOPSWHS LP Header';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS LP List";
    DrillDownPageId = "DOPSWHS LP List";

    fields
    {
        field(1; "No."; Code[20]) { Caption = 'No.'; DataClassification = CustomerContent; }
        field(10; "Location Code"; Code[10]) { Caption = 'Location Code'; DataClassification = CustomerContent; TableRelation = Location; }
        field(20; "Bin Code"; Code[20]) { Caption = 'Bin Code'; DataClassification = CustomerContent; TableRelation = Bin.Code where("Location Code" = field("Location Code")); }
        field(30; Status; Enum "DOPSWHS LP Status") { Caption = 'Status'; DataClassification = CustomerContent; }
        field(40; "Parent LP No."; Code[20]) { Caption = 'Parent LP No.'; DataClassification = CustomerContent; TableRelation = "DOPSWHS LP Header"; ValidateTableRelation = true; }
        field(50; "LP Template Code"; Code[20]) { Caption = 'LP Template Code'; DataClassification = CustomerContent; TableRelation = "DOPSWHS LP Template"; }
        field(60; SSCC; Code[18]) { Caption = 'SSCC'; DataClassification = CustomerContent; }
        field(70; "Assigned Document Type"; Enum "DOPSWHS Assigned Doc Type") { Caption = 'Assigned Document Type'; DataClassification = CustomerContent; }
        field(71; "Assigned Document No."; Code[20]) { Caption = 'Assigned Document No.'; DataClassification = CustomerContent; }
        field(80; "Built By User"; Code[50]) { Caption = 'Built By User'; DataClassification = CustomerContent; Editable = false; }
        field(81; "Built DateTime"; DateTime) { Caption = 'Built DateTime'; DataClassification = CustomerContent; Editable = false; }
        field(82; "Last Modified DateTime"; DateTime) { Caption = 'Last Modified DateTime'; DataClassification = CustomerContent; Editable = false; }
        field(90; "Weight kg"; Decimal)
        {
            Caption = 'Weight kg';
            FieldClass = FlowField;
            CalcFormula = sum("DOPSWHS LP Line"."Line Weight kg" where("LP No." = field("No.")));
            Editable = false;
        }
        field(100; "Length cm"; Decimal) { Caption = 'Length cm'; DataClassification = CustomerContent; }
        field(101; "Width cm"; Decimal) { Caption = 'Width cm'; DataClassification = CustomerContent; }
        field(102; "Height cm"; Decimal) { Caption = 'Height cm'; DataClassification = CustomerContent; }
        field(110; Notes; Text[250]) { Caption = 'Notes'; DataClassification = CustomerContent; }
        field(120; "Line Count"; Integer)
        {
            Caption = 'Line Count';
            FieldClass = FlowField;
            CalcFormula = count("DOPSWHS LP Line" where("LP No." = field("No.")));
            Editable = false;
        }
        field(121; "Total Quantity"; Decimal)
        {
            Caption = 'Total Quantity';
            FieldClass = FlowField;
            CalcFormula = sum("DOPSWHS LP Line".Quantity where("LP No." = field("No.")));
            Editable = false;
        }
        field(122; "Planned Quantity"; Decimal)
        {
            Caption = 'Planned Quantity';
            DataClassification = CustomerContent;
            MinValue = 0;
        }
        field(123; "Bulk Build Request ID"; Guid)
        {
            Caption = 'Bulk Build Request ID';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(124; "Bulk Source ILE No."; Integer)
        {
            Caption = 'Bulk Source Item Ledger Entry No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = "Item Ledger Entry"."Entry No.";
        }
        field(125; "Bulk Source Bin Code"; Code[20])
        {
            Caption = 'Bulk Source Bin Code';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(126; "Pending Receipt No."; Code[20])
        {
            Caption = 'Pending Warehouse Receipt No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = "Warehouse Receipt Header"."No.";
        }
        field(127; "Pending Receipt Line No."; Integer)
        {
            Caption = 'Pending Warehouse Receipt Line No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        // EMU/DKÇ (15 Eyl 2026): snapshot of the document the LP was filled
        // from. Plain fields on purpose: they survive deletion of the source
        // document and are what the label and packing list print.
        field(130; "Source Document Type"; Enum "DOPSWHS Assigned Doc Type")
        {
            Caption = 'Source Document Type';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(131; "Source Document No."; Code[20])
        {
            Caption = 'Source Document No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(132; "Partner Type"; Option)
        {
            Caption = 'Partner Type';
            OptionMembers = " ",Customer,Vendor,Location;
            OptionCaption = ' ,Müşteri,Tedarikçi,Lokasyon';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(133; "Partner No."; Code[20])
        {
            Caption = 'Customer/Vendor No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(134; "Partner Name"; Text[100])
        {
            Caption = 'Customer/Vendor Name';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(135; "Ship-to Code"; Code[10])
        {
            Caption = 'Ship-to Code';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(136; "Ship-to Name"; Text[100])
        {
            Caption = 'Ship-to Name';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(137; "Ship-to Address"; Text[100])
        {
            Caption = 'Ship-to Address';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(138; "Ship-to City"; Text[30])
        {
            Caption = 'Ship-to City';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(139; "Ship-to Post Code"; Code[20])
        {
            Caption = 'Ship-to Post Code';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(140; "Ship-to Country Code"; Code[10])
        {
            Caption = 'Ship-to Country/Region Code';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(141; "Shipment Method Code"; Code[10])
        {
            Caption = 'Shipment Method Code';
            DataClassification = CustomerContent;
            TableRelation = "Shipment Method";
        }
        field(142; "Shipping Agent Code"; Code[10])
        {
            Caption = 'Shipping Agent Code';
            DataClassification = CustomerContent;
            TableRelation = "Shipping Agent";
        }
        field(143; "Shipping Agent Service Code"; Code[10])
        {
            Caption = 'Shipping Agent Service Code';
            DataClassification = CustomerContent;
        }
        field(144; "External Document No."; Code[35])
        {
            Caption = 'External Document No.';
            DataClassification = CustomerContent;
        }
        field(145; "Container No."; Code[30])
        {
            Caption = 'Container No.';
            DataClassification = CustomerContent;
        }
        field(146; "Seal No."; Code[30])
        {
            Caption = 'Seal No.';
            DataClassification = CustomerContent;
        }
        field(147; "Source Document Date"; Date)
        {
            Caption = 'Source Document Date';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(148; "Tare Weight kg"; Decimal)
        {
            Caption = 'Tare Weight kg';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 3;
        }
    }

    keys
    {
        key(PK; "No.") { Clustered = true; }
        key(StatusLocation; Status, "Location Code") { }
        key(Parent; "Parent LP No.") { }
        key(SSCCKey; SSCC) { }
        key(AssignedDoc; "Assigned Document Type", "Assigned Document No.") { }
        key(BulkBuildRequest; "Bulk Build Request ID") { }
        key(PendingReceipt; "Pending Receipt No.", "Pending Receipt Line No.") { }
    }

    trigger OnInsert()
    var
        ExistingLP: Record "DOPSWHS LP Header";
        LPSeriesSetup: Codeunit "DOPSWHS LP Series Setup";
        NoSeries: Codeunit "No. Series";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        LPNoSeriesCode: Code[20];
        Attempts: Integer;
    begin
        if "No." = '' then begin
            LPNoSeriesCode := LPSeriesSetup.EnsureLpNoSeries();
            // A restored/copied company can contain LP records that are ahead
            // of the number series. Consume numbers until an unused LP is found.
            repeat
                "No." := NoSeries.GetNextNo(LPNoSeriesCode);
                Attempts += 1;
                if Attempts > 10000 then
                    Error(
                        '%1 numara serisinde kullanılabilir LP numarası bulunamadı. Numara serisinin son kullanılan değerini kontrol edin.',
                        LPNoSeriesCode);
            until not ExistingLP.Get("No.");
        end;
        "Built By User" := CopyStr(UserId(), 1, MaxStrLen("Built By User"));
        "Built DateTime" := CurrentDateTime();
        Telemetry.LogInfo('LP.Created', "No.");
    end;

    trigger OnModify()
    begin
        "Last Modified DateTime" := CurrentDateTime();
    end;

    trigger OnDelete()
    var
        LPLine: Record "DOPSWHS LP Line";
    begin
        if "Pending Receipt No." <> '' then
            Error('%1 LP''si %2 mal kabulünü bekliyor. Önce ilgili mal kabul belgesinden işlemi iptal edin.', "No.", "Pending Receipt No.");
        if not (Status in [Status::Open, Status::Unbuilt]) then
            Error('Yalnız açık veya bozulmuş LP silinebilir.');

        LPLine.SetRange("LP No.", "No.");
        if not LPLine.IsEmpty() then
            Error('%1 LP numarasının satırları bulunduğu için silinemez.', "No.");
    end;
}
