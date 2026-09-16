page 72069 "DOPSWHS LP Card"
{
    Caption = 'License Plate';
    PageType = Card;
    SourceTable = "DOPSWHS LP Header";
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Status; Rec.Status) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Parent LP No."; Rec."Parent LP No.") { ApplicationArea = All; }
                field("LP Template Code"; Rec."LP Template Code") { ApplicationArea = All; }
                field(SSCC; Rec.SSCC) { ApplicationArea = All; }
            }
            part(Lines; "DOPSWHS LP Line ListPart")
            {
                ApplicationArea = All;
                SubPageLink = "LP No." = field("No.");
            }
            group(Tracking)
            {
                field("Assigned Document Type"; Rec."Assigned Document Type") { ApplicationArea = All; }
                field("Assigned Document No."; Rec."Assigned Document No.") { ApplicationArea = All; }
                field("Built By User"; Rec."Built By User") { ApplicationArea = All; }
                field("Built DateTime"; Rec."Built DateTime") { ApplicationArea = All; }
                field("Last Modified DateTime"; Rec."Last Modified DateTime") { ApplicationArea = All; }
            }
            group(SourceDocument)
            {
                Caption = 'Belge / Sevk Bilgisi';
                field("Source Document Type"; Rec."Source Document Type") { ApplicationArea = All; }
                field("Source Document No."; Rec."Source Document No.") { ApplicationArea = All; }
                field("Source Document Date"; Rec."Source Document Date") { ApplicationArea = All; }
                field("External Document No."; Rec."External Document No.") { ApplicationArea = All; }
                field("Partner Type"; Rec."Partner Type") { ApplicationArea = All; }
                field("Partner No."; Rec."Partner No.") { ApplicationArea = All; }
                field("Partner Name"; Rec."Partner Name") { ApplicationArea = All; }
                field("Ship-to Code"; Rec."Ship-to Code") { ApplicationArea = All; }
                field("Ship-to Name"; Rec."Ship-to Name") { ApplicationArea = All; }
                field("Ship-to Address"; Rec."Ship-to Address") { ApplicationArea = All; }
                field("Ship-to City"; Rec."Ship-to City") { ApplicationArea = All; }
                field("Ship-to Post Code"; Rec."Ship-to Post Code") { ApplicationArea = All; }
                field("Ship-to Country Code"; Rec."Ship-to Country Code") { ApplicationArea = All; }
                field("Shipment Method Code"; Rec."Shipment Method Code") { ApplicationArea = All; }
                field("Shipping Agent Code"; Rec."Shipping Agent Code") { ApplicationArea = All; }
                field("Shipping Agent Service Code"; Rec."Shipping Agent Service Code") { ApplicationArea = All; }
                field("Container No."; Rec."Container No.") { ApplicationArea = All; }
                field("Seal No."; Rec."Seal No.") { ApplicationArea = All; }
            }
            group(Dimensions)
            {
                field("Weight kg"; Rec."Weight kg") { ApplicationArea = All; }
                field("Tare Weight kg"; Rec."Tare Weight kg") { ApplicationArea = All; }
                field("Length cm"; Rec."Length cm") { ApplicationArea = All; }
                field("Width cm"; Rec."Width cm") { ApplicationArea = All; }
                field("Height cm"; Rec."Height cm") { ApplicationArea = All; }
            }
            group(Notes)
            {
                field(NotesText; Rec.Notes) { ApplicationArea = All; MultiLine = true; Caption = 'Notes'; }
            }
        }
        area(FactBoxes)
        {
            part(NestTree; "DOPSWHS LP Factbox Bin")
            {
                ApplicationArea = All;
                SubPageLink = "Location Code" = field("Location Code"),
                              "Bin Code" = field("Bin Code");
            }
            part(MovementLedger; "DOPSWHS LP Movement Ledger")
            {
                ApplicationArea = All;
                SubPageLink = "LP No." = field("No.");
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PrintLabel)
            {
                ApplicationArea = All;
                Caption = 'Etiket Yazdır';
                ToolTip = 'LP şablonunun tasarımıyla (palet/koli/kutu/çuval) ve şablondaki kopya sayısıyla etiketi basar.';
                Image = Print;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    Dispatcher: Codeunit "DOPSWHS Print Dispatcher";
                begin
                    Dispatcher.PrintLPLabel(Rec, '', 0);
                    Message(LabelQueuedMsg, Rec."No.");
                end;
            }
            action(PullFromDocument)
            {
                ApplicationArea = All;
                Caption = 'Belgeden Satırları Çek';
                ToolTip = 'Seçilen belgenin madde satırlarını (lot/seri dağılımıyla) bu LP''nin içeriğine kopyalar ve belge bilgisini LP''ye yazar.';
                Image = GetLines;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::Open;

                trigger OnAction()
                var
                    DocumentLink: Codeunit "DOPSWHS LP Document Link";
                    Dialog: Page "DOPSWHS LP Pull Document";
                    DocType: Enum "DOPSWHS Assigned Doc Type";
                    DocNo: Code[20];
                    Added: Integer;
                begin
                    Dialog.SetDefaults(Rec."Assigned Document Type", Rec."Assigned Document No.");
                    if Dialog.RunModal() <> Action::OK then
                        exit;
                    Dialog.GetSelection(DocType, DocNo);
                    Added := DocumentLink.PullFromDocument(Rec, DocType, DocNo);
                    CurrPage.Update(false);
                    Message(LinesPulledMsg, Added, DocNo);
                end;
            }
            action(RefreshSnapshot)
            {
                ApplicationArea = All;
                Caption = 'Belge Bilgisini Yenile';
                ToolTip = 'Müşteri/tedarikçi, sevk adresi ve sevkiyat yöntemini kaynak belgeden yeniden okur.';
                Image = Refresh;

                trigger OnAction()
                var
                    DocumentLink: Codeunit "DOPSWHS LP Document Link";
                begin
                    DocumentLink.RefreshSnapshot(Rec);
                    CurrPage.Update(false);
                end;
            }
            action(PrintPackingList)
            {
                ApplicationArea = All;
                Caption = 'Paketleme Listesi';
                ToolTip = 'Bu LP ve içindeki kapların palet/koli/kutu hiyerarşisini, SSCC ve ağırlıklarını listeler.';
                Image = PrintReport;
                Promoted = true;
                PromotedCategory = Report;

                trigger OnAction()
                var
                    PackingList: Codeunit "DOPSWHS Packing List Mgt.";
                begin
                    PackingList.RunForLp(Rec."No.");
                end;
            }
        }
    }

    var
        LabelQueuedMsg: Label '%1 etiketi yazıcıya gönderildi.', Comment = '%1 LP no';
        LinesPulledMsg: Label '%1 satır %2 belgesinden LP''ye çekildi.', Comment = '%1 count, %2 doc no';
}
