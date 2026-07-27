table 72360 "DOPSWHS WMS Activity Log"
{
    // Terminal operatör aktiviteleri (toplama, paketleme, kayıt vb.) için denetim kaydı.
    // Android app her işlem (scan, assign, complete) sonrası POST /wmsActivityLog ile event'i gönderir.
    // BC bu tabloyu tutar ve WMS Activity Log sayfasında yönetici/supervisor görebilir.
    Caption = 'WMS Activity Log';
    DataClassification = EndUserIdentifiableInformation;
    Access = Public;

    fields
    {
        field(1; "Entry No."; BigInteger)
        {
            Caption = 'Entry No.';
            AutoIncrement = true;
            Editable = false;
        }
        field(10; "Timestamp"; DateTime)
        {
            Caption = 'Timestamp';
            Editable = false;
        }
        field(20; "Local User"; Code[20])
        {
            Caption = 'WMS Operator';
            TableRelation = "DOPSWHS Local User".Username;
            Editable = false;
        }
        field(21; "User Display Name"; Text[100])
        {
            Caption = 'Operator Name';
            Editable = false;
        }
        field(30; "Action"; Code[30])
        {
            Caption = 'Action';
            Editable = false;
            ToolTip = 'ScanItem, AssignPick, StartPacking, CompleteOrder, RegisterReceipt, etc.';
        }
        field(31; "Action Status"; Option)
        {
            Caption = 'Status';
            OptionMembers = Success, Fail, Timeout;
            Editable = false;
        }
        field(40; "Document Type"; Code[20])
        {
            Caption = 'Document Type';
            Editable = false;
            ToolTip = 'Pick, PutAway, Shipment, Packing Order, etc.';
        }
        field(41; "Document No."; Code[20])
        {
            Caption = 'Document No.';
            Editable = false;
        }
        field(42; "Line No."; Integer)
        {
            Caption = 'Line No.';
            Editable = false;
        }
        field(50; "Item No."; Code[20])
        {
            Caption = 'Item No.';
            TableRelation = Item.No.;
            Editable = false;
        }
        field(51; "Quantity"; Decimal)
        {
            Caption = 'Quantity';
            DecimalPlaces = 0 : 5;
            Editable = false;
        }
        field(52; "Unit of Measure Code"; Code[10])
        {
            Caption = 'UOM';
            TableRelation = "Unit of Measure".Code;
            Editable = false;
        }
        field(60; "Details"; Text[500])
        {
            Caption = 'Details';
            Editable = false;
            ToolTip = 'JSON details: error message, bin code, lot no, serial no, etc.';
        }
    }

    keys
    {
        key(PK; "Entry No.") { Clustered = true; }
        key(Timestamp; Timestamp) { }
        key(OperatorTime; "Local User", Timestamp) { }
        key(DocumentTime; "Document No.", Timestamp) { }
    }
}
