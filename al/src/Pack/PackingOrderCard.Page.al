page 72362 "DOPSWHS Packing Order Card"
{
    PageType = Card;
    Caption = 'Sipariş Paketleme';
    SourceTable = "DOPSWHS Packing Order";
    ApplicationArea = All;
    UsageCategory = Tasks;
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            group(General)
            {
                field("Sales Order No."; Rec."Sales Order No.") { ApplicationArea = All; Caption = 'Satış Siparişi'; Editable = false; }
                field("Customer Name"; Rec."Customer Name") { ApplicationArea = All; Caption = 'Müşteri'; Editable = false; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; Caption = 'Lokasyon'; Editable = false; }
                field("Pick No."; Rec."Pick No.") { ApplicationArea = All; Caption = 'Toplama No.'; Editable = false; }
                field(Status; Rec.Status) { ApplicationArea = All; Caption = 'Durum'; Editable = false; }
                field("Started By User"; Rec."Started By User")
                {
                    ApplicationArea = All;
                    Caption = 'Paketleyen';
                    Editable = false;
                    ToolTip = 'Paketlemeyi üstlenen WMS operatörü. Terminalde paketlemeye başlayan kişi otomatik yazılır.';
                }
                field(BoxText; BoxText)
                {
                    ApplicationArea = All;
                    Caption = 'Kutu';
                    Editable = false;
                    ToolTip = 'Bu siparişin kutusu (LP). Ürünler bitince kutu okutulmadan sipariş kapanmaz.';
                    StyleExpr = BoxStyle;
                }
                field(ScanHere; ScanValue)
                {
                    Caption = 'Ürün Barkodu Okut';
                    ApplicationArea = All;
                    Editable = Rec.Status = Rec.Status::"In Progress";
                    QuickEntry = true;

                    trigger OnValidate()
                    begin
                        ProcessScan();
                    end;
                }
                field(Instruction; InstructionText) { Caption = 'Durum'; ApplicationArea = All; Editable = false; StyleExpr = InstructionStyle; }
            }
            part(Lines; "DOPSWHS Pack Session Subform")
            {
                ApplicationArea = All;
                SubPageLink = "Session Entry No." = field("Session Entry No.");
                UpdatePropagation = Both;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(StartPacking)
            {
                Caption = 'Paketlemeyi Başlat';
                ApplicationArea = All;
                Image = Start;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                Enabled = Rec.Status = Rec.Status::Ready;

                trigger OnAction()
                var
                    PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
                begin
                    PackMgmt.StartOrderSession(Rec."Sales Order No.");
                    Rec.Get(Rec."Sales Order No.");
                    UpdateInstruction();
                    CurrPage.Update(false);
                end;
            }
            action(ScanItem)
            {
                Caption = 'Okutmayı İşle';
                ApplicationArea = All;
                Image = BarCode;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::"In Progress";

                trigger OnAction()
                begin
                    ProcessScan();
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        UpdateInstruction();
    end;

    local procedure ProcessScan()
    var
        PackMgmt: Codeunit "DOPSWHS Pack Station Mgmt";
        CompletedOrders: Text;
    begin
        if ScanValue.Trim() = '' then
            exit;
        Rec.TestField(Status, Rec.Status::"In Progress");
        CompletedOrders := PackMgmt.ScanItem(Rec."Session Entry No.", CopyStr(ScanValue.Trim(), 1, 20), 1);
        ScanValue := '';
        Rec.Get(Rec."Sales Order No.");
        if CompletedOrders <> '' then
            Message('Sipariş %1 tamamlandı.', CompletedOrders);
        UpdateInstruction();
        CurrPage.Update(false);
    end;

    local procedure UpdateInstruction()
    var
        PackLine: Record "DOPSWHS Pack Session Line";
        Remaining: Decimal;
        BoxLpNo: Code[20];
    begin
        // Kutu bilgisi: bu siparişin satırlarından ilk dolu "Box LP No.".
        BoxLpNo := '';
        if Rec."Session Entry No." <> 0 then begin
            PackLine.SetRange("Session Entry No.", Rec."Session Entry No.");
            PackLine.SetRange("Source Order No.", Rec."Sales Order No.");
            PackLine.SetFilter("Box LP No.", '<>%1', '');
            if PackLine.FindFirst() then
                BoxLpNo := PackLine."Box LP No.";
            PackLine.Reset();
        end;
        if BoxLpNo <> '' then begin
            BoxText := BoxLpNo;
            BoxStyle := 'Favorable';
        end else begin
            BoxText := 'Kutu okutulmadı';
            BoxStyle := 'Ambiguous';
        end;

        if Rec.Status = Rec.Status::Completed then begin
            InstructionText := 'Sipariş tamamlandı — sevk ve fatura kesildi.';
            InstructionStyle := 'Favorable';
            exit;
        end;
        if Rec.Status = Rec.Status::Ready then begin
            InstructionText := 'Paketlemeyi Başlat seçin.';
            InstructionStyle := 'Ambiguous';
            exit;
        end;
        PackLine.SetRange("Session Entry No.", Rec."Session Entry No.");
        PackLine.SetRange("Source Order No.", Rec."Sales Order No.");
        if PackLine.FindSet() then
            repeat
                Remaining += PackLine."Qty. Expected" - PackLine."Qty. Packed";
            until PackLine.Next() = 0;
        if Remaining > 0 then begin
            InstructionText := StrSubstNo('Eksik miktar: %1. Kırmızı satırlardaki ürünleri okutun.', Remaining);
            InstructionStyle := 'Unfavorable';
        end else if BoxLpNo = '' then begin
            // Ürünler bitti ama kutu yok — terminaldeki "KUTUYU OKUT" adımının karşılığı.
            InstructionText := 'Tüm ürünler paketlendi. Siparişi kapatmak için kutuyu okutun.';
            InstructionStyle := 'Ambiguous';
        end else begin
            InstructionText := 'Paketleme tamam, kapanış bekleniyor.';
            InstructionStyle := 'Favorable';
        end;
    end;

    var
        ScanValue: Text[100];
        InstructionText: Text[250];
        InstructionStyle: Text;
        BoxText: Text[50];
        BoxStyle: Text;
}
