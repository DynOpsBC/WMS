page 72483 "DOPSWHS LP Line ListPart"
{
    Caption = 'LP Lines';
    PageType = ListPart;
    SourceTable = "DOPSWHS LP Line";
    ApplicationArea = All;
    AutoSplitKey = true;
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Line No."; Rec."Line No.") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Variant Code"; Rec."Variant Code") { ApplicationArea = All; }
                field("Unit of Measure"; Rec."Unit of Measure") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field("Serial No."; Rec."Serial No.") { ApplicationArea = All; }
                field("Package No."; Rec."Package No.") { ApplicationArea = All; }
                field("Child LP No."; Rec."Child LP No.") { ApplicationArea = All; }
                field("Expiration Date"; Rec."Expiration Date") { ApplicationArea = All; }
                field("Source LP No."; Rec."Source LP No.") { ApplicationArea = All; ToolTip = 'Bu satırın toplandığı/aktarıldığı kaynak palet.'; }
                field("Source Item Ledger Entry No."; Rec."Source Item Ledger Entry No.")
                {
                    ApplicationArea = All;
                    Caption = 'Kaynak Giriş No.';
                    Editable = false;
                    ToolTip = 'Bu satırın alındığı kesin madde defteri girişi.';
                }
                field("Source Document No."; Rec."Source Document No.")
                {
                    ApplicationArea = All;
                    Caption = 'Kaynak Belge No.';
                    Editable = false;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(LinkStockSource)
            {
                ApplicationArea = All;
                Caption = 'Kaynak Girişi Bağla';
                ToolTip = 'Kaynağı eksik stok satırını seçtiğiniz madde defteri girişine bağlar. Stok miktarını veya rafını değiştirmez.';
                Image = Entries;
                trigger OnAction()
                var
                    LP: Record "DOPSWHS LP Header";
                    Entry: Record "Item Ledger Entry";
                    EntryLookup: Page "Item Ledger Entries";
                    LPManagement: Codeunit "DOPSWHS LP Management";
                begin
                    Rec.TestField("Item No.");
                    if Rec."Source Item Ledger Entry No." <> 0 then
                        Error('Bu satır zaten %1 girişine bağlıdır.', Rec."Source Item Ledger Entry No.");
                    LP.Get(Rec."LP No.");
                    Entry.SetRange("Item No.", Rec."Item No.");
                    Entry.SetRange("Variant Code", Rec."Variant Code");
                    Entry.SetRange("Lot No.", Rec."Lot No.");
                    Entry.SetRange("Serial No.", Rec."Serial No.");
                    Entry.SetRange("Location Code", LP."Location Code");
                    Entry.SetFilter(Quantity, '>0');
                    Entry.SetFilter("Remaining Quantity", '>0');
                    EntryLookup.SetTableView(Entry);
                    EntryLookup.LookupMode(true);
                    if EntryLookup.RunModal() <> Action::LookupOK then
                        exit;
                    EntryLookup.GetRecord(Entry);
                    LPManagement.LinkStockLineSource(LP, Rec."Line No.", Entry."Entry No.");
                    CurrPage.Update(false);
                end;
            }
        }
    }
}
