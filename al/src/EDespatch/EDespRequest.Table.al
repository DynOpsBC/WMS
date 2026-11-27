table 72453 "DOPSWHS EDesp Request"
{
    // Provider-agnostic e-despatch request of the handheld (ADR-TED-002). One row per posted or registered
    // source document. The e-transformation app owns the legal document; the connector mirrors its
    // number, ETTN and status here.
    Caption = 'E-Despatch Request';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS EDesp Requests";
    DrillDownPageId = "DOPSWHS EDesp Requests";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
        }
        field(2; "Source Type"; Enum "DOPSWHS EDesp Source Type")
        {
            Caption = 'Source Type';
        }
        field(3; "Source No."; Code[20])
        {
            Caption = 'Source No.';
        }
        field(4; "Transfer Order No."; Code[20])
        {
            Caption = 'Transfer Order No.';
        }
        field(5; "Location Code"; Code[10])
        {
            Caption = 'From Location';
            TableRelation = Location.Code;
        }
        field(6; "To Location Code"; Code[10])
        {
            Caption = 'To Location';
            TableRelation = Location.Code;
        }
        field(7; "To Bin Code"; Code[20])
        {
            Caption = 'To Bin';
        }
        field(8; "From Bin Code"; Code[20])
        {
            Caption = 'From Bin';
        }
        field(10; "Receiver Type"; Enum "DOPSWHS EDesp Receiver Type")
        {
            Caption = 'Receiver Type';
        }
        field(11; "Receiver No."; Code[20])
        {
            Caption = 'Receiver No.';
            TableRelation = if ("Receiver Type" = const(Vendor)) Vendor."No."
            else if ("Receiver Type" = const(Customer)) Customer."No.";
        }
        field(12; "Receiver Address Code"; Code[10])
        {
            Caption = 'Delivery Address Code';
        }
        field(13; "Receiver Name"; Text[150])
        {
            Caption = 'Receiver Name';
        }
        field(14; "Receiver Identification No."; Text[30])
        {
            Caption = 'Receiver VKN/TCKN';
        }
        field(15; "Receiver Alias"; Text[250])
        {
            Caption = 'Receiver Alias';
        }
        field(16; "Delivery Address"; Text[250])
        {
            Caption = 'Delivery Address';
        }
        field(17; Purpose; Enum "DOPSWHS EDesp Purpose")
        {
            Caption = 'Despatch Purpose';
        }
        field(18; "Receiver Registered"; Boolean)
        {
            Caption = 'Receiver Registered';
        }
        field(20; "Vehicle Plate No."; Text[20])
        {
            Caption = 'Vehicle Plate No.';
        }
        field(21; "Trailer Plate No."; Text[20])
        {
            Caption = 'Trailer Plate No.';
        }
        field(22; "Driver First Name"; Text[50])
        {
            Caption = 'Driver First Name';
        }
        field(23; "Driver Family Name"; Text[50])
        {
            Caption = 'Driver Family Name';
        }
        field(24; "Driver Identification No."; Text[20])
        {
            Caption = 'Driver Identification No.';
        }
        field(25; "Shipping Agent Code"; Code[10])
        {
            Caption = 'Carrier (Shipping Agent) Code';
            TableRelation = "Shipping Agent".Code;
        }
        field(26; "Actual Despatch DateTime"; DateTime)
        {
            Caption = 'Actual Despatch Date-Time';
        }
        field(27; Note; Text[250])
        {
            Caption = 'Note';
        }
        field(30; Status; Enum "DOPSWHS EDesp Status")
        {
            Caption = 'Status';
        }
        field(31; "Provider Code"; Text[30])
        {
            Caption = 'Provider';
        }
        field(32; "Provider Entry No."; Integer)
        {
            Caption = 'Provider Entry No.';
        }
        field(33; "Provider Document No."; Code[50])
        {
            Caption = 'E-Despatch No.';
        }
        field(34; ETTN; Guid)
        {
            Caption = 'ETTN';
        }
        field(35; "Provider Status Text"; Text[100])
        {
            Caption = 'Provider Status';
        }
        field(36; Editable; Boolean)
        {
            Caption = 'Editable';
        }
        field(37; "Last Error"; Text[2048])
        {
            Caption = 'Last Error';
        }
        field(38; "Attempt Count"; Integer)
        {
            Caption = 'Attempt Count';
        }
        field(39; "Skip Reason"; Text[250])
        {
            Caption = 'Skip Reason';
        }
        field(40; "Created At"; DateTime)
        {
            Caption = 'Created At';
        }
        field(41; "Last Attempt At"; DateTime)
        {
            Caption = 'Last Attempt At';
        }
        field(42; "Sent At"; DateTime)
        {
            Caption = 'Sent At';
        }
        field(43; "Operator User Id"; Code[50])
        {
            // Local WMS user of the handheld, not the shared service account (see README, authentication model).
            Caption = 'Operator';
        }
        field(44; "Printed A4"; Boolean)
        {
            Caption = 'Printed A4';
        }
        field(45; "Printed Thermal"; Boolean)
        {
            Caption = 'Printed 80 mm';
        }
        field(46; "Print Count"; Integer)
        {
            Caption = 'Print Count';
        }
        field(47; "Last Printed At"; DateTime)
        {
            Caption = 'Last Printed At';
        }
        field(50; "Idempotency Key"; Guid)
        {
            Caption = 'Idempotency Key';
        }
        field(51; "Fason Reference No."; Code[50])
        {
            Caption = 'Fason Reference No.';
        }
        field(52; "Fason Purchase Order No."; Code[20])
        {
            Caption = 'Fason Purchase Order No.';
        }
        field(53; "Legacy Outbox Entry No."; Integer)
        {
            Caption = 'Legacy Outbox Entry No.';
        }
        field(60; "Line Count"; Integer)
        {
            Caption = 'Line Count';
            FieldClass = FlowField;
            CalcFormula = count("DOPSWHS EDesp Request Line" where("Request Entry No." = field("Entry No.")));
            Editable = false;
        }
        field(61; "Total Quantity"; Decimal)
        {
            Caption = 'Total Quantity';
            FieldClass = FlowField;
            CalcFormula = sum("DOPSWHS EDesp Request Line".Quantity where("Request Entry No." = field("Entry No.")));
            DecimalPlaces = 0 : 5;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Source; "Source Type", "Source No.")
        {
        }
        key(Idempotency; "Idempotency Key")
        {
        }
        key(ByStatus; Status, "Created At")
        {
        }
        key(Provider; "Provider Entry No.")
        {
        }
    }

    trigger OnDelete()
    var
        RequestLine: Record "DOPSWHS EDesp Request Line";
    begin
        RequestLine.SetRange("Request Entry No.", "Entry No.");
        RequestLine.DeleteAll();
    end;

    procedure IsOpen(): Boolean
    begin
        exit(Status in [Status::Pending, Status::Draft, Status::Error, Status::WaitingAdapter]);
    end;
}
