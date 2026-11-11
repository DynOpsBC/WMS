page 72477 "DOPSWHS Project Issue Entries"
{
    // Kitoko/Element4 #3338: proje bazında stok çıkış listesi. Terminalden saha iş emrine
    // yapılan çıkışlar proje defterine madde kullanımı olarak düşer; Belge No. = saha iş emri,
    // Harici Belge No. = terminal kullanıcısı.
    Caption = 'WMS Proje Malzeme Çıkışları';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    SourceTable = "Job Ledger Entry";
    SourceTableView = sorting("Entry No.") order(descending) where(Type = const(Item), "Entry Type" = const(Usage));
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Entries)
            {
                field("Posting Date"; Rec."Posting Date") { ApplicationArea = All; }
                field("Job No."; Rec."Job No.") { ApplicationArea = All; Caption = 'Proje No.'; }
                field("Job Task No."; Rec."Job Task No.") { ApplicationArea = All; Caption = 'Proje Görevi No.'; }
                field("Document No."; Rec."Document No.") { ApplicationArea = All; Caption = 'Saha İş Emri / Belge No.'; }
                field("No."; Rec."No.") { ApplicationArea = All; Caption = 'Madde No.'; }
                field(Description; Rec.Description) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; }
                field("Total Cost (LCY)"; Rec."Total Cost (LCY)") { ApplicationArea = All; }
                field("Global Dimension 1 Code"; Rec."Global Dimension 1 Code") { ApplicationArea = All; }
                field("Global Dimension 2 Code"; Rec."Global Dimension 2 Code") { ApplicationArea = All; }
                field("External Document No."; Rec."External Document No.") { ApplicationArea = All; Caption = 'Terminal Kullanıcısı'; }
                field("Entry No."; Rec."Entry No.") { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Navigation)
        {
            action(Dimensions)
            {
                ApplicationArea = All;
                Caption = 'Boyutlar';
                Image = Dimensions;
                ToolTip = 'Kaydın boyutlarını (PROJE dahil) gösterir.';
                trigger OnAction()
                begin
                    Rec.ShowDimensions();
                end;
            }
        }
    }
}
