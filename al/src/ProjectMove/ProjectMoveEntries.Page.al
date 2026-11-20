page 72205 "DOPSWHS Project Move Entries"
{
    PageType = List;
    SourceTable = "DOPSWHS Project Move Entry";
    SourceTableView = sorting("Entry No.") order(descending);
    Caption = 'Proje ve Sipariş Taşıma Kayıtları';
    ApplicationArea = All;
    UsageCategory = History;
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
                field("Moved At"; Rec."Moved At") { ApplicationArea = All; ToolTip = 'Taşımanın yapıldığı an.'; }
                field("Project No."; Rec."Project No.") { ApplicationArea = All; ToolTip = 'Ürünün hangi proje için taşındığı.'; }
                field("Project Description"; Rec."Project Description") { ApplicationArea = All; ToolTip = 'Projenin adı.'; }
                field("Sales Order No."; Rec."Sales Order No.") { ApplicationArea = All; ToolTip = 'Ürünün hangi satış siparişi için taşındığı.'; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; ToolTip = 'Taşınan madde.'; }
                field("Item Description"; Rec."Item Description") { ApplicationArea = All; ToolTip = 'Maddenin adı.'; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; ToolTip = 'Taşınan miktar (temel birim).'; }
                field("Unit of Measure Code"; Rec."Unit of Measure Code") { ApplicationArea = All; ToolTip = 'Miktarın birimi.'; }
                field("From Bin Code"; Rec."From Bin Code") { ApplicationArea = All; ToolTip = 'Ürünün alındığı raf.'; }
                field("To Bin Code"; Rec."To Bin Code") { ApplicationArea = All; ToolTip = 'Ürünün bırakıldığı raf ya da alan.'; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; ToolTip = 'Lokasyon.'; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; ToolTip = 'Lot numarası.'; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; ToolTip = 'Taşınan LP (varsa).'; }
                field("User Name"; Rec."User Name") { ApplicationArea = All; ToolTip = 'Taşımayı yapan terminal kullanıcısı.'; }
                field("User ID"; Rec."User ID") { ApplicationArea = All; Visible = false; ToolTip = 'Terminal kullanıcısının kodu.'; }
            }
        }
    }
}
