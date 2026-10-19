page 72075 "DOPSWHS Count Sheet Card"
{
    Caption = 'Count Sheet';
    PageType = Card;
    SourceTable = "DOPSWHS Count Sheet Header";
    ApplicationArea = All;
    UsageCategory = Documents;

    layout
    {
        area(Content)
        {
            group(General)
            {
                Caption = 'General';
                field("No."; Rec."No.") { ApplicationArea = All; Editable = HeaderEditable; Visible = IsFirstRound; }
                field("Round Root No."; Rec."Round Root No.") { ApplicationArea = All; Visible = HasPreviousRound; }
                field("Count Round No."; RoundNo) { Caption = 'Sayım Turu'; ApplicationArea = All; Editable = false; }
                field("Previous Round No."; Rec."Previous Round No.") { ApplicationArea = All; Visible = false; }
                field("Next Round No."; Rec."Next Round No.") { ApplicationArea = All; Visible = false; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; Editable = HeaderEditable; }
                field("Zone Filter"; Rec."Zone Filter") { ApplicationArea = All; Editable = HeaderEditable; }
                field(Mode; Rec.Mode) { ApplicationArea = All; Editable = HeaderEditable; }
                field(Status; Rec.Status) { ApplicationArea = All; Editable = false; }
                field("V2 Scan Mode"; Rec."V2 Scan Mode")
                {
                    ApplicationArea = All;
                    Editable = HeaderEditable;
                    ToolTip = 'Terminalde yalnız barkod okutarak sayım (Sayım V2). Satırı olmayan açık belgede değiştirilebilir.';
                }
            }
            group(Progress)
            {
                Caption = 'Sayım Durumu';
                field(TotalLines; TotalLines)
                {
                    Caption = 'Toplam Satır';
                    ApplicationArea = All;
                    Editable = false;
                }
                field(CountedLines; CountedLines)
                {
                    Caption = 'Sayılan';
                    ApplicationArea = All;
                    Editable = false;
                    Style = Favorable;
                }
                field(RemainingLines; TotalLines - CountedLines)
                {
                    Caption = 'Kalan';
                    ApplicationArea = All;
                    Editable = false;
                    StyleExpr = RemainingStyle;
                }
                field(VarianceLines; VarianceLines)
                {
                    Caption = 'Farklı Satır';
                    ApplicationArea = All;
                    Editable = false;
                    StyleExpr = VarianceLinesStyle;
                }
            }
            part(Counters; "DOPSWHS Count Counter Part")
            {
                ApplicationArea = All;
                SubPageLink = "Sheet No." = field("No.");
                Editable = HeaderEditable;
            }
            part(PreviousRoundLines; "DOPSWHS Count Sheet Line Part")
            {
                Caption = 'Önceki tur · korunan sonuçlar';
                ApplicationArea = All;
                SubPageLink = "Sheet No." = field("Previous Round No.");
                Editable = false;
                Visible = HasPreviousRound;
            }
            part(Lines; "DOPSWHS Count Sheet Line Part")
            {
                ApplicationArea = All;
                SubPageLink = "Sheet No." = field("No.");
                Editable = HeaderEditable;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(StartNextRound)
            {
                Caption = 'Ad-hoc Sonrası Yeni Tur Başlat';
                ApplicationArea = All;
                Image = Refresh;
                Visible = IsActiveRound;
                Enabled = CanStartNextRound;
                ToolTip = 'İlk sayımı kaydedip Ad-hoc düzeltmelerini bitirdikten sonra kullanın. Mevcut sonuçları korur, güncel stok ve raflarla yeni turu oluşturur ve açar.';
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                    NextNo: Code[20];
                begin
                    CurrPage.SaveRecord();
                    Rec.Get(Rec."No.");
                    if Rec."Next Round No." <> '' then begin
                        OpenActiveRoundCard(Rec."Next Round No.");
                        exit;
                    end;
                    CountMgmt.ValidateNextRound(Rec."No.");
                    if not Confirm('Bu turdaki tüm sayıcılar sonuçlarını kaydetmiş ve Ad-hoc düzeltmeleri bitmiş olmalıdır. Mevcut sonuçlar korunacak; güncel stok ve raflarla yeni tur oluşturulup açılacak. Devam edilsin mi?', false) then
                        exit;
                    NextNo := CountMgmt.StartNextRound(Rec."No.");
                    OpenActiveRoundCard(NextNo);
                end;
            }
            action(OpenNextRound)
            {
                Caption = 'Aktif Sayım Turunu Aç';
                ApplicationArea = All;
                Image = NextRecord;
                Visible = HasNextRound;
                Enabled = HasNextRound;
                ToolTip = 'Bu eski turun devamı olan mevcut son turu açar. Yeni bir tur oluşturmaz. Sayıma devam etmek için kullanın.';
                trigger OnAction()
                begin
                    Rec.Get(Rec."No.");
                    if Rec."Next Round No." = '' then
                        Error('Bu sayımın sonraki turu henüz oluşturulmamış. İlk sayımı kaydedip Ad-hoc düzeltmelerini tamamladıktan sonra Ad-hoc Sonrası Yeni Tur Başlat eylemini kullanın. Önceki deneme hata verdiyse yeni tur oluşmamış olabilir.');
                    OpenActiveRoundCard(Rec."Next Round No.");
                end;
            }
            action(GenerateLines)
            {
                Caption = 'Satırları Üret';
                ApplicationArea = All;
                Image = CalculateLines;
                Enabled = HeaderEditable;
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                    LinesCreated: Integer;
                begin
                    LinesCreated := CountMgmt.GenerateLines(Rec."No.");
                    CurrPage.Update(false);
                    Message('%1 sayım satırı oluşturuldu.', LinesCreated);
                end;
            }
            action(Post)
            {
                Caption = 'Post';
                ApplicationArea = All;
                Image = Post;
                Enabled = HeaderEditable;
                trigger OnAction()
                var
                    CountMgmt: Codeunit "DOPSWHS Count Mgmt";
                    CountLine: Record "DOPSWHS Count Sheet Line";
                begin
                    if CountMgmt.HasLPBinFindings(Rec."No.") then
                        Error('Bu belge ilk sayımın raf düzeltme listesidir. LP Raf Düzeltme Listesi eylemini kullanın; Ad-hoc sonrası Yeni Tur Başlat eylemini kullanın.');
                    CountMgmt.ValidateBinReview(Rec."No.");
                    CountMgmt.EvaluateVariance(Rec."No.");
                    // BADE (2 Eki 2026): EvaluateVariance satırlara fark/tekrar sayım
                    // bayrağı yazar; yazma işlemi açıkken Page.RunModal yasak
                    // ("Form.RunModal yazma işlemlerinde izin verilmez"). Farklar
                    // yalnız analitik sonuçtur, inceleme penceresinden önce kaydedilir.
                    Commit();
                    CountLine.SetRange("Sheet No.", Rec."No.");
                    Page.RunModal(Page::"DOPSWHS Count Bin Review", CountLine);
                    if not Confirm('İncelediğiniz raf farkları stoklara işlensin mi?', false) then
                        exit;
                    CountMgmt.PostSheet(Rec."No.");
                    CurrPage.Update(false);
                end;
            }
            action(LPBinFindings)
            {
                Caption = 'LP Raf Düzeltme Listesi';
                ApplicationArea = All;
                Image = List;
                ToolTip = 'İlk sayımda farklı rafta bulunan LP kayıtlarını açar. Sistem rafı sayım anındaki değerdir; Ad-hoc sonrası da korunur. Pozitif sayılan miktarları esas alın.';
                trigger OnAction()
                var
                    Line: Record "DOPSWHS Count Sheet Line";
                begin
                    Line.SetRange("Sheet No.", Rec."No.");
                    Line.SetFilter("Found From Bin", '<>%1', '');
                    Page.Run(Page::"DOPSWHS Count Bin Review", Line);
                end;
            }
            action(PrintVarianceReport)
            {
                Caption = 'Print Variance Report';
                ApplicationArea = All;
                Image = PrintReport;
                trigger OnAction()
                var
                    CountLine: Record "DOPSWHS Count Sheet Line";
                begin
                    CountLine.SetRange("Sheet No.", Rec."No.");
                    Report.RunModal(Report::"DOPSWHS Count Variance", true, false, CountLine);
                end;
            }
        }
    }

    local procedure OpenActiveRoundCard(SheetNo: Code[20])
    var
        Target: Record "DOPSWHS Count Sheet Header";
        Visited: List of [Code[20]];
        CountCard: Page "DOPSWHS Count Sheet Card";
    begin
        Target.Get(SheetNo);
        while Target."Next Round No." <> '' do begin
            if Visited.Contains(Target."No.") then
                Error('Sayım turu bağlantılarında döngü var. Sistem yöneticisine başvurun.');
            Visited.Add(Target."No.");
            Target.Get(Target."Next Round No.");
        end;
        // Rec.Get alone leaves the original card's RunPageLink / view filters
        // in place. Replace the card instance so the old key cannot be restored
        // on refresh. Refresh the archived source before closing, without saving.
        Rec.Get(Rec."No.");
        CurrPage.Update(false);
        CountCard.SetRecord(Target);
        CountCard.Run();
        CurrPage.Close();
    end;

    trigger OnAfterGetCurrRecord()
    var
        CountLine: Record "DOPSWHS Count Sheet Line";
        CountMgmt: Codeunit "DOPSWHS Count Mgmt";
    begin
        RoundNo := CountMgmt.GetRoundNo(Rec);
        HasPreviousRound := Rec."Previous Round No." <> '';
        IsFirstRound := not HasPreviousRound;
        HasNextRound := Rec."Next Round No." <> '';
        IsActiveRound := not HasNextRound;
        HeaderEditable := (Rec.Status <> Rec.Status::Posted) and IsActiveRound;
        CanStartNextRound := HeaderEditable and Rec."V2 Scan Mode";
        TotalLines := 0;
        CountedLines := 0;
        VarianceLines := 0;
        CountLine.SetRange("Sheet No.", Rec."No.");
        if CountLine.FindSet() then
            repeat
                TotalLines += 1;
                if CountLine."Counted 1" or CountLine."Counted 2" or CountLine."Counted 3" or
                   (CountLine."Counted Qty 1" <> 0) or (CountLine."Counted Qty 2" <> 0) or (CountLine."Counted Qty 3" <> 0)
                then begin
                    CountedLines += 1;
                    if CountLine."Counted Qty 1" <> CountLine."System Qty" then
                        VarianceLines += 1;
                end;
            until CountLine.Next() = 0;
        if TotalLines > CountedLines then
            RemainingStyle := 'Attention'
        else
            RemainingStyle := 'Favorable';
        if VarianceLines > 0 then
            VarianceLinesStyle := 'Unfavorable'
        else
            VarianceLinesStyle := 'Favorable';
    end;

    var
        TotalLines: Integer;
        CountedLines: Integer;
        VarianceLines: Integer;
        RemainingStyle: Text;
        VarianceLinesStyle: Text;
        HeaderEditable: Boolean;
        HasPreviousRound: Boolean;
        IsFirstRound: Boolean;
        HasNextRound: Boolean;
        IsActiveRound: Boolean;
        CanStartNextRound: Boolean;
        RoundNo: Integer;
}
