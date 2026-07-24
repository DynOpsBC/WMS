page 72257 "DOPSWHS Quality Order Queue"
{
    // NOT: Bu sayfa bu ortamda derlenmedi (BC sembol paketi/sandbox erişimi yok).
    // Merge öncesi VS Code + AL derleyicisiyle veya bir BC sandbox'ta doğrulanmalı.
    //
    // GKK-05: depo yöneticisi için bekleyen Quality Order kuyruğu. Mobil tarafta
    // aynı veri QualityOrderApi.Page.al üzerinden zaten tüketiliyor; bu sayfa BC
    // web client tarafı için.

    PageType = List;
    ApplicationArea = All;
    UsageCategory = Lists;
    Caption = 'Quality Order Queue';
    SourceTable = "DOPSWHS Quality Order";
    Editable = false;

    layout
    {
        area(content)
        {
            repeater(Group)
            {
                field("No."; Rec."No.") { ApplicationArea = All; }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                    StyleExpr = StatusStyleExpr;
                }
                field("Source Type"; Rec."Source Type") { ApplicationArea = All; }
                field("Source No."; Rec."Source No.") { ApplicationArea = All; }
                field("Item No."; Rec."Item No.") { ApplicationArea = All; }
                field("Item Description"; Rec."Item Description") { ApplicationArea = All; }
                field(Quantity; Rec.Quantity) { ApplicationArea = All; }
                field("LP No."; Rec."LP No.") { ApplicationArea = All; }
                field("Location Code"; Rec."Location Code") { ApplicationArea = All; }
                field("Bin Code"; Rec."Bin Code") { ApplicationArea = All; }
                field("Created DateTime"; Rec."Created DateTime") { ApplicationArea = All; }
                field(Inspector; Rec.Inspector) { ApplicationArea = All; }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(PassOrder)
            {
                Caption = 'Onayla (Pass)';
                Image = Approve;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::Open;
                ToolTip = 'Seçili Quality Order''ı onaylar; LP normal akışa devam edebilir.';

                trigger OnAction()
                var
                    QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
                begin
                    QualityMgmt.Pass(Rec, CopyStr(UserId(), 1, 50), '');
                    CurrPage.Update(false);
                end;
            }
            action(FailOrder)
            {
                Caption = 'Reddet (Fail)';
                Image = Reject;
                ApplicationArea = All;
                Promoted = true;
                PromotedCategory = Process;
                Enabled = Rec.Status = Rec.Status::Open;
                ToolTip = 'Seçili Quality Order''ı reddeder; not girmeniz istenir.';

                trigger OnAction()
                var
                    QualityMgmt: Codeunit "DOPSWHS Quality Mgmt";
                    Setup: Record "DOPSWHS Setup";
                    Notes: Text[250];
                    QuarantineBin: Code[20];
                begin
                    if Setup.Get('') then
                        QuarantineBin := Setup."Default Quarantine Bin Code";
                    if not Dialog.InputQuery('Red nedeni', Notes) then
                        exit;
                    QualityMgmt.Fail(Rec, CopyStr(UserId(), 1, 50), '', Notes, QuarantineBin);
                    CurrPage.Update(false);
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        case Rec.Status of
            Rec.Status::Open, Rec.Status::InProgress:
                StatusStyleExpr := 'Ambiguous';
            Rec.Status::Failed:
                StatusStyleExpr := 'Unfavorable';
            Rec.Status::Passed, Rec.Status::Closed:
                StatusStyleExpr := 'Favorable';
        end;
    end;

    var
        StatusStyleExpr: Text;
}
