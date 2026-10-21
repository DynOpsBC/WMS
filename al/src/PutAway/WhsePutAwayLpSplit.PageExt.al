/// <summary>
/// BADE (21 Eki 2026): a put-away created from standard BC ("Create Put-away" on a
/// posted receipt or the put-away worksheet) has one Take/Place pair without LP and
/// the terminal cannot handle it. This action splits it by the LPs in the Take bin.
/// </summary>
pageextension 72328 "DOPSWHS Whse PutAway LP Split" extends "Warehouse Put-away"
{
    actions
    {
        addlast("F&unctions")
        {
            action(DOPSWHSSplitByBinLPs)
            {
                ApplicationArea = All;
                Caption = 'LP''ye göre böl';
                Image = Split;
                ToolTip = 'LP''siz Al/Koy satırlarını, Al gözünde duran LP''lere göre böler: her LP için bir Al ve bir Koy satırı oluşur ve LP bu yerleştirmeye atanır. Silinmiş bir belgeye atanmış kalan LP''ler önce serbest bırakılır. LP''lere sığmayan miktar LP''siz satırda kalır; satır miktarından fazlası asla oluşmaz.';

                trigger OnAction()
                var
                    ReceiptMgmt: Codeunit "DOPSWHS Receipt Mgmt";
                    LpCount: Integer;
                    LineCount: Integer;
                    CreatedCount: Integer;
                    RemainderBaseQty: Decimal;
                    RemainderText: Text;
                begin
                    ReceiptMgmt.PreviewSplitPutAwayByBinLPs(Rec."No.", LpCount, LineCount, RemainderBaseQty);
                    if LpCount = 0 then begin
                        Message('Bölünecek satır bulunamadı. LP''siz ve henüz işlenmemiş Al/Koy satırı ya da Al gözünde bu ürün/lot için uygun LP yok. Hiçbir şey değişmedi.');
                        exit;
                    end;
                    if RemainderBaseQty > 0 then
                        RemainderText := StrSubstNo(' LP''lere sığmayan %1 (temel birim) LP''siz satırda kalacak.', RemainderBaseQty);
                    if not Confirm('Gözdeki %1 LP''ye göre %2 satır (%1 Al/Koy çifti) oluşturulacak.%3 Devam edilsin mi?', false, LpCount, LineCount, RemainderText) then
                        exit;
                    CreatedCount := ReceiptMgmt.SplitPutAwayByBinLPs(Rec."No.");
                    CurrPage.Update(false);
                    Message('%1 LP için %2 yerleştirme satırı LP ile işaretlendi. Terminalden yerleştirmeye devam edebilirsiniz.', CreatedCount div 2, CreatedCount);
                end;
            }
        }
        addlast(Category_Process)
        {
            actionref(DOPSWHSSplitByBinLPs_Promoted; DOPSWHSSplitByBinLPs) { }
        }
    }
}
