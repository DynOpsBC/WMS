table 72013 "DOPSWHS LP Template"
{
    Caption = 'DOPSWHS LP Template';
    DataClassification = CustomerContent;
    LookupPageId = "DOPSWHS LP Template List";
    DrillDownPageId = "DOPSWHS LP Template List";

    fields
    {
        field(1; "Code"; Code[20]) { Caption = 'Code'; DataClassification = CustomerContent; }
        field(2; Description; Text[100]) { Caption = 'Description'; DataClassification = CustomerContent; }
        field(10; "Default Tare Weight kg"; Decimal) { Caption = 'Default Tare Weight kg'; DataClassification = CustomerContent; }
        field(20; "Default Length cm"; Decimal) { Caption = 'Default Length cm'; DataClassification = CustomerContent; }
        field(21; "Default Width cm"; Decimal) { Caption = 'Default Width cm'; DataClassification = CustomerContent; }
        field(22; "Default Height cm"; Decimal) { Caption = 'Default Height cm'; DataClassification = CustomerContent; }
        field(30; "Max Weight kg"; Decimal) { Caption = 'Max Weight kg'; DataClassification = CustomerContent; }
        field(40; "Label Report ID"; Integer)
        {
            Caption = 'Label Report ID';
            DataClassification = CustomerContent;
            TableRelation = AllObjWithCaption."Object ID" where("Object Type" = const(Report));
        }
        field(50; "No. Series"; Code[20]) { Caption = 'No. Series'; DataClassification = CustomerContent; TableRelation = "No. Series"; }
        field(60; "Allow Mixed Items"; Boolean) { Caption = 'Allow Mixed Items'; DataClassification = CustomerContent; }
        field(61; "Allow Mixed Lots"; Boolean) { Caption = 'Allow Mixed Lots'; DataClassification = CustomerContent; }
        field(70; "Reusable"; Boolean)
        {
            // Tote / yeniden kullanılabilir kap: pick sevk arası taşır, işi bitince
            // Release ile tekrar Built'e döner ve yeniden kullanılır (tek kullanımlık
            // paletin aksine). Müşteri toplantısı: plastik sepet = tote.
            Caption = 'Reusable (Tote)';
            DataClassification = CustomerContent;
        }
        // EMU/DKÇ (15 Eyl 2026): one "Print label" per LP; the template decides
        // the design (pallet / carton / box / sack), whether the label lists the
        // contents (inner layers) and how many copies come out.
        field(80; "Container Kind"; Enum "DOPSWHS LP Container Kind")
        {
            Caption = 'Container Kind';
            DataClassification = CustomerContent;
        }
        field(81; "Label Design"; Enum "DOPSWHS LP Label Design")
        {
            Caption = 'Label Design';
            DataClassification = CustomerContent;
        }
        field(82; "Label Includes Contents"; Boolean)
        {
            Caption = 'Label Includes Contents';
            DataClassification = CustomerContent;
        }
        field(83; "Label Copies"; Integer)
        {
            Caption = 'Label Copies';
            DataClassification = CustomerContent;
            InitValue = 1;
            MinValue = 0;
            MaxValue = 10;
        }
    }

    keys { key(PK; "Code") { Clustered = true; } }
}
