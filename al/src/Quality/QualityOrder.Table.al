table 72254 "DOPSWHS Quality Order"
{
    Caption = 'Quality Order';
    DataClassification = CustomerContent;
    Access = Public;
    LookupPageId = "DOPSWHS Quality Orders";
    DrillDownPageId = "DOPSWHS Quality Orders";

    fields
    {
        field(1; "No."; Code[20]) { Caption = 'No.'; DataClassification = CustomerContent; }
        field(10; "Source Type"; Option)
        {
            Caption = 'Source Type';
            DataClassification = CustomerContent;
            // Assembly (Kitoko, Kas 2026): appended; existing values keep their numbers.
            OptionMembers = Manual,Receipt,Production,Shipment,Return,Assembly;
            OptionCaption = 'Manual,Receipt,Production,Shipment,Return,Assembly';
        }
        field(11; "Source No."; Code[20]) { Caption = 'Source No.'; DataClassification = CustomerContent; }
        field(20; "Item No."; Code[20]) { Caption = 'Item No.'; DataClassification = CustomerContent; TableRelation = Item; }
        field(21; "Item Description"; Text[100]) { Caption = 'Item Description'; DataClassification = CustomerContent; }
        field(30; "Quantity"; Decimal) { Caption = 'Quantity'; DataClassification = CustomerContent; }
        field(31; "Sample Size"; Decimal) { Caption = 'Sample Size'; DataClassification = CustomerContent; }
        field(40; "Location Code"; Code[10]) { Caption = 'Location Code'; DataClassification = CustomerContent; TableRelation = Location; }
        field(41; "Bin Code"; Code[20]) { Caption = 'Bin Code'; DataClassification = CustomerContent; }
        field(42; "LP No."; Code[20]) { Caption = 'LP No.'; DataClassification = CustomerContent; }
        field(50; "Status"; Option)
        {
            Caption = 'Status';
            DataClassification = CustomerContent;
            OptionMembers = Open,InProgress,Passed,Failed,Closed;
            OptionCaption = 'Open,In Progress,Passed,Failed,Closed';
        }
        field(60; "Inspector"; Code[50]) { Caption = 'Inspector'; DataClassification = EndUserIdentifiableInformation; }
        field(61; "Inspected DateTime"; DateTime) { Caption = 'Inspected DateTime'; DataClassification = CustomerContent; }
        field(70; "Result Notes"; Text[250]) { Caption = 'Result Notes'; DataClassification = CustomerContent; }
        field(71; "Reject Reason"; Code[20]) { Caption = 'Reject Reason'; DataClassification = CustomerContent; }
        field(72; "Quarantine Bin"; Code[20]) { Caption = 'Quarantine Bin'; DataClassification = CustomerContent; }
        field(80; "Created DateTime"; DateTime) { Caption = 'Created DateTime'; DataClassification = CustomerContent; }
        field(81; "Due Date"; Date) { Caption = 'Due Date'; DataClassification = CustomerContent; }
        // KIT-009 / KIT-010 / INV-009 / INV-010 (Kitoko, Kas 2026): the order is
        // tied to the inspected stock (variant, lot/serial) and to the exact
        // source line, so receipt/assembly posting can be gated per line and the
        // lot can be held. "Source Table No." follows the warehouse convention
        // (39 = Purchase Line, 900 = Assembly Header, 901 = Assembly Line).
        field(90; "Variant Code"; Code[10])
        {
            Caption = 'Variant Code';
            DataClassification = CustomerContent;
            TableRelation = "Item Variant".Code where("Item No." = field("Item No."));
        }
        field(91; "Lot No."; Code[50])
        {
            Caption = 'Lot No.';
            DataClassification = CustomerContent;
        }
        field(92; "Serial No."; Code[50])
        {
            Caption = 'Serial No.';
            DataClassification = CustomerContent;
        }
        field(93; "Unit of Measure Code"; Code[10])
        {
            Caption = 'Unit of Measure Code';
            DataClassification = CustomerContent;
            TableRelation = "Item Unit of Measure".Code where("Item No." = field("Item No."));
        }
        field(100; "Source Table No."; Integer)
        {
            Caption = 'Source Table No.';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(101; "Source Subtype"; Integer)
        {
            Caption = 'Source Subtype';
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(102; "Source Line No."; Integer)
        {
            Caption = 'Source Line No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(103; "Whse. Document No."; Code[20])
        {
            Caption = 'Whse. Document No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(104; "Posted Document No."; Code[20])
        {
            // Set when a receipt/assembly posting used this inspection. A later
            // partial posting of the same line needs a new inspection.
            Caption = 'Posted Document No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(105; "Vendor No."; Code[20])
        {
            Caption = 'Vendor No.';
            DataClassification = CustomerContent;
            TableRelation = Vendor;
        }
        field(120; Decision; Enum "DOPSWHS Quality Decision")
        {
            Caption = 'Decision';
            DataClassification = CustomerContent;
        }
        field(121; "Decision Qty."; Decimal)
        {
            Caption = 'Decision Qty.';
            DataClassification = CustomerContent;
            DecimalPlaces = 0 : 5;
            MinValue = 0;
        }
        field(122; "Decision Reason Code"; Code[10])
        {
            Caption = 'Decision Reason Code';
            DataClassification = CustomerContent;
            TableRelation = "Reason Code";
        }
        field(123; "Decision Executed"; Boolean)
        {
            Caption = 'Decision Executed';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(124; "Decision Document No."; Code[20])
        {
            Caption = 'Decision Document No.';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(125; "Decision By"; Code[50])
        {
            Caption = 'Decision By';
            DataClassification = EndUserIdentifiableInformation;
            Editable = false;
        }
        field(126; "Decision DateTime"; DateTime)
        {
            Caption = 'Decision DateTime';
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(127; "Re-inspection Order No."; Code[20])
        {
            Caption = 'Re-inspection Order No.';
            DataClassification = CustomerContent;
            Editable = false;
            TableRelation = "DOPSWHS Quality Order";
        }
    }

    keys
    {
        key(PK; "No.") { Clustered = true; }
        key(Status; "Status") { }
        key(Source; "Source Type", "Source No.") { }
        key(SourceDoc; "Source Table No.", "Source Subtype", "Source No.", "Source Line No.") { }
        key(Tracking; "Item No.", "Variant Code", "Lot No.", "Serial No.") { }
        key(LicensePlate; "LP No.") { }
    }

    trigger OnInsert()
    var
        QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
    begin
        // Orders entered on the BC page get the same numbering as the API path.
        if "No." = '' then
            "No." := QualityMgmt.GetNextOrderNo();
        if "Created DateTime" = 0DT then
            "Created DateTime" := CurrentDateTime();
        if "Due Date" = 0D then
            "Due Date" := Today();
    end;

    trigger OnDelete()
    var
        QualityLotHold: Codeunit "DOPSWHS Quality Lot Hold";
    begin
        // A deleted order must not leave its lot blocked (KIT-010); another
        // order that still holds the lot keeps the block.
        QualityLotHold.ReleaseHold(Rec);
    end;

    /// <summary>True while the order has no result yet (Open / In Progress).</summary>
    procedure IsUndecided(): Boolean
    begin
        exit(Status in [Status::Open, Status::InProgress]);
    end;

    /// <summary>
    /// True while this order keeps its lot/serial on quality hold: undecided, or
    /// failed without an executed release decision (accept with deviation /
    /// rework, which hands over to a re-inspection order).
    /// </summary>
    procedure IsHolding(): Boolean
    begin
        case Status of
            Status::Open, Status::InProgress:
                exit(true);
            Status::Failed:
                exit(not ("Decision Executed" and (Decision in [Decision::"Accept with Deviation", Decision::Rework])));
        end;
        exit(false);
    end;

    /// <summary>Converts a quantity of this order into the item's base unit (blank unit = base unit).</summary>
    procedure QuantityBase(Qty: Decimal): Decimal
    var
        ItemUnitOfMeasure: Record "Item Unit of Measure";
    begin
        if "Unit of Measure Code" = '' then
            exit(Qty);
        if ItemUnitOfMeasure.Get("Item No.", "Unit of Measure Code") then
            if ItemUnitOfMeasure."Qty. per Unit of Measure" <> 0 then
                exit(Qty * ItemUnitOfMeasure."Qty. per Unit of Measure");
        exit(Qty);
    end;
}
