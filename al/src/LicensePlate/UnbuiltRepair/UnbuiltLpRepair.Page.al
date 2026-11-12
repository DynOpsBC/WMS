page 72204 "DOPSWHS Unbuilt LP Repair"
{
    // BADE 1.14.1.186: bozulan LP'lerin ön izlemesi ve onarımı.
    Caption = 'Bozulan LP Onarımı';
    PageType = List;
    ApplicationArea = All;
    UsageCategory = Tasks;
    SourceTable = "DOPSWHS Unbuilt LP Repair Buf.";
    SourceTableTemporary = true;
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("LP No."; Rec."LP No.") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Lot No."; Rec."Lot No.") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("Unit of Measure"; Rec."Unit of Measure") { ApplicationArea = All; }
                field("Loose Qty. (Base)"; Rec."Loose Qty. (Base)") { ApplicationArea = All; }
                field(Result; Rec.Result) { ApplicationArea = All; StyleExpr = ResultStyle; }
                field("LP Ready"; Rec."LP Ready") { ApplicationArea = All; }
                field("Unbuilt By"; Rec."Unbuilt By") { ApplicationArea = All; }
                field("Unbuilt At"; Rec."Unbuilt At") { ApplicationArea = All; }
                field(Note; Rec.Note) { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; Visible = false; }
                field("Unbuilt Ledger Entry No."; Rec."Unbuilt Ledger Entry No.") { ApplicationArea = All; Visible = false; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RefreshAction)
            {
                ApplicationArea = All;
                Caption = 'Yenile';
                Image = Refresh;
                ToolTip = 'Bozulmuş LP''leri yeniden tarar. Veri değiştirmez.';
                trigger OnAction()
                begin
                    Reload();
                end;
            }
            action(RepairListedAction)
            {
                ApplicationArea = All;
                Caption = 'Listelenen Uygun LP''leri Onar';
                Image = Reuse;
                ToolTip = 'Geçerli süzgeçte görünen ve bütün satırları "Onarılabilir" olan LP''lerin içeriğini geri yazar ve LP''yi yeniden "Oluşturuldu" yapar. Önce Bozan Kullanıcı / Bozulma Zamanı ile süzün.';
                trigger OnAction()
                var
                    Repair: Codeunit "DOPSWHS Unbuilt LP Repair";
                    LpNos: List of [Code[20]];
                    LpNo: Code[20];
                    Done: Integer;
                begin
                    if Rec.FindSet() then
                        repeat
                            if Rec."LP Ready" and (Rec.Result = Rec.Result::Ready) and not LpNos.Contains(Rec."LP No.") then
                                LpNos.Add(Rec."LP No.");
                        until Rec.Next() = 0;
                    if LpNos.Count() = 0 then begin
                        Message('Geçerli süzgeçte onarılabilir LP yok.');
                        exit;
                    end;
                    if not Confirm('%1 LP onarılacak: içerik geçmişten geri yazılır ve LP yeniden "Oluşturuldu" olur. Devam edilsin mi?', false, LpNos.Count()) then
                        exit;
                    foreach LpNo in LpNos do begin
                        Repair.RepairLp(LpNo);
                        Done += 1;
                    end;
                    Reload();
                    Message('%1 LP onarıldı.', Done);
                end;
            }
            action(RepairSelectedAction)
            {
                ApplicationArea = All;
                Caption = 'Seçili LP''yi Onar (fazla stokla)';
                Image = Approve;
                ToolTip = 'Notunda "fazla LP''siz stok" yazan tek LP''yi, paleti fiziksel olarak doğruladıktan sonra onarır. Stok geçmişteki miktardan azsa onarmaz.';
                trigger OnAction()
                var
                    Repair: Codeunit "DOPSWHS Unbuilt LP Repair";
                    LpNo: Code[20];
                begin
                    LpNo := Rec."LP No.";
                    if LpNo = '' then
                        exit;
                    if not Confirm('%1 LP''si geçmişteki içeriğiyle onarılacak. Paletin rafta olduğunu ve miktarını doğruladınız mı?', false, LpNo) then
                        exit;
                    Repair.RepairLp(LpNo, true);
                    Reload();
                    Message('%1 onarıldı.', LpNo);
                end;
            }
            action(LedgerAction)
            {
                ApplicationArea = All;
                Caption = 'LP Hareket Geçmişi';
                Image = History;
                ToolTip = 'Seçili LP''nin hareket geçmişini açar.';
                trigger OnAction()
                var
                    Ledger: Record "DOPSWHS LP Movement Ledger";
                begin
                    Ledger.SetRange("LP No.", Rec."LP No.");
                    Page.Run(Page::"DOPSWHS LP Movement Ledger", Ledger);
                end;
            }
        }
        area(Promoted)
        {
            actionref(RefreshPromoted; RefreshAction) { }
            actionref(RepairPromoted; RepairListedAction) { }
            actionref(LedgerPromoted; LedgerAction) { }
        }
    }

    var
        ResultStyle: Text;

    trigger OnOpenPage()
    begin
        Reload();
    end;

    trigger OnAfterGetRecord()
    begin
        case Rec.Result of
            Rec.Result::Ready:
                ResultStyle := 'Favorable';
            Rec.Result::"Insufficient Stock":
                ResultStyle := 'Unfavorable';
            else
                ResultStyle := 'Ambiguous';
        end;
    end;

    local procedure Reload()
    var
        Repair: Codeunit "DOPSWHS Unbuilt LP Repair";
        Filters: Text;
    begin
        Filters := Rec.GetView(false);
        Repair.Analyze(Rec);
        Rec.SetView(Filters);
        if Rec.FindFirst() then;
        CurrPage.Update(false);
    end;
}
